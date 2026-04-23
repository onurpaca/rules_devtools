"""clang_tidy() macro — run clang-tidy on source files.

Usage:
    load("@rules_devtools//cc:clang_tidy.bzl", "clang_tidy")
    clang_tidy(name = "clang_tidy", srcs = ["src/**/*.cpp"])

    bazel run //:clang_tidy           # run clang-tidy
    bazel run //:clang_tidy -- --fix  # auto-fix issues

Tool resolution: hermetic first (if configured), PATH fallback (with warn).
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_FORWARDED = ("tags", "visibility", "compatible_with", "target_compatible_with")

def clang_tidy(name, srcs = None, hermetic = None, system = "clang-tidy", compile_commands_dir = "", **kwargs):
    """Create a clang_tidy target.

    Args:
        name: Target name.
        srcs: Glob patterns for sources. Defaults to common C/C++ extensions.
        hermetic: Label to hermetic clang-tidy binary (tried first).
        system: PATH binary name used as fallback (default "clang-tidy"). Pass None to disable fallback.
        compile_commands_dir: Directory containing compile_commands.json. Defaults to workspace root.
        **kwargs: Additional common attributes.
    """
    if not srcs:
        srcs = ["**/*.cpp", "**/*.cc", "**/*.cxx"]

    script_name = name + ".py"
    _clang_tidy_expand_template(
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

def _clang_tidy_expand_template_impl(ctx):
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

_clang_tidy_expand_template = rule(
    implementation = _clang_tidy_expand_template_impl,
    attrs = {
        "srcs_patterns": attr.string_list(mandatory = True),
        "system_path": attr.string(),
        "hermetic_tool": attr.label(allow_single_file = True),
        "compile_commands_dir": attr.string(default = ""),
        "_template": attr.label(allow_single_file = True, default = "//cc:clang_tidy.template.py"),
    },
)
