#!/usr/bin/env bash
# lint-gate.sh - php -l gate for a PHP project, run inside a php:<version>-cli container.
#
# Usage:
#   lint-gate.sh <php-version> [path ...]      lint from the project root (default: .)
#   lint-gate.sh --negative-control [version]  prove the gate fails on bad files
#
# The gate passes only when every linted file prints "No syntax errors detected"
# and nothing else. `php -l` exits 0 for files that only raise Deprecated notices,
# so the exit code is not trusted. vendor/ is skipped. Each file is linted twice,
# with short_open_tag=0 and short_open_tag=1, the same as the CI lint job.
#
# Exit codes: 0 gate passed, 1 gate failed, 2 usage error (bad version or a path that does not exist).

set -u

readonly DEFAULT_VERSION="8.4"
readonly OK_PATTERN='^No syntax errors detected'
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

usage() {
  cat <<'EOF'
Usage:
  lint-gate.sh <php-version> [path ...]      e.g. lint-gate.sh 8.4 application index.php
  lint-gate.sh --negative-control [version]  e.g. lint-gate.sh --negative-control 8.5

Run from the project root. Requires docker. Paths are relative to the project root and must exist.
EOF
}

# check_version <version>: accept MAJOR.MINOR only, e.g. 8.4
check_version() {
  case "$1" in
    [0-9].[0-9]|[0-9].[0-9][0-9]) return 0 ;;
    *) echo "lint-gate: invalid PHP version '$1' (expected MAJOR.MINOR, e.g. 8.4)" >&2; return 2 ;;
  esac
}

# ensure_image <version>: pull php:<version>-cli if it is not local yet.
# Pull progress goes to the terminal, not into the lint output.
ensure_image() {
  if ! docker image inspect "php:$1-cli" >/dev/null 2>&1; then
    echo "lint-gate: pulling php:$1-cli" >&2
    docker pull "php:$1-cli" >&2 || return 1
  fi
}

# run_lint <version> <host-dir> <out-file> [path ...]
# Mounts host-dir read-only at /src and writes the combined php -l output to out-file.
run_lint() {
  local version="$1" host_dir="$2" out="$3"
  shift 3
  [ "$#" -eq 0 ] && set -- .
  docker run --rm -v "$host_dir:/src:ro" -w /src "php:${version}-cli" sh -c '
    log=/tmp/lint.log
    : > "$log"
    for sot in 0 1; do
      find "$@" -name "*.php" ! -path "*/vendor/*" ! -path "vendor/*" -exec \
        php -d short_open_tag="$sot" -d error_reporting=-1 -d display_errors=1 -d log_errors=0 -l {} \; \
        >> "$log" 2>&1
    done
    cat "$log"
  ' sh "$@" > "$out" 2>&1
  return $?
}

# judge <docker-rc> <out-file>: print a summary and return 0 only for a clean gate.
judge() {
  local rc="$1" out="$2" ok bad
  ok="$(grep -c "$OK_PATTERN" "$out" 2>/dev/null || true)"
  bad="$(grep -v "$OK_PATTERN" "$out" 2>/dev/null | grep -c . || true)"
  ok="${ok:-0}"
  bad="${bad:-0}"
  if [ "$rc" -eq 0 ] && [ "$ok" -gt 0 ] && [ "$bad" -eq 0 ]; then
    echo "GATE PASS: $ok results, no errors or deprecations"
    return 0
  fi
  echo "GATE FAIL: $ok ok result(s), $bad non-OK line(s), docker exit=$rc"
  if [ "$ok" -eq 0 ]; then
    echo "  (no 'No syntax errors detected' lines: no PHP files found, or docker failed)"
  fi
  # Each file is linted twice (short_open_tag 0 and 1), so the same message can repeat.
  grep -v "$OK_PATTERN" "$out" | grep . | awk '!seen[$0]++' | head -n 200
  return 1
}

# lint_project <version> [path ...]: the real gate, run from the current directory.
lint_project() {
  local version="$1"
  shift
  local p missing=0
  for p in "$@"; do
    [ -e "$p" ] || { echo "lint-gate: path not found: $p (pass only paths that exist)" >&2; missing=1; }
  done
  [ "$missing" -eq 0 ] || return 2
  local out="$TMP_DIR/lint-out.txt"
  ensure_image "$version" || { echo "GATE FAIL: cannot get php:$version-cli" >&2; return 1; }
  run_lint "$version" "$(pwd)" "$out" "$@"
  local rc=$?
  judge "$rc" "$out"
}

# expect_gate <version> <name> <host-dir> <pass|fail>: lint host-dir, compare with expectation.
expect_gate() {
  local version="$1" name="$2" dir="$3" expected="$4"
  local out="$TMP_DIR/neg-$name.txt" rc got
  run_lint "$version" "$dir" "$out" .
  rc=$?
  if judge "$rc" "$out" >/dev/null; then got="pass"; else got="fail"; fi
  if [ "$got" = "$expected" ]; then
    echo "  [ok]   $name: gate $got, as expected"
    return 0
  fi
  echo "  [BAD]  $name: gate $got, expected $expected"
  judge "$rc" "$out" | sed 's/^/         /'
  return 1
}

# negative_control [version]: a clean file must pass, a deprecated file and a
# parse-error file must each fail. Without this, a gate can silently pass.
negative_control() {
  local version="${1:-$DEFAULT_VERSION}"
  local root="$TMP_DIR/neg"
  local fails=0
  check_version "$version" || return 2
  ensure_image "$version" || { echo "negative control: cannot get php:$version-cli" >&2; return 1; }

  mkdir -p "$root/clean" "$root/deprecated" "$root/parse"
  printf '<?php\necho "ok";\n' > "$root/clean/ok.php"
  printf '<?php\n$b = "x";\necho "${b}";\n' > "$root/deprecated/deprecated.php"
  printf '<?php\necho "x"\n' > "$root/parse/broken.php"

  echo "Negative control, php:$version-cli"
  expect_gate "$version" clean "$root/clean" pass || fails=$((fails + 1))
  expect_gate "$version" deprecated-only "$root/deprecated" fail || fails=$((fails + 1))
  expect_gate "$version" parse-error "$root/parse" fail || fails=$((fails + 1))

  # Why the gate reads output: the deprecated-only file exits 0 under plain php -l.
  echo "  Why not the exit code: php -l on the deprecated-only file:"
  docker run --rm -v "$root/deprecated:/src:ro" "php:${version}-cli" php -l /src/deprecated.php 2>&1 \
    | sed 's/^/         /'
  echo "         exit=${PIPESTATUS[0]}"

  if [ "$fails" -eq 0 ]; then
    echo "Negative control PASSED: the gate behaves as expected."
    return 0
  fi
  echo "Negative control FAILED: $fails expectation(s) not met."
  return 1
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
    "")
      usage >&2
      return 2
      ;;
    --negative-control)
      shift
      negative_control "$@"
      return $?
      ;;
  esac

  local version="$1"
  shift
  check_version "$version" || return 2
  lint_project "$version" "$@"
}

main "$@"
