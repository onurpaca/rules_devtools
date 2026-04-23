"""Parse BEP (Build Event Protocol) JSON for build analysis.

Usage: bazel run //:buildinfo -- /path/to/bep.json
"""

import collections
import json
import os
import sys


def parse_bep_file(filepath):
    """Parse a BEP JSON file (newline-delimited JSON events)."""
    events = []
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    return events


def analyze_events(events):
    """Analyze BEP events and extract build information."""
    info = {
        "started": None,
        "finished": None,
        "targets": [],
        "actions": [],
        "test_results": [],
        "cache_stats": {"hits": 0, "misses": 0},
        "errors": [],
    }

    for event in events:
        event_id = event.get("id", {})

        # Build started
        if "started" in event:
            info["started"] = event["started"]

        # Build finished
        if "finished" in event:
            info["finished"] = event["finished"]

        # Target completed
        if "completed" in event:
            target_id = event_id.get("targetCompleted", {}).get("label", "unknown")
            success = event["completed"].get("success", False)
            info["targets"].append({
                "label": target_id,
                "success": success,
            })

        # Action completed
        if "action" in event:
            action = event["action"]
            info["actions"].append({
                "mnemonic": action.get("type", action.get("mnemonic", "unknown")),
                "label": action.get("label", ""),
                "success": action.get("success", True),
                "stderr": action.get("stderr", ""),
            })

        # Test result
        if "testResult" in event:
            target_id = event_id.get("testResult", {}).get("label", "unknown")
            test = event["testResult"]
            info["test_results"].append({
                "label": target_id,
                "status": test.get("status", "UNKNOWN"),
                "duration_ms": test.get("testAttemptDurationMilliseconds", 0),
            })

        # Aborted (errors)
        if "aborted" in event:
            reason = event["aborted"].get("reason", "UNKNOWN")
            description = event["aborted"].get("description", "")
            info["errors"].append(f"{reason}: {description}")

    return info


def format_duration(ms):
    """Format milliseconds into human-readable duration."""
    if ms < 1000:
        return f"{ms}ms"
    seconds = ms / 1000
    if seconds < 60:
        return f"{seconds:.1f}s"
    minutes = int(seconds // 60)
    secs = seconds % 60
    return f"{minutes}m {secs:.1f}s"


def print_report(info):
    """Print a colorful build analysis report."""
    print("\033[0;34m" + "=" * 60 + "\033[0m")
    print("\033[0;34m  Build Analysis Report\033[0m")
    print("\033[0;34m" + "=" * 60 + "\033[0m")

    # Build duration
    if info["started"] and info["finished"]:
        start_ms = int(info["started"].get("startTimeMillis", 0) or 0)
        finish_time = int(info["finished"].get("finishTimeMillis", 0) or 0)
        if start_ms and finish_time:
            duration = finish_time - start_ms
            print(f"\n  Build duration: {format_duration(duration)}")

    # Exit code
    if info["finished"]:
        exit_code = info["finished"].get("exitCode", {}).get("code", -1)
        exit_name = info["finished"].get("exitCode", {}).get("name", "UNKNOWN")
        color = "\033[0;32m" if exit_code == 0 else "\033[0;31m"
        print(f"  Exit: {color}{exit_name} ({exit_code})\033[0m")

    # Targets
    if info["targets"]:
        succeeded = sum(1 for t in info["targets"] if t["success"])
        failed = len(info["targets"]) - succeeded
        print(f"\n  Targets: {succeeded} succeeded", end="")
        if failed:
            print(f", \033[0;31m{failed} failed\033[0m", end="")
        print()

        # Show failed targets
        for t in info["targets"]:
            if not t["success"]:
                print(f"    \033[0;31m✗ {t['label']}\033[0m")

    # Actions summary
    if info["actions"]:
        mnemonic_counts = collections.Counter(a["mnemonic"] for a in info["actions"])
        print(f"\n  Actions: {len(info['actions'])} total")
        for mnemonic, count in mnemonic_counts.most_common(10):
            print(f"    {mnemonic}: {count}")

    # Test results
    if info["test_results"]:
        print(f"\n  Tests: {len(info['test_results'])} total")
        for t in info["test_results"]:
            status = t["status"]
            color = "\033[0;32m" if status == "PASSED" else "\033[0;31m"
            duration = format_duration(t.get("duration_ms", 0))
            print(f"    {color}{status}\033[0m {t['label']} ({duration})")

    # Errors
    if info["errors"]:
        print(f"\n  \033[0;31mErrors ({len(info['errors'])}):\033[0m")
        for err in info["errors"]:
            print(f"    \033[0;31m• {err}\033[0m")

    print("\n\033[0;34m" + "=" * 60 + "\033[0m")


def main():
    # BEP file path from command line args
    args = sys.argv[1:]
    if not args:
        print("\033[0;31mUsage:\033[0m bazel run //:buildinfo -- /path/to/bep.json", file=sys.stderr)
        print("\nGenerate BEP file with: bazel build //... --build_event_json_file=/tmp/bep.json", file=sys.stderr)
        sys.exit(1)

    bep_path = args[0]
    if not os.path.exists(bep_path):
        print(f"\033[0;31mError:\033[0m BEP file not found: {bep_path}", file=sys.stderr)
        sys.exit(1)

    print(f"\033[0;34mParsing BEP file: {bep_path}\033[0m")
    events = parse_bep_file(bep_path)

    if not events:
        print("\033[0;31mError:\033[0m No events found in BEP file.", file=sys.stderr)
        sys.exit(1)

    info = analyze_events(events)
    print_report(info)


if __name__ == "__main__":
    main()
