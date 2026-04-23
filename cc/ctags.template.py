"""Generate ctags/cscope index for code navigation.

Tool resolution: hermetic first (if configured), PATH fallback (with warn).

Template variables (baked in by ctags.bzl):
    {srcs_patterns} — list of glob patterns
    {system_path} — PATH binary name (empty disables fallback)
    {hermetic_path} — runfiles-relative path to hermetic binary (empty disables hermetic)
    {enable_cscope} — whether to also generate cscope database
"""

import glob
import os
import shutil
import subprocess
import sys
import tempfile


SRCS_PATTERNS = {srcs_patterns}
SYSTEM_PATH = {system_path}
HERMETIC_PATH = {hermetic_path}
ENABLE_CSCOPE = {enable_cscope}


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


def find_tool(label="ctags"):
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
    explicit_files = []
    tool_flags = []
    if "--" in args:
        sep = args.index("--")
        before, after = args[:sep], args[sep + 1:]
        tool_flags.extend(after)
        args = before
    for a in args:
        if a.startswith("-"):
            tool_flags.append(a)
        else:
            explicit_files.append(a)
    return explicit_files, tool_flags


def main():
    workspace_root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not workspace_root:
        print("\033[0;31mError:\033[0m Must be run via 'bazel run'.", file=sys.stderr)
        sys.exit(1)

    explicit_files, tool_flags = parse_args(sys.argv)

    if explicit_files:
        sources = [os.path.join(workspace_root, f) if not os.path.isabs(f) else f for f in explicit_files]
    else:
        sources = find_sources(workspace_root)

    if not sources:
        print("\033[0;33mNo source files found.\033[0m")
        return

    ctags_tool = find_tool()

    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        for src in sources:
            f.write(src + '\n')
        file_list_path = f.name

    try:
        tags_path = os.path.join(workspace_root, "tags")
        cmd = [ctags_tool, "--languages=C,C++,C#", "-L", file_list_path, "-f", tags_path]

        version_result = subprocess.run([ctags_tool, "--version"], capture_output=True, text=True)
        if "Universal Ctags" in version_result.stdout:
            cmd.extend(["--fields=+lnS", "--extras=+q"])

        cmd.extend(tool_flags)

        print(f"\033[0;34mGenerating ctags for {len(sources)} file(s)...\033[0m")
        result = subprocess.run(cmd, cwd=workspace_root)

        if result.returncode != 0:
            print(f"\033[0;31mctags failed with exit code {result.returncode}.\033[0m", file=sys.stderr)
            sys.exit(result.returncode)

        print(f"\033[0;32mWrote tags file: {tags_path}\033[0m")

        if ENABLE_CSCOPE:
            cscope_tool = shutil.which("cscope")
            if cscope_tool:
                cscope_files = os.path.join(workspace_root, "cscope.files")
                with open(cscope_files, 'w') as f:
                    for src in sources:
                        f.write(src + '\n')

                cscope_cmd = [cscope_tool, "-b", "-q", "-i", cscope_files]
                print(f"\033[0;34mGenerating cscope database...\033[0m")
                cscope_result = subprocess.run(cscope_cmd, cwd=workspace_root)

                if cscope_result.returncode == 0:
                    print(f"\033[0;32mWrote cscope database in {workspace_root}\033[0m")
                else:
                    print(f"\033[0;31mcscope failed.\033[0m", file=sys.stderr)
            else:
                print("\033[0;33mWarning:\033[0m cscope not found on PATH, skipping cscope database.", file=sys.stderr)
    finally:
        os.unlink(file_list_path)


if __name__ == "__main__":
    main()
