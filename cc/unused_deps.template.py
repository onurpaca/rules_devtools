"""Find unused BUILD dependencies via bazel query + include analysis.

Template variables:
    {targets} — Bazel target pattern to analyze
"""

import os
import re
import subprocess
import sys


TARGETS = {targets}


def get_cc_rules(workspace_root):
    """Get all cc_library/cc_binary targets matching the pattern."""
    cmd = ["bazel", "query", f'kind("cc_(library|binary|test)", {TARGETS})', "--output=label"]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=workspace_root)
    if result.returncode != 0:
        print(f"\033[0;31mError:\033[0m bazel query failed.", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return [line.strip() for line in result.stdout.strip().split("\n") if line.strip()]


def get_deps(target, workspace_root):
    """Get direct deps of a target."""
    cmd = ["bazel", "query", f'labels(deps, {target})', "--output=label"]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=workspace_root)
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.strip().split("\n") if line.strip() and line.strip() != target]


def get_srcs(target, workspace_root):
    """Get source files of a target."""
    cmd = ["bazel", "query", f'labels(srcs, {target})', "--output=label"]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=workspace_root)
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.strip().split("\n") if line.strip()]


def get_hdrs(target, workspace_root):
    """Get header files provided by a dep."""
    cmd = ["bazel", "query", f'labels(hdrs, {target})', "--output=label"]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=workspace_root)
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.strip().split("\n") if line.strip()]


def label_to_path(label, workspace_root):
    """Convert a Bazel label to a file path."""
    # //pkg:file -> pkg/file
    label = label.lstrip("@")
    if label.startswith("//"):
        label = label[2:]
    pkg, _, name = label.partition(":")
    if not name:
        name = pkg.split("/")[-1]
    path = os.path.join(workspace_root, pkg, name)
    return path


def extract_includes(filepath):
    """Extract #include statements from a source file."""
    includes = set()
    if not os.path.exists(filepath):
        return includes
    try:
        with open(filepath, "r", errors="replace") as f:
            for line in f:
                match = re.match(r'\s*#\s*include\s*[<"]([^>"]+)[>"]', line)
                if match:
                    includes.add(match.group(1))
    except (IOError, OSError):
        pass
    return includes


def header_basename(label):
    """Get the basename of a header label for matching."""
    parts = label.split(":")
    name = parts[-1] if ":" in label else label.split("/")[-1]
    return name


def main():
    workspace_root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if not workspace_root:
        print("\033[0;31mError:\033[0m Must be run via 'bazel run'.", file=sys.stderr)
        sys.exit(1)

    print(f"\033[0;34mAnalyzing targets matching {TARGETS}...\033[0m")
    targets = get_cc_rules(workspace_root)

    if not targets:
        print("\033[0;33mNo cc_* targets found.\033[0m")
        return

    total_unused = 0

    for target in targets:
        deps = get_deps(target, workspace_root)
        if not deps:
            continue

        # Get all includes from source files
        srcs = get_srcs(target, workspace_root)
        all_includes = set()
        for src_label in srcs:
            src_path = label_to_path(src_label, workspace_root)
            all_includes.update(extract_includes(src_path))

        # Check each dep: do source files include any of its headers?
        unused = []
        for dep in deps:
            hdrs = get_hdrs(dep, workspace_root)
            if not hdrs:
                continue  # Skip deps without headers (might be a cc_binary or config)

            dep_used = False
            for hdr_label in hdrs:
                hdr_name = header_basename(hdr_label)
                # Check if any include matches this header
                for inc in all_includes:
                    if inc.endswith(hdr_name) or hdr_name in inc:
                        dep_used = True
                        break
                if dep_used:
                    break

            if not dep_used:
                unused.append(dep)

        if unused:
            total_unused += len(unused)
            print(f"\n\033[0;33m{target}\033[0m has {len(unused)} potentially unused dep(s):")
            for dep in unused:
                print(f"  \033[0;31m- {dep}\033[0m")
                print(f"    buildozer 'remove deps {dep}' {target}")

    if total_unused == 0:
        print(f"\033[0;32mNo unused dependencies found in {len(targets)} target(s).\033[0m")
    else:
        print(f"\n\033[0;33mFound {total_unused} potentially unused dep(s) across {len(targets)} target(s).\033[0m")
        print("Review carefully — heuristic analysis may have false positives.")


if __name__ == "__main__":
    main()
