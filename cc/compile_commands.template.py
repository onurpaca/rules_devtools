"""Generate compile_commands.json from Bazel aquery output.

Three constants below (TARGET_FLAG_PAIRS, EXCLUDE_HEADERS,
EXCLUDE_EXTERNAL_SOURCES) are populated at build time by the expand_template
rule in compile_commands.bzl; the values committed in source are placeholders.

Attribution: the aquery-driven approach and the use of
`mnemonic("CppCompile|ObjcCompile|CudaCompile", deps(...))` to enumerate
compile actions are derived from
https://github.com/hedronvision/bazel-compile-commands-extractor
(Apache-2.0). See NOTICE at the repository root.
"""

import json
import os
import pathlib
import re
import shlex
import subprocess
import sys


# Baked-in configuration
TARGET_FLAG_PAIRS = [
        # __TARGETS__
]
EXCLUDE_HEADERS = __EXCLUDE_HEADERS__
EXCLUDE_EXTERNAL_SOURCES = __EXCLUDE_EXTERNAL_SOURCES__


def get_workspace_root():
    """Get the workspace root from environment."""
    root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not root:
        print("\033[0;31mError:\033[0m Must be run via 'bazel run'.", file=sys.stderr)
        sys.exit(1)
    return root


def get_execution_root(workspace_root):
    """Get Bazel's execution root."""
    result = subprocess.run(
        ["bazel", "info", "execution_root"],
        capture_output=True, text=True, cwd=workspace_root,
    )
    if result.returncode != 0:
        print("\033[0;31mError:\033[0m Failed to get execution root.", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def get_output_base(workspace_root):
    """Get Bazel's output base."""
    result = subprocess.run(
        ["bazel", "info", "output_base"],
        capture_output=True, text=True, cwd=workspace_root,
    )
    if result.returncode != 0:
        print("\033[0;31mError:\033[0m Failed to get output base.", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def run_aquery(workspace_root, target, extra_flags):
    """Run bazel aquery and return the JSON output."""
    query = f'mnemonic("CppCompile|ObjcCompile|CudaCompile", deps({target}))'

    cmd = ["bazel", "aquery", query, "--output=jsonproto"]
    if extra_flags:
        cmd.extend(shlex.split(extra_flags))

    # Pass through any extra args from command line
    extra_args = [a for a in sys.argv[1:] if not a.startswith("--")]
    cmd.extend(extra_args)

    print(f"\033[0;34mRunning aquery for {target}...\033[0m", file=sys.stderr)
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=workspace_root)

    if result.returncode != 0:
        print(f"\033[0;31mError:\033[0m aquery failed for {target}.", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return None

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as e:
        print(f"\033[0;31mError:\033[0m Failed to parse aquery JSON: {e}", file=sys.stderr)
        return None


def resolve_path(path, execution_root, workspace_root, output_base=None):
    """Convert a Bazel path to an absolute path.

    Tries multiple roots in order: workspace, execution root, output_base/external.
    Always returns an absolute path (never leaves paths relative).
    """
    if not path:
        return path

    # Already absolute
    if os.path.isabs(path):
        return os.path.normpath(path)

    # External workspace paths — check execution root first, then output_base
    if path.startswith("external/"):
        full_path = os.path.normpath(os.path.join(execution_root, path))
        if os.path.exists(full_path):
            return full_path
        # On Windows, external repos live under output_base/external/
        if output_base:
            full_path = os.path.normpath(os.path.join(output_base, path))
            if os.path.exists(full_path):
                return full_path
        return os.path.normpath(os.path.join(execution_root, path))

    # Bazel-out paths (generated files)
    if path.startswith("bazel-out/"):
        return os.path.normpath(os.path.join(execution_root, path))

    # Regular workspace-relative path
    full_path = os.path.normpath(os.path.join(workspace_root, path))
    if os.path.exists(full_path):
        return full_path

    # Try execution root
    return os.path.normpath(os.path.join(execution_root, path))


def is_source_file(path):
    """Check if a path looks like a C/C++ source or header file."""
    extensions = {'.c', '.cc', '.cpp', '.cxx', '.c++', '.C',
                  '.h', '.hh', '.hpp', '.hxx', '.h++', '.H',
                  '.m', '.mm',  # Objective-C
                  '.cu', '.cuh'}  # CUDA
    return pathlib.Path(path).suffix in extensions


def is_header_file(path):
    """Check if a path is a header file."""
    extensions = {'.h', '.hh', '.hpp', '.hxx', '.h++', '.H', '.cuh', '.inc'}
    return pathlib.Path(path).suffix in extensions


def is_external_path(path):
    """Check if a path is from an external workspace."""
    return "/external/" in path or path.startswith("external/")


def extract_compile_commands(aquery_output, execution_root, workspace_root, output_base=None):
    """Extract compile commands from aquery JSON output."""
    if not aquery_output:
        return []

    commands = []
    actions = aquery_output.get("actions", [])

    # Build a path fragment map (Bazel 8+ uses pathFragmentId instead of execPath)
    path_fragments = {}
    for pf in aquery_output.get("pathFragments", []):
        frag_id = pf["id"]
        label = pf.get("label", "")
        parent_id = pf.get("parentId")
        if parent_id and parent_id in path_fragments:
            path_fragments[frag_id] = path_fragments[parent_id] + "/" + label
        else:
            path_fragments[frag_id] = label

    # Resolve artifact paths: execPath (Bazel ≤7) or pathFragmentId (Bazel 8+)
    artifacts = {}
    for a in aquery_output.get("artifacts", []):
        if "execPath" in a:
            artifacts[a["id"]] = a["execPath"]
        else:
            artifacts[a["id"]] = path_fragments.get(a.get("pathFragmentId", 0), "")

    # Build dep set map
    dep_sets = {}
    for ds in aquery_output.get("depSetOfFiles", []):
        ds_id = ds["id"]
        direct = ds.get("directArtifactIds", [])
        transitive = ds.get("transitiveDepSetIds", [])
        dep_sets[ds_id] = {"direct": direct, "transitive": transitive}

    for action in actions:
        mnemonic = action.get("mnemonic", "")
        if mnemonic not in ("CppCompile", "ObjcCompile", "CudaCompile"):
            continue

        arguments = action.get("arguments", [])
        if not arguments:
            continue

        # Find the source file from inputs
        input_dep_set_ids = action.get("inputDepSetIds", [])
        input_artifact_ids = set()

        # Resolve dep sets to get all input artifact IDs
        stack = list(input_dep_set_ids)
        visited = set()
        while stack:
            ds_id = stack.pop()
            if ds_id in visited:
                continue
            visited.add(ds_id)
            if ds_id in dep_sets:
                input_artifact_ids.update(dep_sets[ds_id]["direct"])
                stack.extend(dep_sets[ds_id]["transitive"])

        # Find the primary source file from arguments
        source_file = None
        params_file = None
        for i, arg in enumerate(arguments):
            if is_source_file(arg) and not arg.startswith("-"):
                # Usually the last source file in arguments is the one being compiled
                source_file = arg
            elif arg.startswith("@") and arg.endswith(".params"):
                params_file = arg[1:]  # strip leading @

        # On MSVC/Windows, arguments use a params file instead of inline args.
        # Read the params file to extract the source file and full arguments.
        if not source_file and params_file:
            params_path = os.path.join(execution_root, params_file)
            if os.path.isfile(params_path):
                try:
                    with open(params_path, "r") as pf:
                        params_args = [line.strip() for line in pf if line.strip()]
                    for pa in params_args:
                        if is_source_file(pa) and not pa.startswith("-") and not pa.startswith("/"):
                            source_file = pa
                    # Replace arguments with the expanded params for clean_arguments
                    arguments = [arguments[0]] + params_args
                except (IOError, OSError):
                    pass

        if not source_file:
            # Try to find source from input artifacts directly
            input_sources = []
            for aid in input_artifact_ids:
                apath = artifacts.get(aid, "")
                if is_source_file(apath) and not is_header_file(apath) and not is_external_path(apath):
                    input_sources.append(apath)
            if len(input_sources) == 1:
                source_file = input_sources[0]

        if not source_file:
            # Try to find from the output artifact name
            output_ids = action.get("outputIds", [])
            for oid in output_ids:
                if oid in artifacts:
                    obj_path = artifacts[oid]
                    # .o file -> derive source
                    for ext in ['.o', '.obj']:
                        if obj_path.endswith(ext):
                            base = obj_path[:-len(ext)]
                            for src_ext in ['.cpp', '.cc', '.c', '.cxx', '.m', '.mm', '.cu']:
                                candidate = base + src_ext
                                if candidate in [artifacts.get(aid, '') for aid in input_artifact_ids]:
                                    source_file = candidate
                                    break
                    if source_file:
                        break

        if not source_file:
            continue

        resolved_source = resolve_path(source_file, execution_root, workspace_root, output_base)

        # Skip external sources if requested
        if EXCLUDE_EXTERNAL_SOURCES and is_external_path(resolved_source):
            continue

        # Skip headers if requested
        if EXCLUDE_HEADERS == "all" and is_header_file(resolved_source):
            continue
        if EXCLUDE_HEADERS == "external" and is_header_file(resolved_source) and is_external_path(resolved_source):
            continue

        # Clean up the command arguments
        cleaned_args = clean_arguments(arguments, execution_root, workspace_root, output_base)

        entry = {
            "directory": execution_root,
            "file": resolved_source,
            "arguments": cleaned_args,
        }
        commands.append(entry)

    return commands


def _detect_msvc_system_includes(compiler_path):
    """Extract MSVC system include paths from the compiler's sibling directory structure."""
    includes = []
    compiler_path = os.path.normpath(compiler_path)

    # Find MSVC include: go up from .../bin/HostX64/x64/cl.exe to .../include
    msvc_bin = os.path.dirname(compiler_path)
    msvc_root = msvc_bin
    for _ in range(3):  # bin/HostX64/x64 -> MSVC root
        msvc_root = os.path.dirname(msvc_root)
    msvc_include = os.path.join(msvc_root, "include")
    if os.path.isdir(msvc_include):
        includes.append(msvc_include)

    # Find Windows SDK includes via known paths
    kits_root = "C:/Program Files (x86)/Windows Kits/10/Include"
    if os.path.isdir(kits_root):
        # Find the latest SDK version
        versions = sorted(
            [d for d in os.listdir(kits_root) if d.startswith("10.")],
            reverse=True,
        )
        if versions:
            sdk_ver = versions[0]
            for subdir in ("ucrt", "shared", "um", "winrt"):
                sdk_path = os.path.join(kits_root, sdk_ver, subdir)
                if os.path.isdir(sdk_path):
                    includes.append(sdk_path)

    return includes


def _is_msvc_compiler(compiler_path):
    """Check if the compiler is MSVC cl.exe."""
    return os.path.basename(compiler_path).lower() in ("cl.exe", "cl")


def clean_arguments(arguments, execution_root, workspace_root, output_base=None):
    """Clean and resolve paths in compiler arguments for clangd consumption."""
    if not arguments:
        return arguments

    cleaned = []
    skip_next = False
    is_msvc = _is_msvc_compiler(arguments[0])

    # For MSVC, replace cl.exe with clang-cl and add system include paths
    if is_msvc:
        cleaned.append("clang-cl")
        msvc_includes = _detect_msvc_system_includes(arguments[0])
        for inc in msvc_includes:
            cleaned.append("-imsvc" + os.path.normpath(inc))
    else:
        cleaned.append(arguments[0])

    for i, arg in enumerate(arguments):
        if i == 0:
            continue  # already handled above
        if skip_next:
            skip_next = False
            continue

        # Skip MSVC flags that clangd/clang-cl doesn't need
        if is_msvc:
            # Skip output file flags (/Fo, /Fe)
            if arg.startswith("/Fo") or arg.startswith("/Fe"):
                continue
            # Skip /showIncludes
            if arg == "/showIncludes":
                continue
            # Skip /c (clangd adds its own)
            if arg == "/c":
                continue

        # Resolve -I, -isystem, -iquote, /I paths
        for prefix in ("-I", "-isystem", "-iquote", "/I"):
            if arg == prefix and i + 1 < len(arguments):
                out_prefix = "-I" if prefix == "/I" else prefix
                cleaned.append(out_prefix)
                cleaned.append(resolve_path(arguments[i + 1], execution_root, workspace_root, output_base))
                skip_next = True
                break
            elif arg.startswith(prefix) and len(arg) > len(prefix):
                path = arg[len(prefix):]
                out_prefix = "-I" if prefix == "/I" else prefix
                cleaned.append(out_prefix + resolve_path(path, execution_root, workspace_root, output_base))
                break
        else:
            if not skip_next:
                # Resolve source file paths
                if is_source_file(arg) and not arg.startswith("-") and not arg.startswith("/"):
                    cleaned.append(resolve_path(arg, execution_root, workspace_root, output_base))
                else:
                    cleaned.append(arg)

    return cleaned


def main():
    workspace_root = get_workspace_root()
    execution_root = get_execution_root(workspace_root)
    output_base = get_output_base(workspace_root)

    all_commands = []
    seen_files = set()

    for target, extra_flags in TARGET_FLAG_PAIRS:
        aquery_output = run_aquery(workspace_root, target, extra_flags)
        if aquery_output:
            commands = extract_compile_commands(aquery_output, execution_root, workspace_root, output_base)
            for cmd in commands:
                file_path = cmd["file"]
                if file_path not in seen_files:
                    seen_files.add(file_path)
                    all_commands.append(cmd)

    # Write compile_commands.json
    output_path = os.path.join(workspace_root, "compile_commands.json")
    with open(output_path, "w") as f:
        json.dump(all_commands, f, indent=2)

    print(f"\033[0;32mWrote {len(all_commands)} entries to compile_commands.json\033[0m")


if __name__ == "__main__":
    main()
