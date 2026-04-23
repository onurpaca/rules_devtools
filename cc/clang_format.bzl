"""clang_format() macro — run clang-format on source files.

Usage:
    load("@rules_devtools//cc:clang_format.bzl", "clang_format")
    clang_format(name = "clang_format", srcs = ["src/**/*.cpp"])

    bazel run //:clang_format              # format files in-place
    bazel run //:clang_format -- --check   # CI: check only, exit 1 if unformatted

Tool resolution: hermetic first (if configured), PATH fallback (with warn).
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_FORWARDED = ("tags", "visibility", "compatible_with", "target_compatible_with")

def clang_format(name, srcs = None, hermetic = None, system = "clang-format", config = ".clang-format", **kwargs):
    """Create a clang_format target.

    Args:
        name: Target name.
        srcs: Glob patterns for sources. Defaults to common C/C++ extensions.
        hermetic: Label to hermetic clang-format binary (tried first).
        system: PATH binary name used as fallback (default "clang-format"). Pass None to disable fallback.
        config: Path to .clang-format config. Default: ".clang-format".
        **kwargs: Additional common attributes.
    """
    if not srcs:
        srcs = ["**/*.cpp", "**/*.cc", "**/*.cxx", "**/*.h", "**/*.hpp", "**/*.hxx"]

    script_name = name + ".py"
    _clang_format_expand_template(
        name = script_name,
        srcs_patterns = srcs,
        system_path = system or "",
        hermetic_tool = hermetic,
        config = config,
        **{k: v for k, v in kwargs.items() if k in _FORWARDED}
    )

    data = [hermetic] if hermetic else []

    py_binary(
        name = name,
        main = script_name,
        srcs = [script_name],
        data = data,
        **kwargs
    )

def _clang_format_expand_template_impl(ctx):
    hermetic_path = ""
    if ctx.attr.hermetic_tool:
        p = ctx.file.hermetic_tool.short_path
        hermetic_path = p[3:] if p.startswith("../") else ctx.workspace_name + "/" + p

    script = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.expand_template(
        output = script,
        is_executable = True,
        template = ctx.file._template,
        substitutions = {
            "{srcs_patterns}": repr(ctx.attr.srcs_patterns),
            "{system_path}": repr(ctx.attr.system_path),
            "{hermetic_path}": repr(hermetic_path),
            "{config}": repr(ctx.attr.config),
        },
    )
    return DefaultInfo(files = depset([script]))

_clang_format_expand_template = rule(
    implementation = _clang_format_expand_template_impl,
    attrs = {
        "srcs_patterns": attr.string_list(mandatory = True),
        "system_path": attr.string(),
        "hermetic_tool": attr.label(allow_single_file = True),
        "config": attr.string(default = ".clang-format"),
        "_template": attr.label(allow_single_file = True, default = "//cc:clang_format.template.py"),
    },
)
