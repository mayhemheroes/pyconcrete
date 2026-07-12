#!/usr/bin/env bash
#
# mayhem/test.sh — RUN pyconcrete's own upstream test suite (tests/, pytest).
#
# The suite is fully behavioral: it builds pyconcrete into per-mode virtualenvs (exe/lib/cli),
# encrypts/decrypts real modules & .pyz archives, imports encrypted zips, and asserts the
# decrypted program's OUTPUT (see tests/conftest.py + tests/test_*.py). A PATCH that neuters the
# program to exit(0) makes these assertions fail — so this is not reward-hackable.
#
# The venvs build pyconcrete from source via meson-python at collection time (upstream's design;
# we don't precompile it in build.sh). CFLAGS downgrades two default-error diagnostics
# (-Wreturn-mismatch etc.) that upstream's C predates — modern clang/gcc reject them as errors;
# this only relaxes the diagnostic, it does not change behavior. Python dev headers + the suite's
# Python deps are installed by mayhem/Dockerfile.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

export CFLAGS="${CFLAGS:-} -Wno-error=return-mismatch -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
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

JUNIT="${CTRF_REPORT:-$SRC/ctrf-report.json}.junit.xml"
rm -f "$JUNIT"

# RUN the suite (do NOT build the harness here). pytest builds the per-mode venvs itself.
python3 -m pytest tests -q -p no:cacheprovider --junitxml="$JUNIT"
pytest_rc=$?

if [ ! -s "$JUNIT" ]; then
  echo "test.sh: pytest produced no JUnit report (collection/build failure, rc=$pytest_rc)" >&2
  emit_ctrf "pytest" 0 1 0
  exit 1
fi

# Map JUnit -> CTRF counts. errors (fixture/build failures) count as failed.
read -r TESTS FAILURES ERRORS SKIPPED <<EOF
$(python3 - "$JUNIT" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
suites = [root] if root.tag == "testsuite" else root.findall("testsuite")
t=f=e=s=0
for su in suites:
    t += int(su.get("tests", 0)); f += int(su.get("failures", 0))
    e += int(su.get("errors", 0)); s += int(su.get("skipped", 0))
print(t, f, e, s)
PY
)
EOF

FAILED=$(( FAILURES + ERRORS ))
PASSED=$(( TESTS - FAILED - SKIPPED ))
[ "$PASSED" -lt 0 ] && PASSED=0

emit_ctrf "pytest" "$PASSED" "$FAILED" "$SKIPPED"
