"""depgraph() macro — visualize Bazel dependency graphs.

Usage:
    load("@rules_devtools//bazel:depgraph.bzl", "depgraph")
    depgraph(name = "depgraph")

    bazel run //:depgraph -- //src:main
    bazel run //:depgraph -- //src:main --depth=3 --output=html
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_FORWARDED = ("tags", "visibility", "compatible_with", "target_compatible_with")

def depgraph(name, **kwargs):
    """Create a dependency visualization target.

    Args:
        name: Target name.
        **kwargs: Additional common attributes.
    """
    script_name = name + ".py"
    _depgraph_expand_template(
        name = script_name,
        **{k: v for k, v in kwargs.items() if k in _FORWARDED}
    )

    py_binary(
        name = name,
        main = script_name,
        srcs = [script_name],
        imports = [""],
        **kwargs
    )

def _depgraph_expand_template_impl(ctx):
    script = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.expand_template(
        output = script,
        is_executable = True,
        template = ctx.file._template,
        substitutions = {},
    )
    return DefaultInfo(files = depset([script]))

_depgraph_expand_template = rule(
    implementation = _depgraph_expand_template_impl,
    attrs = {
        "_template": attr.label(allow_single_file = True, default = "//bazel:depgraph.template.py"),
    },
)
