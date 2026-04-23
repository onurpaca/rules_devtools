"""buildifier() macro — run buildifier on Bazel files.

Usage:
    load("@rules_devtools//bazel:buildifier.bzl", "buildifier")
    buildifier(name = "buildifier")

    bazel run //:buildifier             # format Bazel files in-place
    bazel run //:buildifier -- --check  # CI mode: check only, exit 1 if unformatted

Tool resolution: hermetic first (if configured), PATH fallback (with warn).
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_FORWARDED = ("tags", "visibility", "compatible_with", "target_compatible_with")

def buildifier(
        name,
        srcs = None,
        mode = "fix",
        lint = "warn",
        warnings = "",
        hermetic = None,
        system = "buildifier",
        **kwargs):
    """Create a buildifier target.

    Args:
        name: Target name.
        srcs: Glob patterns for Bazel files to format. Defaults to standard Bazel file patterns.
        mode: Buildifier mode: "fix", "check", "diff", or "print_if_changed". Default: "fix".
        lint: Lint mode: "off", "warn", or "fix". Default: "warn".
        warnings: Comma-separated list of warnings to enable (empty = defaults).
        hermetic: Label to hermetic buildifier binary (tried first).
        system: PATH binary name used as fallback (default "buildifier"). Pass None to disable fallback.
        **kwargs: Additional common attributes.
    """
    if not srcs:
        srcs = ["**/BUILD", "**/BUILD.bazel", "**/*.bzl", "**/WORKSPACE", "**/WORKSPACE.bazel", "**/MODULE.bazel"]

    script_name = name + ".py"
    _buildifier_expand_template(
        name = script_name,
        srcs_patterns = srcs,
        system_path = system or "",
        hermetic_tool = hermetic,
        mode = mode,
        lint = lint,
        warnings = warnings,
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

def _buildifier_expand_template_impl(ctx):
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
            "{mode}": repr(ctx.attr.mode),
            "{lint}": repr(ctx.attr.lint),
            "{warnings}": repr(ctx.attr.warnings),
        },
    )
    return DefaultInfo(files = depset([script]))

_buildifier_expand_template = rule(
    implementation = _buildifier_expand_template_impl,
    attrs = {
        "srcs_patterns": attr.string_list(mandatory = True),
        "system_path": attr.string(),
        "hermetic_tool": attr.label(allow_single_file = True),
        "mode": attr.string(default = "fix"),
        "lint": attr.string(default = "warn"),
        "warnings": attr.string(default = ""),
        "_template": attr.label(allow_single_file = True, default = "//bazel:buildifier.template.py"),
    },
)
