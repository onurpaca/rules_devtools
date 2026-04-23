"""ctags() macro — generate ctags/cscope index for code navigation.

Usage:
    load("@rules_devtools//cc:ctags.bzl", "ctags")
    ctags(name = "ctags", srcs = ["src/**/*.cpp", "include/**/*.h"])

    bazel run //:ctags  # generates tags file in workspace root

Tool resolution: hermetic first (if configured), PATH fallback (with warn).
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_FORWARDED = ("tags", "visibility", "compatible_with", "target_compatible_with")

def ctags(name, srcs = None, hermetic = None, system = "ctags", cscope = False, **kwargs):
    """Create a ctags generation target.

    Args:
        name: Target name.
        srcs: Glob patterns for sources. Defaults to common C/C++ extensions.
        hermetic: Label to hermetic ctags binary (tried first).
        system: PATH binary name used as fallback (default "ctags"). Pass None to disable fallback.
        cscope: Also generate cscope database. Default: False.
        **kwargs: Additional common attributes.
    """
    if not srcs:
        srcs = ["**/*.cpp", "**/*.cc", "**/*.cxx", "**/*.c", "**/*.h", "**/*.hpp", "**/*.hxx"]

    script_name = name + ".py"
    _ctags_expand_template(
        name = script_name,
        srcs_patterns = srcs,
        system_path = system or "",
        hermetic_tool = hermetic,
        enable_cscope = cscope,
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

def _ctags_expand_template_impl(ctx):
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
            "{enable_cscope}": repr(ctx.attr.enable_cscope),
        },
    )
    return DefaultInfo(files = depset([script]))

_ctags_expand_template = rule(
    implementation = _ctags_expand_template_impl,
    attrs = {
        "srcs_patterns": attr.string_list(mandatory = True),
        "system_path": attr.string(),
        "hermetic_tool": attr.label(allow_single_file = True),
        "enable_cscope": attr.bool(default = False),
        "_template": attr.label(allow_single_file = True, default = "//cc:ctags.template.py"),
    },
)
