"""cc_devtools() bundle — generate the C/C++ devtools targets.

Creates these targets:
  - {name}_clang_format
  - {name}_clang_tidy
  - {name}_sast
  - {name}_iwyu
  - {name}_ctags
  - {name}_compile_commands
  - {name}_unused_deps

Use this when you only want the C/C++ portion. For the full set
(C/C++ plus Bazel meta-tools and orchestrators) use //:devtools.bzl.

Usage:
    load("@rules_devtools//cc:cc_devtools.bzl", "cc_devtools")
    cc_devtools(name = "cc", targets = "//...")
"""

load("//cc:clang_format.bzl", "clang_format")
load("//cc:clang_tidy.bzl", "clang_tidy")
load("//cc:compile_commands.bzl", "compile_commands")
load("//cc:ctags.bzl", "ctags")
load("//cc:iwyu.bzl", "iwyu")
load("//cc:sast.bzl", "sast")
load("//cc:unused_deps.bzl", "unused_deps")

def cc_devtools(
        name,
        targets = None,
        format_srcs = None,
        lint_srcs = None,
        sast_srcs = None,
        ctags_srcs = None,
        clang_format_hermetic = None,
        clang_format_system = "clang-format",
        clang_tidy_hermetic = None,
        clang_tidy_system = "clang-tidy",
        iwyu_hermetic = None,
        iwyu_system = "include-what-you-use",
        ctags_hermetic = None,
        ctags_system = "ctags",
        analyzers = None,
        exclude_headers = None,
        exclude_external_sources = False,
        enable_cscope = False,
        **kwargs):
    """Create the C/C++ devtools target set.

    Args:
        name: Base name; each target gets a suffix (e.g. {name}_clang_format).
        targets: Bazel targets for compile_commands and unused_deps. Default "//...".
        format_srcs: Glob patterns for clang_format/clang_tidy/sast/ctags sources.
        lint_srcs: Glob patterns for clang_tidy. Defaults to format_srcs.
        sast_srcs: Glob patterns for sast. Defaults to format_srcs.
        ctags_srcs: Glob patterns for ctags. Defaults to format_srcs.
        clang_format_hermetic: Label to hermetic clang-format binary.
        clang_format_system: PATH binary name for clang-format fallback.
        clang_tidy_hermetic: Label to hermetic clang-tidy binary.
        clang_tidy_system: PATH binary name for clang-tidy fallback.
        iwyu_hermetic: Label to hermetic IWYU binary.
        iwyu_system: PATH binary name for IWYU fallback.
        ctags_hermetic: Label to hermetic ctags binary.
        ctags_system: PATH binary name for ctags fallback.
        analyzers: List of analyzers for sast (default ["cppcheck"]).
        exclude_headers: Header exclusion mode for compile_commands.
        exclude_external_sources: Exclude external sources from compile_commands.
        enable_cscope: Generate cscope database alongside ctags.
        **kwargs: Additional common attributes passed to all targets.
    """
    compile_commands(
        name = name + "_compile_commands",
        targets = targets,
        exclude_headers = exclude_headers,
        exclude_external_sources = exclude_external_sources,
        **kwargs
    )

    clang_format(
        name = name + "_clang_format",
        srcs = format_srcs,
        hermetic = clang_format_hermetic,
        system = clang_format_system,
        **kwargs
    )

    clang_tidy(
        name = name + "_clang_tidy",
        srcs = lint_srcs or format_srcs,
        hermetic = clang_tidy_hermetic,
        system = clang_tidy_system,
        **kwargs
    )

    sast(
        name = name + "_sast",
        srcs = sast_srcs or format_srcs,
        analyzers = analyzers,
        **kwargs
    )

    iwyu(
        name = name + "_iwyu",
        hermetic = iwyu_hermetic,
        system = iwyu_system,
        **kwargs
    )

    ctags(
        name = name + "_ctags",
        srcs = ctags_srcs or format_srcs,
        hermetic = ctags_hermetic,
        system = ctags_system,
        cscope = enable_cscope,
        **kwargs
    )

    unused_deps(
        name = name + "_unused_deps",
        targets = targets if type(targets) == "string" else "//...",
        **kwargs
    )
