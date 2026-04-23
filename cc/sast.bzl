"""sast() macro — run static analyzers (cppcheck, semgrep, scan-build).

Usage:
    load("@rules_devtools//cc:sast.bzl", "sast")
    sast(name = "sast", srcs = ["src/**/*.cpp"], analyzers = ["cppcheck"])
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_FORWARDED = ("tags", "visibility", "compatible_with", "target_compatible_with")

def sast(name, srcs = None, analyzers = None, system_tools = None, **kwargs):
    """Create a static analysis target.

    Args:
        name: Target name.
        srcs: Glob patterns for source files.
        analyzers: List of analyzers to run. Options: "cppcheck", "semgrep", "scan-build".
            Defaults to ["cppcheck"].
        system_tools: Dict of analyzer name to system binary name overrides.
        **kwargs: Additional common attributes.
    """
    if not srcs:
        srcs = ["**/*.cpp", "**/*.cc", "**/*.cxx", "**/*.h", "**/*.hpp"]
    if not analyzers:
        analyzers = ["cppcheck"]
    if not system_tools:
        system_tools = {}

    script_name = name + ".py"
    _sast_expand_template(
        name = script_name,
        srcs_patterns = srcs,
        analyzers = analyzers,
        tool_overrides = system_tools,
        **{k: v for k, v in kwargs.items() if k in _FORWARDED}
    )

    py_binary(
        name = name,
        main = script_name,
        srcs = [script_name],
        imports = [""],
        **kwargs
    )

def _sast_expand_template_impl(ctx):
    script = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.expand_template(
        output = script,
        is_executable = True,
        template = ctx.file._template,
        substitutions = {
            "{srcs_patterns}": repr(ctx.attr.srcs_patterns),
            "{analyzers}": repr(ctx.attr.analyzers),
            "{tool_overrides}": repr(ctx.attr.tool_overrides),
        },
    )
    return DefaultInfo(files = depset([script]))

_sast_expand_template = rule(
    implementation = _sast_expand_template_impl,
    attrs = {
        "srcs_patterns": attr.string_list(mandatory = True),
        "analyzers": attr.string_list(default = ["cppcheck"]),
        "tool_overrides": attr.string_dict(default = {}),
        "_template": attr.label(allow_single_file = True, default = "//cc:sast.template.py"),
    },
)
