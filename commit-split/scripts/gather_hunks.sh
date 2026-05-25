#!/usr/bin/env bash
# gather_hunks.sh
#
# Read the working tree at hunk granularity so commit-split can group changes
# into logical commits. Emits a markdown report on stdout.
#
# It does NOT stage, commit, or modify the working tree. The only files it
# writes are a baseline snapshot used later to prove the split lost nothing:
#   <git-dir>/commit-split-baseline.diff   (the pre-split combined diff)
#   <git-dir>/commit-split-orig-head       (the pre-split HEAD sha)
# Both live inside the git dir and are never tracked. Bash 3.2 compatible.
#
# Usage: ./gather_hunks.sh

set -u

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not inside a git repo" >&2; exit 1; }
cd "$REPO_ROOT" || { echo "ERROR: cannot cd into repo root '$REPO_ROOT'" >&2; exit 1; }

GIT_DIR="$(git rev-parse --absolute-git-dir 2>/dev/null)"
ORIG_HEAD="$(git rev-parse HEAD 2>/dev/null)"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

echo "# commit-split — working-tree inventory"
echo
echo "Repo: \`$REPO_ROOT\`"
echo "Branch: \`$BRANCH\`  ·  HEAD: \`$ORIG_HEAD\`"
echo

# ---------- Mid-operation guard (stop before splitting) ----------
INFLIGHT=""
[ -d "$GIT_DIR/rebase-merge" ] && INFLIGHT="$INFLIGHT rebase-in-progress"
[ -d "$GIT_DIR/rebase-apply" ] && INFLIGHT="$INFLIGHT rebase/am-in-progress"
[ -f "$GIT_DIR/MERGE_HEAD" ] && INFLIGHT="$INFLIGHT merge-in-progress"
[ -f "$GIT_DIR/CHERRY_PICK_HEAD" ] && INFLIGHT="$INFLIGHT cherry-pick-in-progress"
[ -f "$GIT_DIR/BISECT_LOG" ] && INFLIGHT="$INFLIGHT bisect-in-progress"
if [ -n "$INFLIGHT" ]; then
  echo "## ⚠ Git operation in progress —$INFLIGHT"
  echo
  echo "_Do NOT split now. Finish or abort the in-progress operation first — staging hunks mid-operation corrupts it._"
  echo
fi

# ---------- Clean-tree short-circuit ----------
if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
  echo "## Nothing to split"
  echo
  echo "Working tree is clean — no changes to group into commits."
  exit 0
fi

# ---------- Pre-existing staged content ----------
if ! git diff --cached --quiet 2>/dev/null; then
  echo "## ⚠ Index already has staged content"
  echo
  echo "Some hunks are already staged — surface this before re-planning (it may be the user's own grouping). The full-undo command \`git reset --mixed\` will also unstage these."
  echo '```'
  git diff --cached --stat 2>/dev/null | tail -40
  echo '```'
  echo
fi

# ---------- Baseline + snapshot for the lossless check ----------
# Human-readable baseline (tracked changes) for reading the pre-split state.
git diff "$ORIG_HEAD" > "$GIT_DIR/commit-split-baseline.diff" 2>/dev/null
printf "%s\n" "$ORIG_HEAD" > "$GIT_DIR/commit-split-orig-head"
# Authoritative snapshot: a tree object of the FULL working state (tracked +
# untracked), built via a throwaway index so the real index is untouched. The
# lossless check compares this tree to the post-split tree — robust to untracked
# files becoming committed (a plain `git diff` baseline is not).
SNAP_IDX="$GIT_DIR/commit-split-snapshot.index"
rm -f "$SNAP_IDX"
GIT_INDEX_FILE="$SNAP_IDX" git add -A 2>/dev/null
SNAP_TREE="$(GIT_INDEX_FILE="$SNAP_IDX" git write-tree 2>/dev/null)"
rm -f "$SNAP_IDX"
printf "%s\n" "$SNAP_TREE" > "$GIT_DIR/commit-split-snapshot-tree"

echo "## Baseline (for the lossless check)"
echo
echo "- Original HEAD: \`$ORIG_HEAD\`"
echo "- Pre-split tree snapshot: \`$SNAP_TREE\` (full working state, tracked + untracked)"
echo "- Saved combined diff (for reading): \`$GIT_DIR/commit-split-baseline.diff\`"
echo "- Full undo at any time: \`git reset --mixed $ORIG_HEAD\` (restores this exact pre-split state)"
echo
echo "After the split — and BEFORE discarding any don't-commit leftovers — prove nothing was lost by running the skill's:"
echo '```'
echo "scripts/verify_split.sh   # compares the post-split tree to snapshot $SNAP_TREE"
echo '```'
echo

# ---------- Hunk index ----------
echo "## Hunk index"
echo
echo "_One row per hunk (ID · file · \`@@\` range). Plan groups by ID; build each group's patch from the full diff below._"
echo
echo '```'
git diff "$ORIG_HEAD" 2>/dev/null | awk '
  /^diff --git / { p=$0; sub(/^diff --git a\/.* b\//, "", p); file=p; next }
  /^@@ / { n++; printf "H%-3d %s\t%s\n", n, file, $0; next }
  END { if (n=="") print "(no tracked hunks — see untracked files below)" }
'
echo '```'
echo

# ---------- Don't-commit scan (added lines only) ----------
echo "## Possibly-don't-commit scan"
echo
echo "_Heuristic hints over added lines — confirm in context before dropping. These usually belong in no commit._"
echo
ADDED="$(git diff "$ORIG_HEAD" 2>/dev/null | grep -E '^\+' | grep -Ev '^\+\+\+')"
HITS=0
scan() {
  m="$(printf "%s\n" "$ADDED" | grep -E "$2" 2>/dev/null | head -8)"
  if [ -n "$m" ]; then
    HITS=1
    echo "- **$1:**"
    echo '```'
    printf "%s\n" "$m"
    echo '```'
  fi
}
scan "debug prints"     'console\.(log|debug)|[^a-zA-Z_]print\(|fmt\.Print|dbg!|System\.out\.print|var_dump|[^a-zA-Z_]puts '
scan "focused tests"    '\.only\(|fdescribe|[^a-zA-Z]fit\(|test\.only|it\.only'
scan "leftover markers" 'TODO|FIXME|XXX|HACK'
scan "conflict markers" '^\+(<<<<<<<|=======|>>>>>>>)'
scan "possible secrets" 'API_KEY|SECRET|PASSWORD|TOKEN|PRIVATE_KEY|AKIA[0-9A-Z]{16}'
[ "$HITS" -eq 0 ] && echo "_(no obvious red flags)_"
echo

# ---------- Recent commit subjects (message style) ----------
echo "## Recent commit subjects (match this style for messages)"
echo
echo '```'
git log -8 --format='%s' 2>/dev/null
echo '```'
echo

# ---------- Full tracked diff (build group patches from this) ----------
echo "## Full tracked diff (build each group's patch from this)"
echo
DIFF_LINES="$(git diff "$ORIG_HEAD" 2>/dev/null | wc -l | tr -d ' ')"
echo '```diff'
git diff "$ORIG_HEAD" 2>/dev/null | head -800
echo '```'
if [ "${DIFF_LINES:-0}" -gt 800 ]; then
  echo
  echo "_Diff truncated at 800 lines (total $DIFF_LINES). Run \`git diff $ORIG_HEAD -- <path>\` per file for the rest._"
fi
echo

# ---------- Untracked files (added wholesale per group) ----------
echo "## Untracked files (each is added wholesale to one group)"
echo
UNTRACKED="$(git ls-files --others --exclude-standard 2>/dev/null)"
if [ -n "$UNTRACKED" ]; then
  echo '```'
  printf "%s\n" "$UNTRACKED" | head -50
  echo '```'
  echo
  echo "_Stage these with \`git add -- <path>\` (no patch surgery). Large/generated ones are often their own commit — or a don't-commit._"
else
  echo "_(none)_"
fi
echo
