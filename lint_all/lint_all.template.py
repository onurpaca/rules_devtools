"""Smart lint-all: dispatches files to clang-tidy (C++) or buildifier-lint (Bazel).

Tool resolution: hermetic first (if configured), PATH fallback (with warn).

Template variables (baked in by lint_all.bzl):
    {cpp_patterns} — glob patterns for C++ sources
    {bazel_patterns} — glob patterns for Bazel files
    {cpp_system_path} — PATH binary name for clang-tidy (empty disables fallback)
    {cpp_hermetic_path} — runfiles-relative path to hermetic clang-tidy
    {bazel_system_path} — PATH binary name for buildifier (empty disables fallback)
    {bazel_hermetic_path} — runfiles-relative path to hermetic buildifier
    {compile_commands_dir} — path to compile_commands.json directory (empty = workspace root)
    {buildifier_warnings} — comma-separated buildifier warnings
"""

import glob
import os
import shutil
import subprocess
import sys


CPP_PATTERNS = {cpp_patterns}
BAZEL_PATTERNS = {bazel_patterns}
CPP_SYSTEM_PATH = {cpp_system_path}
CPP_HERMETIC_PATH = {cpp_hermetic_path}
BAZEL_SYSTEM_PATH = {bazel_system_path}
BAZEL_HERMETIC_PATH = {bazel_hermetic_path}
COMPILE_COMMANDS_DIR = {compile_commands_dir}
BUILDIFIER_WARNINGS = {buildifier_warnings}


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


def _find_tool(label, system_path, hermetic_path):
    """Resolve tool: hermetic first, system PATH fallback."""
    if hermetic_path:
        p = _find_runfile(hermetic_path)
        if p:
            return p
        if system_path:
            print(f"\033[0;33mwarn:\033[0m hermetic {label} missing in runfiles, falling back to PATH '{system_path}'", file=sys.stderr)
    if system_path:
        p = shutil.which(system_path)
        if p:
            return p
        print(f"\033[0;31merror:\033[0m {label} '{system_path}' not on PATH (and no hermetic fallback available)", file=sys.stderr)
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


def _is_excluded(path, workspace_root):
    rel = os.path.relpath(path, workspace_root)
    return rel.split(os.sep, 1)[0].startswith("bazel-")


def _walk_dir(root, all_patterns, workspace_root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith("bazel-")]
        if _is_excluded(dirpath, workspace_root) and os.path.relpath(dirpath, workspace_root) != ".":
            dirnames[:] = []
            continue
        for f in filenames:
            full = os.path.join(dirpath, f)
            if _path_matches(full, all_patterns):
                yield full


def _scan_globs(workspace_root, patterns):
    out = []
    for pattern in patterns:
        out.extend(glob.glob(os.path.join(workspace_root, pattern), recursive=True))
    return [f for f in out if not _is_excluded(f, workspace_root)]


def parse_args(argv):
    args = argv[1:]
    fix_mode = False
    explicit = []
    extra = []
    if "--" in args:
        sep = args.index("--")
        before, after = args[:sep], args[sep + 1:]
        extra.extend(after)
        args = before
    for a in args:
        if a == "--fix":
            fix_mode = True
        elif a.startswith("-"):
            extra.append(a)
        else:
            explicit.append(a)
    return fix_mode, explicit, extra


def collect_sources(explicit, workspace_root):
    all_patterns = list(CPP_PATTERNS) + list(BAZEL_PATTERNS)
    if explicit:
        candidates = []
        for p in explicit:
            full = p if os.path.isabs(p) else os.path.join(workspace_root, p)
            if os.path.isdir(full):
                candidates.extend(_walk_dir(full, all_patterns, workspace_root))
            else:
                candidates.append(full)
    else:
        candidates = (
            _scan_globs(workspace_root, CPP_PATTERNS)
            + _scan_globs(workspace_root, BAZEL_PATTERNS)
        )
    cpp = sorted({f for f in candidates if _path_matches(f, CPP_PATTERNS)})
    bzl = sorted({f for f in candidates if _path_matches(f, BAZEL_PATTERNS)})
    return cpp, bzl


def run_clang_tidy(tool, files, fix_mode, extra_flags, workspace_root):
    if not files:
        return 0
    cc_dir = COMPILE_COMMANDS_DIR if COMPILE_COMMANDS_DIR else workspace_root
    cc_path = os.path.join(cc_dir, "compile_commands.json")
    if not os.path.exists(cc_path):
        print(f"\033[0;33mWarning:\033[0m compile_commands.json not found at {cc_path}", file=sys.stderr)
        print("Run compile_commands target first for accurate results.", file=sys.stderr)

    cmd = [tool]
    has_p = any(a == "-p" or a.startswith("-p=") for a in extra_flags)
    if not has_p and os.path.exists(cc_path):
        cmd.extend(["-p", cc_dir])
    if fix_mode:
        cmd.append("--fix")
    cmd.extend(extra_flags)
    cmd.extend(files)
    rc = subprocess.run(cmd, cwd=workspace_root).returncode
    label = "fixed" if fix_mode else "linted"
    color = "\033[0;31m" if rc else "\033[0;32m"
    state = "issues found" if rc else "ok"
    print(f"{color}[clang-tidy] {len(files)} file(s) {label}: {state}\033[0m", file=sys.stderr if rc else sys.stdout)
    return rc


def run_buildifier(tool, files, fix_mode, extra_flags, workspace_root):
    if not files:
        return 0
    mode = "fix" if fix_mode else "check"
    lint = "fix" if fix_mode else "warn"
    cmd = [tool, "-mode=" + mode, "-lint=" + lint]
    if BUILDIFIER_WARNINGS:
        cmd.append("-warnings=" + BUILDIFIER_WARNINGS)
    cmd.extend(extra_flags)
    cmd.extend(files)
    rc = subprocess.run(cmd, cwd=workspace_root).returncode
    label = "fixed" if fix_mode else "linted"
    color = "\033[0;31m" if rc else "\033[0;32m"
    state = "issues found" if rc else "ok"
    print(f"{color}[buildifier] {len(files)} file(s) {label}: {state}\033[0m", file=sys.stderr if rc else sys.stdout)
    return rc


def main():
    workspace_root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not workspace_root:
        print("\033[0;31mError:\033[0m Must be run via 'bazel run'.", file=sys.stderr)
        sys.exit(1)

    fix_mode, explicit, extra_flags = parse_args(sys.argv)
    cpp_files, bazel_files = collect_sources(explicit, workspace_root)

    if not cpp_files and not bazel_files:
        scope = explicit if explicit else "<entire project>"
        print(f"\033[0;33mNo matching files under:\033[0m {scope}")
        return

    cpp_tool = _find_tool("clang-tidy", CPP_SYSTEM_PATH, CPP_HERMETIC_PATH) if cpp_files else None
    bazel_tool = _find_tool("buildifier", BAZEL_SYSTEM_PATH, BAZEL_HERMETIC_PATH) if bazel_files else None

    rc = 0
    if cpp_files:
        rc |= run_clang_tidy(cpp_tool, cpp_files, fix_mode, extra_flags, workspace_root)
    if bazel_files:
        rc |= run_buildifier(bazel_tool, bazel_files, fix_mode, extra_flags, workspace_root)

    sys.exit(rc)


if __name__ == "__main__":
    main()
