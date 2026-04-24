"""devtools() bundle macro: single call to create all devtools targets.

Creates the full set of C/C++ and Bazel meta-tool targets, plus the cross-cutting
format_all and lint_all orchestrators.

Usage:
    load("@rules_devtools//:devtools.bzl", "devtools")

    devtools(
        name = "dev",
        targets = "//...",
        format_srcs = ["src/**/*.cpp", "include/**/*.h"],
    )

    # Generated targets:
    # bazel run //:dev_format_all                      # C++ + Bazel in one pass
    # bazel run //:dev_format_all -- --check
    # bazel run //:dev_lint_all                        # C++ + Bazel in one pass
    # bazel run //:dev_lint_all -- --fix
    # bazel run //:dev_clang_format
    # bazel run //:dev_clang_format -- --check
    # bazel run //:dev_clang_tidy
    # bazel run //:dev_clang_tidy -- --fix
    # bazel run //:dev_sast
    # bazel run //:dev_iwyu
    # bazel run //:dev_ctags
    # bazel run //:dev_buildifier
    # bazel run //:dev_buildifier -- --check
    # bazel run //:dev_buildozer -- 'add deps //foo:bar' //my:target
    # bazel run //:dev_compile_commands
    # bazel run //:dev_unused_deps
    # bazel run //:dev_depgraph -- //src:main
    # bazel run //:dev_bep_report -- /tmp/bep.json

Tool resolution: every per-tool target prefers a hermetic binary (if you pass one)
and falls back to PATH (warn-on-fallback) otherwise.
"""

load("//bazel:bazel_devtools.bzl", "bazel_devtools")
load("//cc:cc_devtools.bzl", "cc_devtools")
load("//format_all:format_all.bzl", "format_all")
load("//lint_all:lint_all.bzl", "lint_all")

def devtools(
        name,
        targets = None,
        format_srcs = None,
        lint_srcs = None,
        sast_srcs = None,
        ctags_srcs = None,
        buildifier_srcs = None,
        clang_format_hermetic = None,
        clang_format_system = "clang-format",
        clang_tidy_hermetic = None,
        clang_tidy_system = "clang-tidy",
        iwyu_hermetic = None,
        iwyu_system = "include-what-you-use",
        ctags_hermetic = None,
        ctags_system = "ctags",
        buildifier_hermetic = None,
        buildifier_system = "buildifier",
        buildozer_hermetic = None,
        buildozer_system = "buildozer",
        analyzers = None,
        exclude_headers = None,
        exclude_external_sources = False,
        enable_cscope = False,
        buildifier_mode = "fix",
        buildifier_lint = "warn",
        buildifier_warnings = "",
        **kwargs):
    """Create the full devtools target set with a single macro call.

    Args:
        name: Base name; each target gets a suffix (e.g. {name}_clang_format).
        targets: Bazel targets to analyze for compile_commands and unused_deps.
        format_srcs: Glob patterns for clang_format/clang_tidy/sast/ctags sources.
        lint_srcs: Glob patterns for clang_tidy. Defaults to format_srcs.
        sast_srcs: Glob patterns for sast. Defaults to format_srcs.
        ctags_srcs: Glob patterns for ctags. Defaults to format_srcs.
        buildifier_srcs: Glob patterns for buildifier sources.
        clang_format_hermetic: Label to hermetic clang-format binary.
        clang_format_system: PATH binary name for clang-format fallback (default "clang-format").
        clang_tidy_hermetic: Label to hermetic clang-tidy binary.
        clang_tidy_system: PATH binary name for clang-tidy fallback (default "clang-tidy").
        iwyu_hermetic: Label to hermetic IWYU binary.
        iwyu_system: PATH binary name for IWYU fallback (default "include-what-you-use").
        ctags_hermetic: Label to hermetic ctags binary.
        ctags_system: PATH binary name for ctags fallback (default "ctags").
        buildifier_hermetic: Label to hermetic buildifier binary.
        buildifier_system: PATH binary name for buildifier fallback (default "buildifier").
        buildozer_hermetic: Label to hermetic buildozer binary.
        buildozer_system: PATH binary name for buildozer fallback (default "buildozer").
        analyzers: List of analyzers for sast (default ["cppcheck"]).
        exclude_headers: Header exclusion mode for compile_commands.
        exclude_external_sources: Exclude external sources from compile_commands.
        enable_cscope: Generate cscope database alongside ctags.
        buildifier_mode: Buildifier mode (fix/check/diff). Default: "fix".
        buildifier_lint: Buildifier lint mode (off/warn/fix). Default: "warn".
        buildifier_warnings: Comma-separated buildifier warnings.
        **kwargs: Additional common attributes passed to all targets.
    """
    cc_devtools(
        name = name,
        targets = targets,
        format_srcs = format_srcs,
        lint_srcs = lint_srcs,
        sast_srcs = sast_srcs,
        ctags_srcs = ctags_srcs,
        clang_format_hermetic = clang_format_hermetic,
        clang_format_system = clang_format_system,
        clang_tidy_hermetic = clang_tidy_hermetic,
        clang_tidy_system = clang_tidy_system,
        iwyu_hermetic = iwyu_hermetic,
        iwyu_system = iwyu_system,
        ctags_hermetic = ctags_hermetic,
        ctags_system = ctags_system,
        analyzers = analyzers,
        exclude_headers = exclude_headers,
        exclude_external_sources = exclude_external_sources,
        enable_cscope = enable_cscope,
        **kwargs
    )

    bazel_devtools(
        name = name,
        buildifier_srcs = buildifier_srcs,
        buildifier_hermetic = buildifier_hermetic,
        buildifier_system = buildifier_system,
        buildifier_mode = buildifier_mode,
        buildifier_lint = buildifier_lint,
        buildifier_warnings = buildifier_warnings,
        buildozer_hermetic = buildozer_hermetic,
        buildozer_system = buildozer_system,
        **kwargs
    )

    fa_kwargs = dict(kwargs)
    if format_srcs:
        fa_kwargs["cpp_srcs"] = format_srcs
    if buildifier_srcs:
        fa_kwargs["bazel_srcs"] = buildifier_srcs
    fa_kwargs["clang_format_hermetic"] = clang_format_hermetic
    fa_kwargs["clang_format_system"] = clang_format_system
    fa_kwargs["buildifier_hermetic"] = buildifier_hermetic
    fa_kwargs["buildifier_system"] = buildifier_system
    format_all(name = name + "_format_all", **fa_kwargs)

    la_kwargs = dict(kwargs)
    la_cpp_srcs = lint_srcs or format_srcs
    if la_cpp_srcs:
        la_kwargs["cpp_srcs"] = la_cpp_srcs
    if buildifier_srcs:
        la_kwargs["bazel_srcs"] = buildifier_srcs
    la_kwargs["clang_tidy_hermetic"] = clang_tidy_hermetic
    la_kwargs["clang_tidy_system"] = clang_tidy_system
    la_kwargs["buildifier_hermetic"] = buildifier_hermetic
    la_kwargs["buildifier_system"] = buildifier_system
    lint_all(name = name + "_lint_all", **la_kwargs)
