"""buildozer() macro — run buildozer commands on BUILD files.

Usage:
    load("@rules_devtools//bazel:buildozer.bzl", "buildozer")
    buildozer(name = "buildozer")

    bazel run //:buildozer -- 'add deps //foo:bar' //my:target

Tool resolution: hermetic first (if configured), PATH fallback (with warn).
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_FORWARDED = ("tags", "visibility", "compatible_with", "target_compatible_with")

def buildozer(name, hermetic = None, system = "buildozer", **kwargs):
    """Create a buildozer target.

    Buildozer is a passthrough tool — all arguments are forwarded at runtime
    via sys.argv[1:]. No srcs or patterns needed.

    Args:
        name: Target name.
        hermetic: Label to hermetic buildozer binary (tried first).
        system: PATH binary name used as fallback (default "buildozer"). Pass None to disable fallback.
        **kwargs: Additional common attributes.
    """
    script_name = name + ".py"
    _buildozer_expand_template(
        name = script_name,
        system_path = system or "",
        hermetic_tool = hermetic,
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

def _buildozer_expand_template_impl(ctx):
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
            "{system_path}": repr(ctx.attr.system_path),
            "{hermetic_path}": repr(hermetic_path),
        },
    )
    return DefaultInfo(files = depset([script]))

_buildozer_expand_template = rule(
    implementation = _buildozer_expand_template_impl,
    attrs = {
        "system_path": attr.string(),
        "hermetic_tool": attr.label(allow_single_file = True),
        "_template": attr.label(allow_single_file = True, default = "//bazel:buildozer.template.py"),
    },
)
