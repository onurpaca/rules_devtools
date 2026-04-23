"""bep_report() macro — parse BEP JSON for build analysis.

Usage:
    load("@rules_devtools//bazel:bep_report.bzl", "bep_report")
    bep_report(name = "bep_report")

    bazel build //... --build_event_json_file=/tmp/bep.json
    bazel run //:bep_report -- /tmp/bep.json
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_FORWARDED = ("tags", "visibility", "compatible_with", "target_compatible_with")

def bep_report(name, **kwargs):
    """Create a BEP report target.

    Args:
        name: Target name.
        **kwargs: Additional common attributes.
    """
    script_name = name + ".py"
    _bep_report_expand_template(
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

def _bep_report_expand_template_impl(ctx):
    script = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.expand_template(
        output = script,
        is_executable = True,
        template = ctx.file._template,
        substitutions = {},
    )
    return DefaultInfo(files = depset([script]))

_bep_report_expand_template = rule(
    implementation = _bep_report_expand_template_impl,
    attrs = {
        "_template": attr.label(allow_single_file = True, default = "//bazel:bep_report.template.py"),
    },
)
