#!/usr/bin/env bash
# differential_run.sh
#
# Refactor-branch helper: run a command at HEAD and at a base ref, normalize
# both outputs, diff them, and report. Used by differential mode (see
# references/differential-mode.md).
#
# Uses `git worktree` for the base ref to avoid the stash/checkout dance and
# the pycache-conflict problems that come with it. The user's working tree is
# never touched.
#
# Usage:
#   ./differential_run.sh <base_ref> -- <command> [args...]
#
# Example:
#   ./differential_run.sh HEAD~1 -- ./bin/mytool --help
#
# Output: normalized diff on stdout. Exit 0 if outputs match (and exit codes
# match), 1 if they differ, 2 on usage / setup error.

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <base_ref> -- <command> [args...]" >&2
  exit 2
fi

BASE_REF="$1"
shift

if [[ "$1" != "--" ]]; then
  echo "ERROR: expected '--' between base_ref and command" >&2
  exit 2
fi
shift

CMD=("$@")

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Verify the base ref exists.
if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  echo "ERROR: base ref '$BASE_REF' not found" >&2
  exit 2
fi

# --- Create a worktree at the base ref ---
# We use a uniquely-named directory under /tmp so the user's working tree is
# untouched, and the worktree gets removed on exit even if the script fails.
WORKTREE_DIR="$(mktemp -d -t verify-change-worktree.XXXXXX)"
WORKTREE_BRANCH="verify-change-diff-$$"

# shellcheck disable=SC2329  # invoked indirectly via `trap cleanup EXIT` below
cleanup() {
  set +e
  # Remove worktree (handles both clean and dirty worktree states).
  if [[ -d "$WORKTREE_DIR" ]]; then
    git worktree remove --force "$WORKTREE_DIR" 2>/dev/null
    # Belt-and-suspenders: physically remove the dir if worktree command left it.
    rm -rf "$WORKTREE_DIR" 2>/dev/null
  fi
  # Prune any administrative state for the temp branch.
  git branch -D "$WORKTREE_BRANCH" 2>/dev/null
  git worktree prune 2>/dev/null
  set -e
}
trap cleanup EXIT

echo "[differential] Creating worktree at $BASE_REF in $WORKTREE_DIR..." >&2
if ! git worktree add -q --detach "$WORKTREE_DIR" "$BASE_REF" 2>/dev/null; then
  # Some git versions need a branch arg even with --detach; try without -q for the error.
  if ! git worktree add --detach "$WORKTREE_DIR" "$BASE_REF"; then
    echo "ERROR: git worktree add failed" >&2
    exit 2
  fi
fi

# --- Output capture ---
HEAD_OUT="$(mktemp -t verify-change-head.XXXXXX)"
BASE_OUT="$(mktemp -t verify-change-base.XXXXXX)"

# Run at HEAD (the user's current working tree) — read-only, no side effects on the user.
echo "[differential] Running at HEAD: ${CMD[*]}" >&2
set +e
"${CMD[@]}" >"$HEAD_OUT" 2>&1
HEAD_EXIT=$?
set -e
echo "[differential]   exit=$HEAD_EXIT, $(wc -l <"$HEAD_OUT" | tr -d ' ') lines" >&2

# Run the same command in the worktree (which is checked out at the base ref).
echo "[differential] Running at $BASE_REF (in worktree): ${CMD[*]}" >&2
set +e
( cd "$WORKTREE_DIR" && "${CMD[@]}" ) >"$BASE_OUT" 2>&1
BASE_EXIT=$?
set -e
echo "[differential]   exit=$BASE_EXIT, $(wc -l <"$BASE_OUT" | tr -d ' ') lines" >&2

# --- Normalization ---
# Strip volatile/path fields uniformly from both outputs. State these in any
# generated test's docstring — hidden normalization is how a real regression
# gets papered over.
normalize() {
  local in="$1"
  local repo_esc="${REPO_ROOT//\//\\/}"
  local home_esc="${HOME//\//\\/}"
  local wt_esc="${WORKTREE_DIR//\//\\/}"
  sed -E \
    -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?/<TS>/g' \
    -e "s/${wt_esc}/<REPO>/g" \
    -e "s/${repo_esc}/<REPO>/g" \
    -e "s/${home_esc}/~/g" \
    -e 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<UUID>/gI' \
    -e 's/localhost:[0-9]+/localhost:<PORT>/g' \
    -e 's/127\.0\.0\.1:[0-9]+/127.0.0.1:<PORT>/g' \
    -e 's/pid=[0-9]+/pid=<PID>/g' \
    "$in"
}

HEAD_NORM="$(mktemp -t verify-change-head-norm.XXXXXX)"
BASE_NORM="$(mktemp -t verify-change-base-norm.XXXXXX)"
normalize "$HEAD_OUT" > "$HEAD_NORM"
normalize "$BASE_OUT" > "$BASE_NORM"

# --- Diff and report ---
echo
echo "==== Differential result ===="
echo "Command:    ${CMD[*]}"
echo "HEAD:       exit=$HEAD_EXIT"
echo "$BASE_REF:  exit=$BASE_EXIT"
echo

DIFF_OUT="$(diff -u "$BASE_NORM" "$HEAD_NORM" || true)"
RESULT=0
if [[ -z "$DIFF_OUT" ]] && [[ "$HEAD_EXIT" == "$BASE_EXIT" ]]; then
  echo "PASS — outputs identical after normalization, exit codes match."
else
  if [[ "$HEAD_EXIT" != "$BASE_EXIT" ]]; then
    echo "DIFF — exit codes differ: $BASE_REF=$BASE_EXIT, HEAD=$HEAD_EXIT"
  fi
  if [[ -n "$DIFF_OUT" ]]; then
    echo "DIFF — normalized outputs:"
    echo "$DIFF_OUT"
  fi
  RESULT=1
fi

rm -f "$HEAD_OUT" "$BASE_OUT" "$HEAD_NORM" "$BASE_NORM"
exit "$RESULT"
