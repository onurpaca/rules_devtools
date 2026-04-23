"""Smart format-all: dispatches files to clang-format (C++), buildifier (Bazel), or ruff (Python).

Tool resolution: hermetic first (if configured), PATH fallback (with warn).

Template variables (baked in by format_all.bzl):
    {cpp_patterns} — glob patterns for C++ sources
    {bazel_patterns} — glob patterns for Bazel files
    {py_patterns} — glob patterns for Python sources
    {cpp_system_path} — PATH binary name for clang-format (empty disables fallback)
    {cpp_hermetic_path} — runfiles-relative path to hermetic clang-format
    {bazel_system_path} — PATH binary name for buildifier (empty disables fallback)
    {bazel_hermetic_path} — runfiles-relative path to hermetic buildifier
    {py_system_path} — PATH binary name for ruff (empty disables fallback)
    {config} — path to .clang-format
    {buildifier_lint} — buildifier lint mode (off/warn/fix)
    {buildifier_warnings} — comma-separated buildifier warnings
"""

import glob
import os
import shutil
import subprocess
import sys

CPP_PATTERNS = {cpp_patterns}
BAZEL_PATTERNS = {bazel_patterns}
PY_PATTERNS = {py_patterns}
CPP_SYSTEM_PATH = {cpp_system_path}
CPP_HERMETIC_PATH = {cpp_hermetic_path}
BAZEL_SYSTEM_PATH = {bazel_system_path}
BAZEL_HERMETIC_PATH = {bazel_hermetic_path}
PY_SYSTEM_PATH = {py_system_path}
CONFIG = {config}
BUILDIFIER_LINT = {buildifier_lint}
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
            print(
                f"\033[0;33mwarn:\033[0m hermetic {label} missing in runfiles, falling back to PATH '{system_path}'",
                file=sys.stderr,
            )
    if system_path:
        p = shutil.which(system_path)
        if p:
            return p
        print(
            f"\033[0;31merror:\033[0m {label} '{system_path}' not on PATH (and no hermetic fallback available)",
            file=sys.stderr,
        )
        sys.exit(1)
    print(
        f"\033[0;31merror:\033[0m no {label} configured (neither hermetic nor system).",
        file=sys.stderr,
    )
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
        if (
            _is_excluded(dirpath, workspace_root)
            and os.path.relpath(dirpath, workspace_root) != "."
        ):
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
    check_mode = False
    explicit = []
    extra = []
    if "--" in args:
        sep = args.index("--")
        before, after = args[:sep], args[sep + 1 :]
        extra.extend(after)
        args = before
    for a in args:
        if a == "--check":
            check_mode = True
        elif a.startswith("-"):
            extra.append(a)
        else:
            explicit.append(a)
    return check_mode, explicit, extra


def collect_sources(explicit, workspace_root):
    all_patterns = list(CPP_PATTERNS) + list(BAZEL_PATTERNS) + list(PY_PATTERNS)
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
            + _scan_globs(workspace_root, PY_PATTERNS)
        )
    cpp = sorted({f for f in candidates if _path_matches(f, CPP_PATTERNS)})
    bzl = sorted({f for f in candidates if _path_matches(f, BAZEL_PATTERNS)})
    py = sorted({f for f in candidates if _path_matches(f, PY_PATTERNS)})
    return cpp, bzl, py


def run_clang_format(tool, files, check_mode, extra_flags, workspace_root):
    if not files:
        return 0
    if check_mode:
        cmd = [tool, "--dry-run", "--Werror"] + extra_flags + files
    else:
        style = []
        if not any(f.startswith("--style") for f in extra_flags):
            cfg = os.path.join(workspace_root, CONFIG)
            if os.path.exists(cfg):
                style = [f"--style=file:{cfg}"]
        cmd = [tool, "-i"] + style + extra_flags + files
    rc = subprocess.run(cmd, cwd=workspace_root).returncode
    label = "checked" if check_mode else "formatted"
    color = "\033[0;31m" if rc else "\033[0;32m"
    state = "issues found" if rc and check_mode else ("failed" if rc else "ok")
    print(
        f"{color}[clang-format] {len(files)} file(s) {label}: {state}\033[0m",
        file=sys.stderr if rc else sys.stdout,
    )
    return rc


def run_buildifier(tool, files, check_mode, extra_flags, workspace_root):
    if not files:
        return 0
    mode = "check" if check_mode else "fix"
    cmd = [tool, "-mode=" + mode]
    if BUILDIFIER_LINT != "off":
        cmd.append("-lint=" + BUILDIFIER_LINT)
    if BUILDIFIER_WARNINGS:
        cmd.append("-warnings=" + BUILDIFIER_WARNINGS)
    cmd.extend(extra_flags)
    cmd.extend(files)
    rc = subprocess.run(cmd, cwd=workspace_root).returncode
    label = "checked" if check_mode else "processed"
    color = "\033[0;31m" if rc else "\033[0;32m"
    state = "issues found" if rc and check_mode else ("failed" if rc else "ok")
    print(
        f"{color}[buildifier] {len(files)} file(s) {label}: {state}\033[0m",
        file=sys.stderr if rc else sys.stdout,
    )
    return rc


def run_ruff(tool, files, check_mode, extra_flags, workspace_root):
    if not files:
        return 0
    if check_mode:
        cmd = [tool, "check"] + extra_flags + files
    else:
        cmd = [tool, "format"] + extra_flags + files
    rc = subprocess.run(cmd, cwd=workspace_root).returncode
    label = "checked" if check_mode else "formatted"
    color = "\033[0;31m" if rc else "\033[0;32m"
    state = "issues found" if rc and check_mode else ("failed" if rc else "ok")
    print(
        f"{color}[ruff] {len(files)} file(s) {label}: {state}\033[0m",
        file=sys.stderr if rc else sys.stdout,
    )
    return rc


def main():
    workspace_root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not workspace_root:
        print("\033[0;31mError:\033[0m Must be run via 'bazel run'.", file=sys.stderr)
        sys.exit(1)

    check_mode, explicit, extra_flags = parse_args(sys.argv)
    cpp_files, bazel_files, py_files = collect_sources(explicit, workspace_root)

    if not cpp_files and not bazel_files and not py_files:
        scope = explicit if explicit else "<entire project>"
        print(f"\033[0;33mNo matching files under:\033[0m {scope}")
        return

    cpp_tool = (
        _find_tool("clang-format", CPP_SYSTEM_PATH, CPP_HERMETIC_PATH)
        if cpp_files
        else None
    )
    bazel_tool = (
        _find_tool("buildifier", BAZEL_SYSTEM_PATH, BAZEL_HERMETIC_PATH)
        if bazel_files
        else None
    )
    py_tool = (
        _find_tool("ruff", PY_SYSTEM_PATH, "")
        if py_files
        else None
    )

    rc = 0
    if cpp_files:
        rc |= run_clang_format(
            cpp_tool, cpp_files, check_mode, extra_flags, workspace_root
        )
    if bazel_files:
        rc |= run_buildifier(
            bazel_tool, bazel_files, check_mode, extra_flags, workspace_root
        )
    if py_files:
        rc |= run_ruff(py_tool, py_files, check_mode, extra_flags, workspace_root)

    sys.exit(rc)


if __name__ == "__main__":
    main()
