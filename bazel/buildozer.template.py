"""Run buildozer commands on BUILD files.

Tool resolution: hermetic first (if configured), PATH fallback (with warn).

Template variables (baked in by buildozer.bzl):
    {system_path} — PATH binary name (empty disables fallback)
    {hermetic_path} — runfiles-relative path to hermetic binary (empty disables hermetic)
"""

import os
import shutil
import subprocess
import sys


SYSTEM_PATH = {system_path}
HERMETIC_PATH = {hermetic_path}


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


def find_tool(label="buildozer"):
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


def main():
    workspace_root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not workspace_root:
        print("\033[0;31mError:\033[0m Must be run via 'bazel run'.", file=sys.stderr)
        sys.exit(1)

    tool = find_tool()
    cmd = [tool] + sys.argv[1:]
    result = subprocess.run(cmd, cwd=workspace_root)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
