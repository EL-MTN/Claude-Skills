#!/usr/bin/env bash
# apply_group.sh — stage ONE logical group onto the index, safely.
#
# Validates a group patch with `git apply --cached --check` before applying it,
# so a malformed or non-applying patch fails loudly without touching the index.
# It only stages — it never commits. The agent commits the staged group with a
# message it composed and the user approved.
#
# It does not modify the working tree: `git apply --cached` writes the index
# only. Full undo of an entire split remains `git reset --mixed <orig-head>`.
# Bash 3.2 compatible.
#
# Usage:
#   ./apply_group.sh <group.patch>            # validate, then stage
#   ./apply_group.sh --check <group.patch>    # validate only, stage nothing

set -u

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then CHECK_ONLY=1; shift; fi

PATCH="${1:-}"
[ -n "$PATCH" ] || { echo "ERROR: usage: apply_group.sh [--check] <group.patch>" >&2; exit 2; }
[ -f "$PATCH" ] || { echo "ERROR: patch file not found: $PATCH" >&2; exit 2; }

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "ERROR: not inside a git repo" >&2; exit 1; }

ERRFILE="$(mktemp 2>/dev/null || echo "/tmp/commit-split-apply.$$")"
trap 'rm -f "$ERRFILE"' EXIT

# Validate first. --whitespace=nowarn keeps the report about applicability,
# not whitespace style.
if ! git apply --cached --check --whitespace=nowarn "$PATCH" 2>"$ERRFILE"; then
  echo "✗ Patch does NOT apply cleanly to the index — nothing staged." >&2
  cat "$ERRFILE" >&2
  echo "Likely causes: hunks overlap a group already staged, or the patch text drifted." >&2
  echo "Fix: rebuild this group's patch from a FRESH \`git diff\` (offsets shift after each stage)." >&2
  exit 1
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "✓ Patch applies cleanly (validation only — nothing staged)."
  exit 0
fi

git apply --cached --whitespace=nowarn "$PATCH" || { echo "ERROR: apply failed after passing --check (unexpected)" >&2; exit 1; }

echo "✓ Group staged. Now staged for commit:"
echo
git diff --cached --stat
echo
echo "Confirm it's exactly this group, then:  git commit -m \"<approved message>\""
echo "For the next group, re-slice from a fresh \`git diff\` before building its patch."
