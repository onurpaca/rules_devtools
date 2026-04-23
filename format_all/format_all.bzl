"""format_all() macro — single command that runs clang-format, buildifier, and ruff.

Dispatches files to the right tool by extension/name:
  - .cpp/.cc/.cxx/.h/.hpp/.hxx/.hh/.c → clang-format
  - BUILD/BUILD.bazel/MODULE.bazel/WORKSPACE/WORKSPACE.bazel/*.bzl → buildifier
  - .py → ruff format

Usage:
    load("@rules_devtools//format_all:format_all.bzl", "format_all")
    format_all(name = "format_all")

    bazel run //:format_all                      # fix all
    bazel run //:format_all -- --check           # CI: check all
    bazel run //:format_all -- src/lib           # recurse into a subdir
    bazel run //:format_all -- src/foo.cpp      # single file (auto-routed)

Tool resolution: hermetic first (if configured), PATH fallback (with warn).
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_DEFAULT_CPP_PATTERNS = [
    "**/*.cpp",
    "**/*.cc",
    "**/*.cxx",
    "**/*.c",
    "**/*.h",
    "**/*.hpp",
    "**/*.hxx",
    "**/*.hh",
]

_DEFAULT_BAZEL_PATTERNS = [
    "**/BUILD",
    "**/BUILD.bazel",
    "**/*.bzl",
    "**/WORKSPACE",
    "**/WORKSPACE.bazel",
    "**/MODULE.bazel",
]

_DEFAULT_PY_PATTERNS = [
    "**/*.py",
]

_FORWARDED = ("tags", "visibility", "compatible_with", "target_compatible_with")

def format_all(
        name,
        cpp_srcs = None,
        bazel_srcs = None,
        py_srcs = None,
        clang_format_hermetic = None,
        clang_format_system = "clang-format",
        buildifier_hermetic = None,
        buildifier_system = "buildifier",
        config = ".clang-format",
        buildifier_lint = "off",
        buildifier_warnings = "",
        ruff_system = "ruff",
        **kwargs):
    """Create a format_all target.

    Args:
        name: Target name.
        cpp_srcs: Glob patterns for C++ sources. Defaults to common C/C++ extensions.
        bazel_srcs: Glob patterns for Bazel files. Defaults to standard Bazel files.
        py_srcs: Glob patterns for Python sources. Defaults to ["**/*.py"].
        clang_format_hermetic: Label to hermetic clang-format binary (tried first).
        clang_format_system: PATH binary name for clang-format fallback (default "clang-format").
            Pass None to disable fallback.
        buildifier_hermetic: Label to hermetic buildifier binary (tried first).
        buildifier_system: PATH binary name for buildifier fallback (default "buildifier").
            Pass None to disable fallback.
        config: Path to .clang-format config. Default: ".clang-format".
        buildifier_lint: Buildifier lint mode (off/warn/fix). Default: "off"
            so format_all stays a pure formatter; use the dedicated buildifier
            target for linting.
        buildifier_warnings: Comma-separated buildifier warnings.
        ruff_system: PATH binary name for ruff fallback (default "ruff").
        **kwargs: Additional common attributes.
    """
    if cpp_srcs == None:
        cpp_srcs = _DEFAULT_CPP_PATTERNS
    if bazel_srcs == None:
        bazel_srcs = _DEFAULT_BAZEL_PATTERNS
    if py_srcs == None:
        py_srcs = _DEFAULT_PY_PATTERNS

    script_name = name + ".py"
    forwarded = {k: v for k, v in kwargs.items() if k in _FORWARDED}

    _format_all_expand_template(
        name = script_name,
        cpp_patterns = cpp_srcs,
        bazel_patterns = bazel_srcs,
        py_patterns = py_srcs,
        cpp_system_path = clang_format_system or "",
        bazel_system_path = buildifier_system or "",
        py_system_path = ruff_system or "",
        clang_format_hermetic = clang_format_hermetic,
        buildifier_hermetic = buildifier_hermetic,
        config = config,
        buildifier_lint = buildifier_lint,
        buildifier_warnings = buildifier_warnings,
        **forwarded
    )

    data = []
    if clang_format_hermetic:
        data.append(clang_format_hermetic)
    if buildifier_hermetic:
        data.append(buildifier_hermetic)

    py_binary(
        name = name,
        main = script_name,
        srcs = [script_name],
        data = data,
        **kwargs
    )

def _hermetic_rlocation(file, workspace_name):
    if not file:
        return ""
    p = file.short_path
    if p.startswith("../"):
        return p[3:]
    return workspace_name + "/" + p

def _format_all_expand_template_impl(ctx):
    cpp_hermetic_path = _hermetic_rlocation(ctx.file.clang_format_hermetic, ctx.workspace_name)
    bazel_hermetic_path = _hermetic_rlocation(ctx.file.buildifier_hermetic, ctx.workspace_name)

    script = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.expand_template(
        output = script,
        is_executable = True,
        template = ctx.file._template,
        substitutions = {
            "{cpp_patterns}": repr(ctx.attr.cpp_patterns),
            "{bazel_patterns}": repr(ctx.attr.bazel_patterns),
            "{py_patterns}": repr(ctx.attr.py_patterns),
            "{cpp_system_path}": repr(ctx.attr.cpp_system_path),
            "{cpp_hermetic_path}": repr(cpp_hermetic_path),
            "{bazel_system_path}": repr(ctx.attr.bazel_system_path),
            "{bazel_hermetic_path}": repr(bazel_hermetic_path),
            "{py_system_path}": repr(ctx.attr.py_system_path),
            "{config}": repr(ctx.attr.config),
            "{buildifier_lint}": repr(ctx.attr.buildifier_lint),
            "{buildifier_warnings}": repr(ctx.attr.buildifier_warnings),
        },
    )
    return DefaultInfo(files = depset([script]))

_format_all_expand_template = rule(
    implementation = _format_all_expand_template_impl,
    attrs = {
        "cpp_patterns": attr.string_list(mandatory = True),
        "bazel_patterns": attr.string_list(mandatory = True),
        "py_patterns": attr.string_list(mandatory = True),
        "cpp_system_path": attr.string(),
        "bazel_system_path": attr.string(),
        "py_system_path": attr.string(),
        "clang_format_hermetic": attr.label(allow_single_file = True),
        "buildifier_hermetic": attr.label(allow_single_file = True),
        "config": attr.string(default = ".clang-format"),
        "buildifier_lint": attr.string(default = "off"),
        "buildifier_warnings": attr.string(default = ""),
        "_template": attr.label(
            allow_single_file = True,
            default = "//format_all:format_all.template.py",
        ),
    },
)
