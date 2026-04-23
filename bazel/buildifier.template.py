"""Format Bazel files using buildifier.

Tool resolution: hermetic first (if configured), PATH fallback (with warn).

Template variables (baked in by buildifier.bzl):
    {srcs_patterns} — list of glob patterns for Bazel files
    {system_path} — PATH binary name (empty disables fallback)
    {hermetic_path} — runfiles-relative path to hermetic binary (empty disables hermetic)
    {mode} — buildifier mode (fix, check, diff, print_if_changed)
    {lint} — lint mode (off, warn, fix)
    {warnings} — comma-separated warning list
"""

import glob
import os
import shutil
import subprocess
import sys


SRCS_PATTERNS = {srcs_patterns}
SYSTEM_PATH = {system_path}
HERMETIC_PATH = {hermetic_path}
MODE = {mode}
LINT = {lint}
WARNINGS = {warnings}


def _find_runfile(rlocationpath):
    if not rlocationpath:
        return None
    runfiles_dir = os.environ.get("RUNFILES_DIR")
    if runfiles_dir:
        p = os.path.join(runfiles_dir, rlocationpath)
        if os.path.exists(p):
            return p
    runfiles_dir = os.path.abspath(sys.argv[0]) + ".runfiles"
    if os.path.isdir(runfiles_dir):
        p = os.path.join(runfiles_dir, rlocationpath)
        if os.path.exists(p):
            return p
    manifest = os.environ.get("RUNFILES_MANIFEST_FILE")
    if manifest and os.path.exists(manifest):
        with open(manifest) as f:
            for line in f:
                parts = line.strip().split(" ", 1)
                if len(parts) == 2 and parts[0] == rlocationpath:
                    return parts[1]
    return None


def find_tool(label="buildifier"):
    """Resolve tool: hermetic first, system PATH fallback."""
    if HERMETIC_PATH:
        p = _find_runfile(HERMETIC_PATH)
        if p:
            return p
        if SYSTEM_PATH:
            print(f"\033[0;33mwarn:\033[0m hermetic {label} missing in runfiles, falling back to PATH '{SYSTEM_PATH}'", file=sys.stderr)
    if SYSTEM_PATH:
        p = shutil.which(SYSTEM_PATH)
        if p:
            return p
        print(f"\033[0;31merror:\033[0m {label} '{SYSTEM_PATH}' not on PATH (and no hermetic fallback available)", file=sys.stderr)
        sys.exit(1)
    print(f"\033[0;31merror:\033[0m no {label} configured (neither hermetic nor system).", file=sys.stderr)
    sys.exit(1)


def _path_matches(path, patterns):
    base = os.path.basename(path)
    for p in patterns:
        last = os.path.basename(p)
        if last.startswith("*"):
            if base.lower().endswith(last[1:].lower()):
                return True
        elif base == last:
            return True
    return False


def _walk_dir(root, patterns, workspace_root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith("bazel-")]
        rel_dir = os.path.relpath(dirpath, workspace_root)
        if rel_dir != "." and rel_dir.split(os.sep, 1)[0].startswith("bazel-"):
            dirnames[:] = []
            continue
        for f in filenames:
            full = os.path.join(dirpath, f)
            if _path_matches(full, patterns):
                yield full


def find_sources(workspace_root):
    files = []
    for pattern in SRCS_PATTERNS:
        full_pattern = os.path.join(workspace_root, pattern)
        files.extend(glob.glob(full_pattern, recursive=True))
    return sorted({f for f in files if not os.path.relpath(f, workspace_root).split(os.sep, 1)[0].startswith("bazel-")})


def expand_paths(paths, workspace_root):
    resolved = []
    for p in paths:
        full = p if os.path.isabs(p) else os.path.join(workspace_root, p)
        if os.path.isdir(full):
            resolved.extend(_walk_dir(full, SRCS_PATTERNS, workspace_root))
        else:
            resolved.append(full)
    return sorted(set(resolved))


def main():
    workspace_root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not workspace_root:
        print("\033[0;31mError:\033[0m Must be run via 'bazel run'.", file=sys.stderr)
        sys.exit(1)

    tool = find_tool()
    sources = find_sources(workspace_root)

    if not sources:
        print("\033[0;33mNo Bazel files found matching patterns:\033[0m", SRCS_PATTERNS)
        return

    mode = MODE
    args = sys.argv[1:]
    explicit_files = []
    tool_flags = []

    if "--" in args:
        sep = args.index("--")
        before, after = args[:sep], args[sep + 1:]
        tool_flags.extend(after)
        args = before

    for a in args:
        if a == "--check":
            mode = "check"
        elif a.startswith("-"):
            tool_flags.append(a)
        else:
            explicit_files.append(a)

    if explicit_files:
        sources = expand_paths(explicit_files, workspace_root)
        if not sources:
            print("\033[0;33mNo Bazel files found under:\033[0m", explicit_files)
            return

    cmd = [tool, "-mode=" + mode]
    if LINT != "off":
        cmd.append("-lint=" + LINT)
    if WARNINGS:
        cmd.append("-warnings=" + WARNINGS)
    cmd.extend(tool_flags)
    cmd.extend(sources)

    result = subprocess.run(cmd, cwd=workspace_root)
    if result.returncode != 0:
        if mode == "check":
            print(f"\033[0;31mBuildifier check failed: formatting issues found.\033[0m", file=sys.stderr)
        sys.exit(result.returncode)
    if mode == "check":
        print(f"\033[0;32m{len(sources)} file(s) checked, all formatted correctly.\033[0m")
    else:
        print(f"\033[0;32m{len(sources)} file(s) processed by buildifier.\033[0m")


if __name__ == "__main__":
    main()
