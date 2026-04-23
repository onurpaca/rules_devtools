"""unused_deps() macro — find unused BUILD dependencies.

Usage:
    load("@rules_devtools//cc:unused_deps.bzl", "unused_deps")
    unused_deps(name = "unused_deps", targets = "//...")
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_FORWARDED = ("tags", "visibility", "compatible_with", "target_compatible_with")

def unused_deps(name, targets = None, **kwargs):
    """Create an unused deps detection target.

    Args:
        name: Target name.
        targets: Bazel targets to analyze. Defaults to "//...".
        **kwargs: Additional common attributes.
    """
    if not targets:
        targets = "//..."
    if type(targets) == "list":
        targets = " + ".join(targets)

    script_name = name + ".py"
    _unused_deps_expand_template(
        name = script_name,
        targets = targets,
        **{k: v for k, v in kwargs.items() if k in _FORWARDED}
    )

    py_binary(
        name = name,
        main = script_name,
        srcs = [script_name],
        imports = [""],
        **kwargs
    )

def _unused_deps_expand_template_impl(ctx):
    script = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.expand_template(
        output = script,
        is_executable = True,
        template = ctx.file._template,
        substitutions = {
            "{targets}": repr(ctx.attr.targets),
        },
    )
    return DefaultInfo(files = depset([script]))

_unused_deps_expand_template = rule(
    implementation = _unused_deps_expand_template_impl,
    attrs = {
        "targets": attr.string(default = "//..."),
        "_template": attr.label(allow_single_file = True, default = "//cc:unused_deps.template.py"),
    },
)
