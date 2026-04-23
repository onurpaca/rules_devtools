"""black() macro — format Python source files using black.

Usage:
    load("@rules_devtools//py:black.bzl", "black")
    black(name = "black", srcs = ["src/**/*.py"])

    bazel run //:black              # format files in-place
    bazel run //:black -- --check   # CI: check only, exit 1 if unformatted

Tool resolution: hermetic first (if configured), PATH fallback (with warn).
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_FORWARDED = ("tags", "visibility", "compatible_with", "target_compatible_with")

def black(name, srcs = None, hermetic = None, system = "black", config = ".pyproject.toml", **kwargs):
    """Create a black target.

    Args:
        name: Target name.
        srcs: Glob patterns for sources. Defaults to common Python extensions.
        hermetic: Label to hermetic black binary (tried first).
        system: PATH binary name used as fallback (default "black"). Pass None to disable fallback.
        config: Path to pyproject.toml config. Default: ".pyproject.toml".
        **kwargs: Additional common attributes.
    """
    if not srcs:
        srcs = ["**/*.py"]

    script_name = name + ".py"
    _black_expand_template(
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

def _black_expand_template_impl(ctx):
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

_black_expand_template = rule(
    implementation = _black_expand_template_impl,
    attrs = {
        "srcs_patterns": attr.string_list(mandatory = True),
        "system_path": attr.string(),
        "hermetic_tool": attr.label(allow_single_file = True),
        "config": attr.string(default = ".pyproject.toml"),
        "_template": attr.label(allow_single_file = True, default = "//py:black.template.py"),
    },
)
