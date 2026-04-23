load(":devtools.bzl", "devtools")

########################################
# rules_devtools: Developer Workflow Toolkit
# Single bundle macro creates all devtools targets:
#   bazel run //:dev_format_all                  # C++ + Bazel + Python in one pass
#   bazel run //:dev_format_all -- --check
#   bazel run //:dev_lint_all                    # C++ + Bazel + Python in one pass
#   bazel run //:dev_lint_all -- --fix
#   bazel run //:dev_clang_format
#   bazel run //:dev_clang_format -- --check
#   bazel run //:dev_clang_tidy
#   bazel run //:dev_clang_tidy -- --fix
#   bazel run //:dev_sast
#   bazel run //:dev_iwyu
#   bazel run //:dev_ctags
#   bazel run //:dev_buildifier
#   bazel run //:dev_buildifier -- --check
#   bazel run //:dev_buildozer -- 'add deps //foo:bar' //my:target
#   bazel run //:dev_compile_commands
#   bazel run //:dev_unused_deps
#   bazel run //:dev_depgraph -- //src:main
#   bazel run //:dev_bep_report -- /tmp/bep.json
#   bazel run //:dev_ruff
#   bazel run //:dev_ruff -- --check
#   bazel run //:dev_black
#   bazel run //:dev_black -- --check
#   bazel run //:dev_mypy
devtools(
    name = "dev",
    targets = "//...",
    py_srcs = ["**/*.py"],
)

# Stardoc users only: Depend on "@rules_devtools//:bzl_srcs_for_stardoc" as needed.
# Why? Stardoc requires all loaded files to be listed as deps; without this we'd prevent users from running Stardoc on their code when they load from this tool in, e.g., their own workspace.bzl or wrapping macros.
exports_files(["devtools.bzl"])

filegroup(
    name = "bzl_srcs_for_stardoc",
    srcs = glob(["**/*.bzl"]) + [
        "@bazel_tools//tools:bzl_srcs",
    ],
    visibility = ["//visibility:public"],
)
