#!/usr/bin/env bash
#
# args/mayhem/test.sh — behavioral oracle for Taywee/args.
# Runs /mayhem/args-behavior-check (built by build.sh) which parses KNOWN argument
# vectors through the parser and PRINTS extracted values.  We grep the output for
# the specific expected lines; if the program is neutered to exit(0) it produces NO
# output and the grep assertions fail — this defeats reward-hacking (§6.3).
#
# Anti-reward-hack contract: a patch that blanks the program body to `exit(0)` MUST
# fail this script.  verify-repo confirms this mechanically with an LD_PRELOAD neuter.
#
# Emits a CTRF summary (ctrf.io) and exits non-zero iff any test failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

CHECKER="${SRC:-/mayhem}/mayhem/args-behavior-check"
# build.sh deposits the binary into /mayhem/
BIN="/mayhem/args-behavior-check"

# Prefer the image-installed binary; fall back to SRC path (local runs).
if [ -x "$BIN" ]; then
  CHECKER="$BIN"
elif [ ! -x "$CHECKER" ]; then
  echo "args-behavior-check not found at $BIN or $CHECKER — did build.sh run?" >&2
  exit 2
fi

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-${SRC:-/mayhem}/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Run the behavioral checker and capture stdout+stderr separately.
echo "=== running args behavioral checker: $CHECKER ==="
CHECKER_OUT="$("$CHECKER" 2>/tmp/args-check-err.txt)"; CHECKER_RC=$?
echo "$CHECKER_OUT"
[ -s /tmp/args-check-err.txt ] && cat /tmp/args-check-err.txt >&2

# Each "PASS <tc>: <key>=<val>" line is a behavioral assertion that survived the run.
# The final "ALL_PASS" line is only printed when ALL internal cases succeeded.
#
# Sabotage contract: if the binary is LD_PRELOAD-neutered to _exit(0), CHECKER_OUT is
# EMPTY — none of the greps below match, PASS_COUNT=0, FAIL_COUNT=TOTAL, and the
# CTRF summary reports failures.

TOTAL=7   # 3 in TC1 + 3 in TC2 + 1 in TC3; must match args_behavior_check.cpp

PASS_COUNT=0
FAIL_COUNT=0

# Helper: assert a substring appears in the checker output.
assert_output() {
  local label="$1" expected="$2"
  if printf '%s\n' "$CHECKER_OUT" | grep -qF "$expected"; then
    echo "  OK  $label: found '$expected'"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
  else
    echo "  FAIL $label: expected '$expected' in output" >&2
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  fi
}

# TC1: flag + string value + integer value
assert_output "TC1/bar"   "PASS TC1: bar=true"
assert_output "TC1/foo"   "PASS TC1: foo=hello"
assert_output "TC1/count" "PASS TC1: count=42"

# TC2: short flag grouping + double value
assert_output "TC2/bar"   "PASS TC2: bar=true"
assert_output "TC2/foo"   "PASS TC2: foo=test"
assert_output "TC2/baz"   "PASS TC2: baz=755.5"

# TC3: default value when flag absent
assert_output "TC3/opt"   "PASS TC3: opt=unset"

# Also verify the checker itself exited cleanly (all internal assertions passed).
if [ "$CHECKER_RC" -ne 0 ]; then
  echo "  FAIL args-behavior-check exited $CHECKER_RC" >&2
  FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  TOTAL=$(( TOTAL + 1 ))
fi

emit_ctrf "args-behavior" "$PASS_COUNT" "$FAIL_COUNT"
