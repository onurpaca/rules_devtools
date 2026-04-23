#!/usr/bin/env bash
# Smoke test: build every dogfood target and exercise the key entrypoints.
#
# Catches load/wiring regressions in the module extension, the bundle macro,
# and the repository rule that generates @rd_internal_devtools//:BUILD.bazel.
#
# Runs from the repo root. Exits non-zero on any failure.

set -euo pipefail

cd "$(dirname "$0")/.."

# Resolve Bazel launcher. Users often alias `bazel` to `bazelisk`; aliases
# don't cross subshells, so prefer the real binary.
BAZEL="${BAZEL:-}"
if [[ -z "$BAZEL" ]]; then
  if command -v bazelisk >/dev/null 2>&1; then BAZEL=bazelisk
  elif command -v bazel >/dev/null 2>&1; then BAZEL=bazel
  else echo "bazel/bazelisk not found on PATH" >&2; exit 1
  fi
fi

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

pass=0
fail=0

run() {
  local desc="$1"; shift
  printf "%s[smoke]%s %s ... " "$BLUE" "$NC" "$desc"
  if "${@/#bazel/$BAZEL}" >/tmp/rd_smoke.log 2>&1; then
    printf "%sOK%s\n" "$GREEN" "$NC"
    pass=$((pass + 1))
  else
    printf "%sFAIL%s\n" "$RED" "$NC"
    echo "---- last 40 lines ----"
    tail -n 40 /tmp/rd_smoke.log
    fail=$((fail + 1))
  fi
}

DOGFOOD_TARGETS=(
  //:dev_compile_commands
  //:dev_clang_format
  //:dev_format_all
  //:dev_clang_tidy
  //:dev_lint_all
  //:dev_sast
  //:dev_iwyu
  //:dev_unused_deps
  //:dev_bep_report
  //:dev_depgraph
  //:dev_ctags
  //:dev_buildifier
  //:dev_buildozer
)

EXTENSION_TARGETS=(
  @rd_internal_devtools//:compile_commands
  @rd_internal_devtools//:clang_format
  @rd_internal_devtools//:format_all
  @rd_internal_devtools//:clang_tidy
  @rd_internal_devtools//:lint_all
  @rd_internal_devtools//:buildifier
  @rd_internal_devtools//:buildozer
)

for t in "${DOGFOOD_TARGETS[@]}"; do
  run "build $t" bazel build "$t"
done

for t in "${EXTENSION_TARGETS[@]}"; do
  run "build $t" bazel build "$t"
done

run "stardoc //docs:all" bazel build //docs:all
run "dev_buildifier -- --help" bazel run //:dev_buildifier -- --help
run "dev_format_all --check (own .bzl + BUILD files)" \
  bazel run //:dev_format_all -- --check

echo
printf "Passed: %s%d%s   Failed: %s%d%s\n" "$GREEN" "$pass" "$NC" "$RED" "$fail" "$NC"
[[ "$fail" -eq 0 ]]
