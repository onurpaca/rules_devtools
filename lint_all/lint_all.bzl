"""lint_all() macro — single command that runs clang-tidy, buildifier-lint, and ruff.

Dispatches files to the right tool by extension/name:
  - .cpp/.cc/.cxx/.c → clang-tidy
  - BUILD/BUILD.bazel/MODULE.bazel/WORKSPACE/WORKSPACE.bazel/*.bzl → buildifier (lint)
  - .py → ruff check

Usage:
    load("@rules_devtools//lint_all:lint_all.bzl", "lint_all")
    lint_all(name = "lint_all")

    bazel run //:lint_all                  # warn for all
    bazel run //:lint_all -- --fix         # auto-fix all
    bazel run //:lint_all -- src/lib       # recurse into a subdir
    bazel run //:lint_all -- src/foo.cpp   # single file (auto-routed)

Tool resolution: hermetic first (if configured), PATH fallback (with warn).
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_DEFAULT_CPP_PATTERNS = [
    "**/*.cpp",
    "**/*.cc",
    "**/*.cxx",
    "**/*.c",
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

def lint_all(
        name,
        cpp_srcs = None,
        bazel_srcs = None,
        py_srcs = None,
        clang_tidy_hermetic = None,
        clang_tidy_system = "clang-tidy",
        buildifier_hermetic = None,
        buildifier_system = "buildifier",
        compile_commands_dir = "",
        buildifier_warnings = "",
        ruff_system = "ruff",
        **kwargs):
    """Create a lint_all target.

    Args:
        name: Target name.
        cpp_srcs: Glob patterns for C++ sources. Defaults to common C/C++ extensions.
        bazel_srcs: Glob patterns for Bazel files. Defaults to standard Bazel files.
        py_srcs: Glob patterns for Python sources. Defaults to ["**/*.py"].
        clang_tidy_hermetic: Label to hermetic clang-tidy binary (tried first).
        clang_tidy_system: PATH binary name for clang-tidy fallback (default "clang-tidy").
            Pass None to disable fallback.
        buildifier_hermetic: Label to hermetic buildifier binary (tried first).
        buildifier_system: PATH binary name for buildifier fallback (default "buildifier").
            Pass None to disable fallback.
        compile_commands_dir: Directory containing compile_commands.json. Defaults to workspace root.
        buildifier_warnings: Comma-separated buildifier warnings (passed as -warnings=).
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

    _lint_all_expand_template(
        name = script_name,
        cpp_patterns = cpp_srcs,
        bazel_patterns = bazel_srcs,
        py_patterns = py_srcs,
        cpp_system_path = clang_tidy_system or "",
        bazel_system_path = buildifier_system or "",
        py_system_path = ruff_system or "",
        clang_tidy_hermetic = clang_tidy_hermetic,
        buildifier_hermetic = buildifier_hermetic,
        compile_commands_dir = compile_commands_dir,
        buildifier_warnings = buildifier_warnings,
        **forwarded
    )

    data = []
    if clang_tidy_hermetic:
        data.append(clang_tidy_hermetic)
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

def _lint_all_expand_template_impl(ctx):
    cpp_hermetic_path = _hermetic_rlocation(ctx.file.clang_tidy_hermetic, ctx.workspace_name)
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
            "{compile_commands_dir}": repr(ctx.attr.compile_commands_dir),
            "{buildifier_warnings}": repr(ctx.attr.buildifier_warnings),
        },
    )
    return DefaultInfo(files = depset([script]))

_lint_all_expand_template = rule(
    implementation = _lint_all_expand_template_impl,
    attrs = {
        "cpp_patterns": attr.string_list(mandatory = True),
        "bazel_patterns": attr.string_list(mandatory = True),
        "py_patterns": attr.string_list(mandatory = True),
        "cpp_system_path": attr.string(),
        "bazel_system_path": attr.string(),
        "py_system_path": attr.string(),
        "clang_tidy_hermetic": attr.label(allow_single_file = True),
        "buildifier_hermetic": attr.label(allow_single_file = True),
        "compile_commands_dir": attr.string(default = ""),
        "buildifier_warnings": attr.string(default = ""),
        "_template": attr.label(
            allow_single_file = True,
            default = "//lint_all:lint_all.template.py",
        ),
    },
)
