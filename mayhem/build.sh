#!/usr/bin/env bash
#
# args/mayhem/build.sh — build Taywee/args' libFuzzer harnesses as sanitized targets (+ standalone
# reproducers). args is a HEADER-ONLY C++ argument parser (args.hxx); the fuzzed surface is the
# parser/value-reader running on attacker-controlled argv tokens / value strings:
#
#   parse_args_fuzzer    — FuzzedDataProvider splits the input into 1..10 argv tokens, then drives
#                          args::ArgumentParser::ParseArgs over Flag/HelpFlag matchers, catching the
#                          parser's exceptions (the OSS-Fuzz harness; the only well-formed fuzzer here).
#
# NB: the repo also ships fuzz/fuzz_parser.cpp and fuzz/fuzz_numeric_parser.cxx, but neither is a
# usable Mayhem target and both are intentionally NOT built:
#   * fuzz_parser.cpp        calls the removed ParseArgs(argc, argv) overload — it no longer COMPILES
#                            against the current args.hxx.
#   * fuzz_numeric_parser.cxx calls args::ValueReader::operator() WITHOUT catching args::ParseError;
#                            ValueReader throws by design on any non-numeric input, so the exception
#                            escapes LLVMFuzzerTestOneInput and std::terminate()s on essentially every
#                            input — a harness defect (a crash-on-startup, not a finding in args).
#
# Inputs are argv TOKENS / value strings (NOT files). We compile the harnesses against the header with
# $SANITIZER_FLAGS so the parser code in args.hxx is fully instrumented.
#
# Build contract comes from the org base ENV (CXX/SANITIZER_FLAGS/LIB_FUZZING_ENGINE/STANDALONE_FUZZ_MAIN/
# SRC). $OUT may be empty in the base; targets always land in /mayhem.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) for SANITIZER_FLAGS so an explicit empty --build-arg builds with NO sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DWARF < 4 required — clang-19 defaults to DWARF-5; pin to dwarf-3 so Mayhem triage works (§6.2 item 10).
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
export SANITIZER_FLAGS DEBUG_FLAGS
: "${CXX:=clang++}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export CXX LIB_FUZZING_ENGINE STANDALONE_FUZZ_MAIN

cd "$SRC"

OUTDIR="/mayhem"
FUZZ_DIR="$SRC/fuzz"
INC="-I$SRC"
STD="-std=c++17"

# Standalone run-once driver (reads one input file, calls LLVMFuzzerTestOneInput once). Compiled as a
# C object once and linked into each -standalone reproducer; no libFuzzer runtime.
STANDALONE_OBJ="/mayhem/standalone_main.o"
${CC:-clang} $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$STANDALONE_OBJ"

# harness <basename> <source-file>
build_harness() {
  local name="$1" src="$2"
  # libFuzzer target -> /mayhem/<name>
  $CXX $STD $SANITIZER_FLAGS $DEBUG_FLAGS $INC \
      "$src" $LIB_FUZZING_ENGINE \
      -o "$OUTDIR/$name"

  # standalone reproducer (no libFuzzer runtime) -> /mayhem/<name>-standalone
  $CXX $STD $SANITIZER_FLAGS $DEBUG_FLAGS $INC \
      "$src" "$STANDALONE_OBJ" \
      -o "$OUTDIR/$name-standalone"

  echo "built $name (+ standalone)"
}

build_harness parse_args_fuzzer "$FUZZ_DIR/parse_args_fuzzer.cpp"

# Behavioral oracle helper — built with normal (non-fuzzer) flags; runs argv through the parser
# and PRINTS extracted values so test.sh can verify them with grep.  No sanitizer / fuzzer engine.
# If this binary is neutered to exit(0), test.sh's grep assertions fail, defeating reward-hacking.
$CXX $STD $DEBUG_FLAGS $INC \
    "$SRC/mayhem/args_behavior_check.cpp" \
    -o "$OUTDIR/args-behavior-check"

echo "build.sh complete:"
ls -la /mayhem/parse_args_fuzzer /mayhem/parse_args_fuzzer-standalone /mayhem/args-behavior-check 2>&1 || true
