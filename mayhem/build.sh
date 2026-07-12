#!/usr/bin/env bash
#
# mayhem/build.sh — build pyconcrete's fuzz harness + standalone reproducer.
#
# Fuzz surface: the native decryption function fnDecryptBuffer (src/pyconcrete_ext/pyconcrete.c),
# exposed to Python as _pyconcrete.decrypt_buffer(data) and fed the raw bytes of a `.pye` file by
# src/pyconcrete/__init__.py. The archived target ran the whole pyconcrete EXECUTABLE on a file
# (embedded CPython per input -> ~no native edges); we drive the same C code path in-process.
#
# Air-gapped: this compiles from vendored sources only (no network). The Python dev headers and the
# test suite's Python deps are installed by mayhem/Dockerfile (as root) so this stays offline-clean.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# Passphrase bakes the AES key into secret_key.h. Any value works — it does not affect
# reachability of the decrypt code path the harness fuzzes.
PASSPHRASE="fuzzpyconcrete"

EXT_DIR="$SRC/src/pyconcrete_ext"
GEN_DIR="$SRC/mayhem/_gen"
rm -rf "$GEN_DIR"; mkdir -p "$GEN_DIR"

# Mirror meson's gen_secret_key custom_target: writes secret_key.h into the CWD.
( cd "$GEN_DIR" && python3 "$SRC/meson_utility/gen_secret_key.py" "$PASSPHRASE" )
test -s "$GEN_DIR/secret_key.h"

EXT_SRCS=(
  "$EXT_DIR/pyconcrete.c"
  "$EXT_DIR/pyconcrete_module.c"
  "$EXT_DIR/openaes/src/oaes_base64.c"
  "$EXT_DIR/openaes/src/oaes_lib.c"
)
INCS=(
  -I"$EXT_DIR"
  -I"$EXT_DIR/openaes/inc"
  -I"$GEN_DIR"
)
DEFS=( -DPYCONCRETE_EXT='".pye"' )

PY_INC="$(python3-config --includes)"
PY_LD="$(python3-config --ldflags --embed)"

# 1) libFuzzer harness — the fuzz target.
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    "${DEFS[@]}" $PY_INC "${INCS[@]}" \
    "$SRC/mayhem/fuzz_decrypt_buffer.c" "${EXT_SRCS[@]}" \
    $PY_LD -o /mayhem/pyconcrete

# 2) standalone reproducer — same harness, StandaloneFuzzTargetMain (no libFuzzer runtime).
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS \
    "${DEFS[@]}" $PY_INC "${INCS[@]}" \
    "$STANDALONE_FUZZ_MAIN" "$SRC/mayhem/fuzz_decrypt_buffer.c" "${EXT_SRCS[@]}" \
    $PY_LD -o /mayhem/pyconcrete-standalone

echo "build.sh: built /mayhem/pyconcrete and /mayhem/pyconcrete-standalone"

# 3) Test suite: pyconcrete's own suite (tests/) is pytest-driven and builds the project inside
#    per-mode virtualenvs at run time (tests/conftest.py). There is nothing to precompile here;
#    mayhem/test.sh runs `pytest tests`. The Python deps + dev headers it needs are installed in
#    mayhem/Dockerfile.
