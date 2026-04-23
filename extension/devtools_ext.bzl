"""Module extension for rules_devtools hermetic tool downloads and workspace setup."""

load("//tools:versions.bzl", "BUILDTOOLS_TOOLS", "DEFAULT_BUILDTOOLS_VERSION", "DEFAULT_LLVM_VERSION", "LLVM_TOOLS")
load(":devtools_repo.bzl", "devtools_repo")
load(":download_buildtools.bzl", "download_buildtools")
load(":download_tool.bzl", "download_tool")

def _resolve_version(value, default):
    """Map a tag attribute to a concrete version, or None to skip downloading."""
    if value == "":
        return None
    if value == "default":
        return default
    return value

def _devtools_extension_impl(module_ctx):
    """Module extension that downloads hermetic tools and generates devtools targets."""
    llvm_downloaded = False
    buildtools_downloaded = False

    for mod in module_ctx.modules:
        for tag in mod.tags.configure:
            llvm_version = _resolve_version(tag.llvm, DEFAULT_LLVM_VERSION)
            if llvm_version and not llvm_downloaded:
                for tool_name, binary_subpath in LLVM_TOOLS.items():
                    download_tool(
                        name = tool_name.replace("-", "_"),
                        tool_name = tool_name,
                        version = llvm_version,
                        binary_subpath = binary_subpath,
                    )
                llvm_downloaded = True

            buildtools_version = _resolve_version(tag.buildtools, DEFAULT_BUILDTOOLS_VERSION)
            if buildtools_version and not buildtools_downloaded:
                for tool_name in BUILDTOOLS_TOOLS:
                    download_buildtools(
                        name = tool_name,
                        tool_name = tool_name,
                        version = buildtools_version,
                    )
                buildtools_downloaded = True

            clang_format_hermetic = tag.clang_format_hermetic
            clang_tidy_hermetic = tag.clang_tidy_hermetic
            iwyu_hermetic = tag.iwyu_hermetic
            ctags_hermetic = tag.ctags_hermetic
            buildifier_hermetic = tag.buildifier_hermetic
            buildozer_hermetic = tag.buildozer_hermetic

            if llvm_version:
                if not clang_format_hermetic:
                    clang_format_hermetic = "@clang_format//:clang-format"
                if not clang_tidy_hermetic:
                    clang_tidy_hermetic = "@clang_tidy//:clang-tidy"

            if buildtools_version:
                if not buildifier_hermetic:
                    buildifier_hermetic = "@buildifier//:buildifier"
                if not buildozer_hermetic:
                    buildozer_hermetic = "@buildozer//:buildozer"

            devtools_repo(
                name = tag.name,
                targets = tag.targets,
                format_srcs = tag.format_srcs,
                lint_srcs = tag.lint_srcs,
                sast_srcs = tag.sast_srcs,
                ctags_srcs = tag.ctags_srcs,
                buildifier_srcs = tag.buildifier_srcs,
                clang_format_system = tag.clang_format_system,
                clang_format_hermetic = clang_format_hermetic,
                clang_tidy_system = tag.clang_tidy_system,
                clang_tidy_hermetic = clang_tidy_hermetic,
                iwyu_system = tag.iwyu_system,
                iwyu_hermetic = iwyu_hermetic,
                ctags_system = tag.ctags_system,
                ctags_hermetic = ctags_hermetic,
                buildifier_system = tag.buildifier_system,
                buildifier_hermetic = buildifier_hermetic,
                buildozer_system = tag.buildozer_system,
                buildozer_hermetic = buildozer_hermetic,
                analyzers = tag.analyzers,
                exclude_headers = tag.exclude_headers,
                exclude_external_sources = tag.exclude_external_sources,
                enable_cscope = tag.enable_cscope,
                buildifier_mode = tag.buildifier_mode,
                buildifier_lint = tag.buildifier_lint,
                buildifier_warnings = tag.buildifier_warnings,
                py_srcs = tag.py_srcs,
                ruff_system = tag.ruff_system,
                black_system = tag.black_system,
                mypy_system = tag.mypy_system,
            )

_configure_tag = tag_class(
    attrs = {
        "name": attr.string(default = "devtools", doc = "Repository name. Use with use_repo()."),
        "targets": attr.string(default = "//...", doc = "Bazel targets to analyze."),
        "llvm": attr.string(
            default = "",
            doc = "LLVM version to download for hermetic clang-format/clang-tidy. " +
                  "Use \"default\" for the bundled default, an explicit version (e.g. \"18.1.8\"), " +
                  "or leave empty to use system tools.",
        ),
        "buildtools": attr.string(
            default = "",
            doc = "Buildtools version to download for hermetic buildifier/buildozer. " +
                  "Use \"default\" for the bundled default, an explicit version (e.g. \"8.5.1\"), " +
                  "or leave empty to use system tools.",
        ),
        "format_srcs": attr.string_list(doc = "Glob patterns for clang_format/clang_tidy/sast/ctags sources."),
        "lint_srcs": attr.string_list(doc = "Glob patterns for clang_tidy. Defaults to format_srcs."),
        "sast_srcs": attr.string_list(doc = "Glob patterns for sast. Defaults to format_srcs."),
        "ctags_srcs": attr.string_list(doc = "Glob patterns for ctags. Defaults to format_srcs."),
        "buildifier_srcs": attr.string_list(doc = "Glob patterns for buildifier sources."),
        "clang_format_system": attr.string(default = "clang-format"),
        "clang_format_hermetic": attr.string(default = "", doc = "Label to hermetic clang-format. Auto-set when llvm is requested."),
        "clang_tidy_system": attr.string(default = "clang-tidy"),
        "clang_tidy_hermetic": attr.string(default = "", doc = "Label to hermetic clang-tidy. Auto-set when llvm is requested."),
        "iwyu_system": attr.string(default = "include-what-you-use"),
        "iwyu_hermetic": attr.string(default = "", doc = "Label to hermetic IWYU binary."),
        "ctags_system": attr.string(default = "ctags"),
        "ctags_hermetic": attr.string(default = "", doc = "Label to hermetic ctags binary."),
        "buildifier_system": attr.string(default = "buildifier"),
        "buildifier_hermetic": attr.string(default = "", doc = "Label to hermetic buildifier. Auto-set when buildtools is requested."),
        "buildozer_system": attr.string(default = "buildozer"),
        "buildozer_hermetic": attr.string(default = "", doc = "Label to hermetic buildozer. Auto-set when buildtools is requested."),
        "analyzers": attr.string_list(doc = "List of analyzers for sast target."),
        "exclude_headers": attr.string(default = "", doc = "Header exclusion mode for compile_commands."),
        "exclude_external_sources": attr.bool(default = False),
        "enable_cscope": attr.bool(default = False),
        "buildifier_mode": attr.string(default = "fix"),
        "buildifier_lint": attr.string(default = "warn"),
        "buildifier_warnings": attr.string(default = ""),
        "py_srcs": attr.string_list(doc = "Glob patterns for Python sources."),
        "ruff_system": attr.string(default = "ruff"),
        "black_system": attr.string(default = "black"),
        "mypy_system": attr.string(default = "mypy"),
    },
)

devtools_extension = module_extension(
    implementation = _devtools_extension_impl,
    tag_classes = {
        "configure": _configure_tag,
    },
)
