"""compile_commands() macro — generate compile_commands.json from Bazel aquery.

Usage:
    load("@rules_devtools//cc:compile_commands.bzl", "compile_commands")
    compile_commands(name = "compile_commands", targets = "//...")

    bazel run //:compile_commands  # writes compile_commands.json to workspace root

Attribution: the macro shape, the target-coercion behavior (string/list/dict
inputs), and the use of `mnemonic("CppCompile|ObjcCompile|CudaCompile", deps(...))`
to enumerate compile actions are derived from
https://github.com/hedronvision/bazel-compile-commands-extractor (Apache-2.0).
See NOTICE at the repository root.
"""

load("@rules_python//python:py_binary.bzl", "py_binary")

_DEFAULT_TARGET = "@//..."
_TEMPLATE_LABEL = "//cc:compile_commands.template.py"
_FORWARDED_KWARGS = ("tags", "visibility", "compatible_with", "target_compatible_with")

def _absolutize(label):
    """Convert a possibly-relative label to its absolute form."""
    if label.startswith("@") or label.startswith("//"):
        return label
    return "{repo}//{pkg}:{name}".format(
        repo = native.repository_name(),
        pkg = native.package_name(),
        name = label.removeprefix(":"),
    )

def _coerce_to_dict(targets):
    """Map any supported `targets` shape to a {label: extra_flags} dict.

    Returns the value unchanged for select() so it propagates through.
    """
    target_kind = type(targets)
    if target_kind == "select":
        return targets
    if target_kind == "dict":
        return dict(targets)
    if target_kind == "list":
        result = {}
        for label in targets:
            result[label] = ""
        return result
    return {targets: ""}

def _normalize_targets(targets):
    """Produce {absolute_label: extra_flags} from user input."""
    if not targets:
        return {_DEFAULT_TARGET: ""}

    coerced = _coerce_to_dict(targets)
    if type(coerced) == "select":
        return coerced

    resolved = {}
    for label, extra in coerced.items():
        resolved[_absolutize(label)] = extra
    return resolved

def compile_commands(name, targets = None, exclude_headers = None, exclude_external_sources = False, **kwargs):
    """Create a compile_commands.json generation target.

    Args:
        name: Target name.
        targets: Targets to query. Accepts a single label string, a list of labels,
            or a dict mapping labels to extra Bazel flags. Defaults to "//...".
        exclude_headers: "all" to drop all header entries, "external" to drop
            only external headers, None (default) to keep everything.
        exclude_external_sources: If True, omit sources from external workspaces.
        **kwargs: Additional common attributes (visibility, tags, etc.).
    """
    label_to_flags = _normalize_targets(targets)

    template_target = name + ".py"
    forwarded = {k: v for k, v in kwargs.items() if k in _FORWARDED_KWARGS}

    _expand_compile_commands_template(
        name = template_target,
        label_to_flags = label_to_flags,
        exclude_headers = exclude_headers or "",
        exclude_external_sources = exclude_external_sources,
        **forwarded
    )

    py_binary(
        name = name,
        main = template_target,
        srcs = [template_target],
        imports = [""],
        **kwargs
    )

def _expand_compile_commands_template_impl(ctx):
    """Render the runtime script with baked-in configuration."""
    pairs = ctx.attr.label_to_flags.items()
    target_lines = "\n".join(["        {},".format(repr(pair)) for pair in pairs])

    out = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.expand_template(
        output = out,
        is_executable = True,
        template = ctx.file._template,
        substitutions = {
            "        # __TARGETS__": target_lines,
            "__EXCLUDE_HEADERS__": repr(ctx.attr.exclude_headers),
            "__EXCLUDE_EXTERNAL_SOURCES__": repr(ctx.attr.exclude_external_sources),
        },
    )
    return DefaultInfo(files = depset([out]))

_expand_compile_commands_template = rule(
    implementation = _expand_compile_commands_template_impl,
    attrs = {
        "label_to_flags": attr.string_dict(mandatory = True),
        "exclude_headers": attr.string(values = ["all", "external", ""]),
        "exclude_external_sources": attr.bool(default = False),
        "_template": attr.label(allow_single_file = True, default = _TEMPLATE_LABEL),
    },
)
