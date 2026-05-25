#!/usr/bin/env bash
# verify_split.sh — prove the split lost nothing.
#
# Compares the current full working-tree state (tracked + untracked) against the
# snapshot taken by gather_hunks.sh. Because committing hunks never changes file
# content on disk, a lossless split leaves the working tree byte-for-byte
# identical — so the two tree objects must match.
#
# Read-only: builds the comparison tree in a throwaway index; never touches the
# real index, the working tree, or history. Bash 3.2 compatible.
#
# Run this AFTER staging+committing all groups, but BEFORE you discard any
# don't-commit leftovers — discarding those is a deliberate change that will
# (correctly) make this diverge.
#
# Usage: ./verify_split.sh

set -u

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "ERROR: not inside a git repo" >&2; exit 1; }
GIT_DIR="$(git rev-parse --absolute-git-dir 2>/dev/null)"

SAVED="$GIT_DIR/commit-split-snapshot-tree"
[ -f "$SAVED" ] || { echo "ERROR: no snapshot found ($SAVED). Run gather_hunks.sh first." >&2; exit 2; }
WANT="$(cat "$SAVED")"

TMPIDX="$GIT_DIR/commit-split-verify.index"
rm -f "$TMPIDX"
GIT_INDEX_FILE="$TMPIDX" git add -A 2>/dev/null
GOT="$(GIT_INDEX_FILE="$TMPIDX" git write-tree 2>/dev/null)"
rm -f "$TMPIDX"

if [ "$WANT" = "$GOT" ]; then
  echo "IDENTICAL — the working tree matches the pre-split snapshot byte-for-byte. Split is lossless ✓"
  exit 0
fi

echo "DIVERGED ✗ — the working tree differs from the pre-split snapshot." >&2
echo "  pre-split tree: $WANT" >&2
echo "  current tree:   $GOT" >&2
echo "See what changed:  git diff $WANT" >&2
ORIG_HEAD_FILE="$GIT_DIR/commit-split-orig-head"
[ -f "$ORIG_HEAD_FILE" ] && echo "Start over:        git reset --mixed $(cat "$ORIG_HEAD_FILE")" >&2
exit 1
