#!/usr/bin/env bash
# run_harness.sh
#
# Step 7 of the verify-change skill: run the generated verify.sh and stream
# results to the caller. Lightweight wrapper that ensures the harness is
# executable, isolates its working directory, and captures output for triage.
#
# Usage: ./run_harness.sh [verify_dir]
#   verify_dir defaults to .verify-change/ in the current repo root.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
VERIFY_DIR="${1:-$REPO_ROOT/.verify-change}"

if [[ ! -d "$VERIFY_DIR" ]]; then
  echo "ERROR: verify directory not found: $VERIFY_DIR" >&2
  echo "Run the skill end-to-end first, or pass the path explicitly." >&2
  exit 1
fi

HARNESS=""
for candidate in "$VERIFY_DIR/verify.sh" "$VERIFY_DIR/verify.bash" "$VERIFY_DIR/run.sh"; do
  if [[ -f "$candidate" ]]; then
    HARNESS="$candidate"
    break
  fi
done

if [[ -z "$HARNESS" ]]; then
  echo "ERROR: no harness entry point found in $VERIFY_DIR" >&2
  echo "Expected one of: verify.sh, verify.bash, run.sh" >&2
  exit 1
fi

# Ensure executable
chmod +x "$HARNESS" 2>/dev/null || true

# Independence boundary visibility: confirm AUDIT.md exists before running.
if [[ ! -f "$VERIFY_DIR/AUDIT.md" ]]; then
  echo "WARNING: $VERIFY_DIR/AUDIT.md is missing. The test-author subagent" >&2
  echo "did not produce its required self-audit. The independence boundary" >&2
  echo "cannot be verified. Proceeding anyway — review the test files manually." >&2
  echo >&2
fi

# Run with a captured log so triage has something concrete to work from.
LOG_FILE="$VERIFY_DIR/last_run.log"
echo "==== verify-change harness ===="
echo "Harness:  $HARNESS"
echo "Log:      $LOG_FILE"
echo "Started:  $(date -Iseconds 2>/dev/null || date)"
echo

# Use a temporary file so we can both tee to stdout and capture exit code.
set +e
"$HARNESS" 2>&1 | tee "$LOG_FILE"
EXIT_CODE="${PIPESTATUS[0]}"
set -e

echo
echo "==== verify-change result ===="
echo "Exit code: $EXIT_CODE"
echo "Finished:  $(date -Iseconds 2>/dev/null || date)"

exit "$EXIT_CODE"
