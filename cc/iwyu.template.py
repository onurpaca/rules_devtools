"""Run include-what-you-use on source files.

Tool resolution: hermetic first (if configured), PATH fallback (with warn).

Template variables (baked in by iwyu.bzl):
    {srcs_patterns} — list of glob patterns (or empty to use compile_commands.json)
    {system_path} — PATH binary name (empty disables fallback)
    {hermetic_path} — runfiles-relative path to hermetic binary (empty disables hermetic)
    {compile_commands_dir} — path to compile_commands.json directory
"""

import glob
import json
import os
import re
import shutil
import subprocess
import sys


SRCS_PATTERNS = {srcs_patterns}
SYSTEM_PATH = {system_path}
HERMETIC_PATH = {hermetic_path}
COMPILE_COMMANDS_DIR = {compile_commands_dir}


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


def find_tool(label="include-what-you-use"):
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


def find_fixer():
    for name in ["iwyu-fix-includes", "fix_includes.py", "iwyu_tool"]:
        path = shutil.which(name)
        if path:
            return path
    return None


def load_compile_commands(workspace_root):
    cc_dir = COMPILE_COMMANDS_DIR if COMPILE_COMMANDS_DIR else workspace_root
    cc_path = os.path.join(cc_dir, "compile_commands.json")
    if not os.path.exists(cc_path):
        return None
    with open(cc_path) as f:
        return json.load(f)


def find_sources(workspace_root):
    if SRCS_PATTERNS:
        files = []
        for pattern in SRCS_PATTERNS:
            full_pattern = os.path.join(workspace_root, pattern)
            files.extend(glob.glob(full_pattern, recursive=True))
        return sorted({f for f in files if not os.path.relpath(f, workspace_root).split(os.sep, 1)[0].startswith("bazel-")})
    cc = load_compile_commands(workspace_root)
    if cc:
        return [entry["file"] for entry in cc if os.path.exists(entry["file"])]
    print("\033[0;31mError:\033[0m No source patterns specified and no compile_commands.json found.", file=sys.stderr)
    sys.exit(1)


def get_compile_flags(source_file, compile_commands):
    if not compile_commands:
        return []
    for entry in compile_commands:
        if os.path.abspath(entry["file"]) == os.path.abspath(source_file):
            args = entry.get("arguments", [])
            if args:
                return [a for a in args[1:] if a != source_file and not a.endswith(('.cpp', '.cc', '.c', '.cxx'))]
            command = entry.get("command", "")
            if command:
                import shlex
                parts = shlex.split(command)
                return [a for a in parts[1:] if a != source_file and not a.endswith(('.cpp', '.cc', '.c', '.cxx'))]
    return []


def parse_args(argv):
    args = argv[1:]
    fix_mode = False
    explicit_files = []
    tool_flags = []
    if "--" in args:
        sep = args.index("--")
        before, after = args[:sep], args[sep + 1:]
        tool_flags.extend(after)
        args = before
    for a in args:
        if a == "--fix":
            fix_mode = True
        elif a.startswith("-"):
            tool_flags.append(a)
        else:
            explicit_files.append(a)
    return fix_mode, explicit_files, tool_flags


def main():
    workspace_root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not workspace_root:
        print("\033[0;31mError:\033[0m Must be run via 'bazel run'.", file=sys.stderr)
        sys.exit(1)

    tool = find_tool()
    compile_commands = load_compile_commands(workspace_root)
    fix_mode, explicit_files, tool_flags = parse_args(sys.argv)

    if explicit_files:
        sources = [os.path.join(workspace_root, f) if not os.path.isabs(f) else f for f in explicit_files]
    else:
        sources = find_sources(workspace_root)

    if not sources:
        print("\033[0;33mNo source files found.\033[0m")
        return

    print(f"\033[0;34mRunning IWYU on {len(sources)} file(s)...\033[0m")

    all_output = []
    issues_found = 0

    for source in sources:
        flags = get_compile_flags(source, compile_commands)
        cmd = [tool] + flags + tool_flags + [source]
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=workspace_root)
        output = result.stderr
        if output.strip():
            all_output.append(output)
            add_count = len(re.findall(r"^#include", output, re.MULTILINE))
            remove_count = len(re.findall(r"^- #include", output, re.MULTILINE))
            if add_count or remove_count:
                issues_found += 1

    if all_output:
        print("\n".join(all_output))

    if fix_mode and all_output:
        fixer = find_fixer()
        if fixer:
            print(f"\033[0;34mApplying fixes with {fixer}...\033[0m")
            full_output = "\n".join(all_output)
            fix_result = subprocess.run([fixer], input=full_output, text=True, cwd=workspace_root)
            if fix_result.returncode == 0:
                print("\033[0;32mFixes applied successfully.\033[0m")
            else:
                print("\033[0;31mFix application failed.\033[0m", file=sys.stderr)
                sys.exit(1)
        else:
            print("\033[0;33mWarning:\033[0m iwyu-fix-includes not found, cannot auto-fix.", file=sys.stderr)
    elif issues_found:
        print(f"\033[0;33m{issues_found} file(s) with include suggestions.\033[0m")
        if not fix_mode:
            print("Run with --fix to auto-apply changes.")
    else:
        print(f"\033[0;32mNo include issues found in {len(sources)} file(s).\033[0m")


if __name__ == "__main__":
    main()
