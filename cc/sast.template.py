"""Run static analyzers on source files.

Template variables (baked in by sast.bzl):
    {srcs_patterns} — list of glob patterns
    {analyzers} — list of analyzer names to run
    {tool_overrides} — dict of analyzer name to binary name overrides
"""

import glob
import json
import os
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


SRCS_PATTERNS = {srcs_patterns}
ANALYZERS = {analyzers}
TOOL_OVERRIDES = {tool_overrides}

DEFAULT_TOOL_NAMES = {
    "cppcheck": "cppcheck",
    "semgrep": "semgrep",
    "scan-build": "scan-build",
}


def find_tool(analyzer):
    """Find the analyzer binary."""
    name = TOOL_OVERRIDES.get(analyzer, DEFAULT_TOOL_NAMES.get(analyzer, analyzer))
    path = shutil.which(name)
    if not path:
        print(f"\033[0;33mWarning:\033[0m {name} not found on PATH, skipping.", file=sys.stderr)
        return None
    return path


def find_sources(workspace_root):
    files = []
    for pattern in SRCS_PATTERNS:
        full_pattern = os.path.join(workspace_root, pattern)
        files.extend(glob.glob(full_pattern, recursive=True))
    return sorted({f for f in files if not os.path.relpath(f, workspace_root).split(os.sep, 1)[0].startswith("bazel-")})


def run_cppcheck(tool, sources, workspace_root, extra_args):
    """Run cppcheck and report results."""
    print(f"\033[0;34m--- Running cppcheck ---\033[0m")
    cmd = [tool, "--enable=all", "--suppress=missingIncludeSystem", "--quiet"] + extra_args + sources
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=workspace_root)

    output = result.stderr or result.stdout
    if output.strip():
        print(output)
        return 1
    else:
        print(f"\033[0;32mcppcheck: no issues found in {len(sources)} file(s).\033[0m")
        return 0


def run_semgrep(tool, sources, workspace_root, extra_args):
    """Run semgrep and report results."""
    print(f"\033[0;34m--- Running semgrep ---\033[0m")
    cmd = [tool, "--config", "auto", "--json"] + extra_args + sources
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=workspace_root)

    if result.returncode != 0 and not result.stdout:
        print(f"\033[0;31msemgrep failed:\033[0m {result.stderr}", file=sys.stderr)
        return result.returncode

    try:
        data = json.loads(result.stdout)
        results = data.get("results", [])
        if results:
            for r in results:
                severity = r.get("extra", {}).get("severity", "INFO")
                path = r.get("path", "?")
                line = r.get("start", {}).get("line", "?")
                message = r.get("extra", {}).get("message", "")
                check_id = r.get("check_id", "")
                color = "\033[0;31m" if severity == "ERROR" else "\033[0;33m" if severity == "WARNING" else "\033[0;34m"
                print(f"{color}[{severity}]\033[0m {path}:{line}: {message} ({check_id})")
            return 1
        else:
            print(f"\033[0;32msemgrep: no issues found.\033[0m")
            return 0
    except json.JSONDecodeError:
        print(result.stdout)
        return 1


def run_scan_build(tool, sources, workspace_root, extra_args):
    """Run scan-build."""
    print(f"\033[0;34m--- Running scan-build ---\033[0m")
    print("\033[0;33mNote:\033[0m scan-build requires a compilation step. Use with caution.", file=sys.stderr)
    # scan-build wraps a compiler invocation, so we just report availability
    print(f"scan-build is available at: {tool}")
    print("Usage: scan-build bazel build //your:target")
    return 0


RUNNERS = {
    "cppcheck": run_cppcheck,
    "semgrep": run_semgrep,
    "scan-build": run_scan_build,
}


def parse_args(argv):
    """Parse arguments into explicit files and tool flags.

    Convention:
      - Non-dash args = explicit file paths (override glob patterns)
      - Everything after '--' goes directly to all analyzers
      - All other dash-args = passed through to all analyzers
    """
    args = argv[1:]
    explicit_files = []
    tool_flags = []

    # Split on '--' separator
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

    exit_code = 0
    for analyzer in ANALYZERS:
        tool = find_tool(analyzer)
        if not tool:
            continue
        runner = RUNNERS.get(analyzer)
        if runner:
            rc = runner(tool, sources, workspace_root, tool_flags)
            if rc != 0:
                exit_code = 1
        else:
            print(f"\033[0;33mUnknown analyzer: {analyzer}\033[0m", file=sys.stderr)

    if exit_code != 0:
        sys.exit(exit_code)


if __name__ == "__main__":
    main()
