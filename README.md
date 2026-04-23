# rules_devtools

Bazel module for C/C++, Bazel, and Python developer tools: formatting, linting, static analysis, code navigation, and BUILD file tooling. One `use_extension` call wires up everything.

## Usage

```starlark
# MODULE.bazel
bazel_dep(name = "rules_devtools", version = "1.8.0")
local_path_override(module_name = "rules_devtools", path = "../rules_devtools")

devtools = use_extension("@rules_devtools//extension:devtools_ext.bzl", "devtools_extension")
devtools.configure(
    targets = "//...",
    llvm = "default",         # for C/C++: clang-format, clang-tidy, iwyu, compile_commands
    buildtools = "default",   # for Bazel: buildifier, buildozer
    format_srcs = ["src/**/*.cpp", "src/**/*.hpp", "src/**/*.h"],
    py_srcs = ["src/**/*.py"],
)
use_repo(devtools, "devtools")
```

## All Targets

Run any target with `bazel run @devtools//:TARGET_NAME -- [args]`. All extra args are passed transparently to the underlying tool.

### Orchestrators (run all tools in one pass)

| Target | Purpose | CI check | Auto-fix |
|---|---|---|---|
| `format_all` | Format C/C++ (clang-format) + Bazel (buildifier) + Python (ruff) | `-- --check` | (default) |
| `lint_all` | Lint C/C++ (clang-tidy) + Bazel (buildifier lint) + Python (ruff check) | `-- --check` | `-- --fix` |

### C/C++ (`//cc:*`)

| Target | Purpose | CI check | Auto-fix |
|---|---|---|---|
| `clang_format` | Format C/C++ source | `-- --check` | `-i` |
| `clang_tidy` | Lint C/C++ source | — | `-- --fix` |
| `compile_commands` | Generate `compile_commands.json` for clangd | — | — |
| `iwyu` | Analyze `#include` usage | — | applies fix |
| `unused_deps` | Find stale BUILD deps | — | — |
| `sast` | Multi-analyzer: cppcheck + semgrep | — | — |
| `ctags` | Generate code index for navigation | — | — |

### Bazel (`//bazel:*`)

| Target | Purpose | CI check | Auto-fix |
|---|---|---|---|
| `buildifier` | Format BUILD/.bzl files | `-- --check` | (default) |
| `buildozer` | Edit BUILD files programmatically | — | — |
| `depgraph` | Visualize dependency graph | — | — |
| `bep_report` | Parse BEP JSON into a report | — | — |

### Python (system PATH only)

| Target | Purpose | CI check | Auto-fix |
|---|---|---|---|
| `ruff` | Format + lint Python (wraps `ruff format` + `ruff check`) | `-- --check` | (default) |
| `black` | Format Python | `-- --check` | `-i` |
| `mypy` | Type-check Python | — | — |

## Examples

```sh
# Format everything (C/C++ + Bazel + Python in one pass)
bazel run @devtools//:format_all

# CI: verify nothing needs formatting
bazel run @devtools//:format_all -- --check

# Lint everything (C/C++ + Bazel + Python in one pass)
bazel run @devtools//:lint_all

# Auto-fix lint issues
bazel run @devtools//:lint_all -- --fix

# Run just clang-format check on C/C++
bazel run @devtools//:clang_format -- --check

# Run just ruff check on Python
bazel run @devtools//:ruff -- --check

# Run just black check on Python
bazel run @devtools//:black -- --check

# Run just mypy on Python
bazel run @devtools//:mypy -- src/

# Generate compile_commands.json for clangd
bazel run @devtools//:compile_commands
```

## Tool Resolution

All tools follow the same resolution order:
1. **Hermetic** — hermetic binary from LLVM/buildtools (default for C/C++ and Bazel tools)
2. **System PATH** — fallback with warning if hermetic not available

Python tools use system PATH only (ruff, black, mypy must be on PATH).

## Configuration

```starlark
devtools.configure(
    targets = "//...",                           # for compile_commands, unused_deps
    llvm = "default",                             # hermetic LLVM version, or "default"/"none"
    buildtools = "default",                       # hermetic buildtools version, or "default"/"none"
    format_srcs = ["src/**/*.cpp", "src/**/*.h"],  # for clang_format
    lint_srcs = ["src/**/*.cpp"],                  # for clang_tidy (default: format_srcs)
    sast_srcs = ["src/**/*.cpp"],                  # for sast (default: format_srcs)
    ctags_srcs = ["src/**/*.cpp"],                 # for ctags (default: format_srcs)
    py_srcs = ["src/**/*.py"],                     # for ruff/black/mypy
)
```

To use system tools without hermetic downloads:

```starlark
devtools.configure(
    llvm = "none",         # use system clang-format, clang-tidy, etc.
    buildtools = "none",   # use system buildifier, buildozer
    py_srcs = ["src/**/*.py"],
)
```

## Platforms

Linux (x86_64/arm64), macOS arm64, Windows x86_64. macOS x86_64 LLVM not available (no upstream prebuilt).

## License

Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for third-party attributions.

## Inspiration

`compile_commands` generation is powered by the aquery-based approach from
[hedronvision/bazel-compile-commands-extractor](https://github.com/hedronvision/bazel-compile-commands-extractor).
See [NOTICE](NOTICE) for details.
