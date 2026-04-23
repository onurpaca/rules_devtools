"""iwyu() macro — run include-what-you-use.

Usage:
    load("@rules_devtools//cc:iwyu.bzl", "iwyu")
    iwyu(name = "iwyu")

    bazel run //:iwyu           # report include suggestions
    bazel run //:iwyu -- --fix  # auto-fix includes

Tool resolution: hermetic first (if configured), PATH fallback (with warn).
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_FORWARDED = ("tags", "visibility", "compatible_with", "target_compatible_with")

def iwyu(name, srcs = None, hermetic = None, system = "include-what-you-use", compile_commands_dir = "", **kwargs):
    """Create an IWYU target.

    Args:
        name: Target name.
        srcs: Glob patterns for sources. Empty (default) uses compile_commands.json entries.
        hermetic: Label to hermetic IWYU binary (tried first).
        system: PATH binary name used as fallback (default "include-what-you-use"). Pass None to disable fallback.
        compile_commands_dir: Directory containing compile_commands.json.
        **kwargs: Additional common attributes.
    """
    if not srcs:
        srcs = []

    script_name = name + ".py"
    _iwyu_expand_template(
        name = script_name,
        srcs_patterns = srcs,
        system_path = system or "",
        hermetic_tool = hermetic,
        compile_commands_dir = compile_commands_dir,
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

def _iwyu_expand_template_impl(ctx):
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
            "{compile_commands_dir}": repr(ctx.attr.compile_commands_dir),
        },
    )
    return DefaultInfo(files = depset([script]))

_iwyu_expand_template = rule(
    implementation = _iwyu_expand_template_impl,
    attrs = {
        "srcs_patterns": attr.string_list(default = []),
        "system_path": attr.string(),
        "hermetic_tool": attr.label(allow_single_file = True),
        "compile_commands_dir": attr.string(default = ""),
        "_template": attr.label(allow_single_file = True, default = "//cc:iwyu.template.py"),
    },
)
