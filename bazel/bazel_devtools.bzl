"""bazel_devtools() bundle — generate the Bazel meta-tool targets.

Creates these targets:
  - {name}_buildifier
  - {name}_buildozer
  - {name}_depgraph
  - {name}_bep_report

Use this when you only want the Bazel meta-tool portion. For the full set
(C/C++ plus Bazel meta-tools and orchestrators) use //:devtools.bzl.

Usage:
    load("@rules_devtools//bazel:bazel_devtools.bzl", "bazel_devtools")
    bazel_devtools(name = "bz")
"""

load("//bazel:bep_report.bzl", "bep_report")
load("//bazel:buildifier.bzl", "buildifier")
load("//bazel:buildozer.bzl", "buildozer")
load("//bazel:depgraph.bzl", "depgraph")

def bazel_devtools(
        name,
        buildifier_srcs = None,
        buildifier_hermetic = None,
        buildifier_system = "buildifier",
        buildifier_mode = "fix",
        buildifier_lint = "warn",
        buildifier_warnings = "",
        buildozer_hermetic = None,
        buildozer_system = "buildozer",
        **kwargs):
    """Create the Bazel meta-tool target set.

    Args:
        name: Base name; each target gets a suffix (e.g. {name}_buildifier).
        buildifier_srcs: Glob patterns for buildifier sources.
        buildifier_hermetic: Label to hermetic buildifier binary.
        buildifier_system: PATH binary name for buildifier fallback.
        buildifier_mode: Buildifier mode (fix/check/diff). Default: "fix".
        buildifier_lint: Buildifier lint mode (off/warn/fix). Default: "warn".
        buildifier_warnings: Comma-separated buildifier warnings (passed as -warnings=).
        buildozer_hermetic: Label to hermetic buildozer binary.
        buildozer_system: PATH binary name for buildozer fallback.
        **kwargs: Additional common attributes passed to all targets.
    """
    buildifier(
        name = name + "_buildifier",
        srcs = buildifier_srcs,
        hermetic = buildifier_hermetic,
        system = buildifier_system,
        mode = buildifier_mode,
        lint = buildifier_lint,
        warnings = buildifier_warnings,
        **kwargs
    )

    buildozer(
        name = name + "_buildozer",
        hermetic = buildozer_hermetic,
        system = buildozer_system,
        **kwargs
    )

    depgraph(
        name = name + "_depgraph",
        **kwargs
    )

    bep_report(
        name = name + "_bep_report",
        **kwargs
    )
