"""Lint source files using clang-tidy.

Tool resolution: hermetic first (if configured), PATH fallback (with warn).

Template variables (baked in by clang_tidy.bzl):
    {srcs_patterns} — list of glob patterns
    {system_path} — PATH binary name (empty disables fallback)
    {hermetic_path} — runfiles-relative path to hermetic binary (empty disables hermetic)
    {compile_commands_dir} — path to compile_commands.json directory
"""

import glob
import os
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


def find_tool(label="clang-tidy"):
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


def find_sources(workspace_root):
    files = []
    for pattern in SRCS_PATTERNS:
        full_pattern = os.path.join(workspace_root, pattern)
        files.extend(glob.glob(full_pattern, recursive=True))
    return sorted({f for f in files if not os.path.relpath(f, workspace_root).split(os.sep, 1)[0].startswith("bazel-")})


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
    sources = find_sources(workspace_root)

    if not sources:
        print("\033[0;33mNo source files found matching patterns:\033[0m", SRCS_PATTERNS)
        return

    cc_dir = COMPILE_COMMANDS_DIR if COMPILE_COMMANDS_DIR else workspace_root
    cc_path = os.path.join(cc_dir, "compile_commands.json")
    if not os.path.exists(cc_path):
        print("\033[0;33mWarning:\033[0m compile_commands.json not found at", cc_path, file=sys.stderr)
        print("Run compile_commands target first for accurate results.", file=sys.stderr)
        print("Continuing without compilation database...", file=sys.stderr)

    fix_mode, explicit_files, tool_flags = parse_args(sys.argv)
    if explicit_files:
        sources = [os.path.join(workspace_root, f) if not os.path.isabs(f) else f for f in explicit_files]

    cmd = [tool]
    has_p = any(a == "-p" or a.startswith("-p=") for a in tool_flags)
    if not has_p and os.path.exists(cc_path):
        cmd.extend(["-p", cc_dir or workspace_root])
    if fix_mode:
        cmd.append("--fix")
    cmd.extend(tool_flags)
    cmd.extend(sources)

    print(f"\033[0;34mRunning clang-tidy on {len(sources)} file(s)...\033[0m")
    result = subprocess.run(cmd, cwd=workspace_root)

    if result.returncode != 0:
        print(f"\033[0;31mLinting completed with issues (exit code {result.returncode}).\033[0m", file=sys.stderr)
        sys.exit(result.returncode)
    print(f"\033[0;32mLinting completed successfully on {len(sources)} file(s).\033[0m")


if __name__ == "__main__":
    main()
