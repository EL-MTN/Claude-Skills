#!/usr/bin/env bash
# collect_change_context.sh
#
# Step 1 of the verify-change skill: gather everything the MAIN AGENT needs
# to draft falsifiable intent bullets. Output is consumed by the main agent
# only — never passed across the independence boundary to the test-author.
#
# Usage: ./collect_change_context.sh [base_ref]
#   base_ref defaults to HEAD~1
#
# Output: a single markdown document on stdout.

set -euo pipefail

BASE_REF="${1:-HEAD~1}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || { echo "ERROR: not inside a git repo" >&2; exit 1; })"
cd "$REPO_ROOT"

echo "# Change context"
echo
echo "Repo root: \`$REPO_ROOT\`"
echo "Base ref:  \`$BASE_REF\`"
echo "Current ref: \`$(git rev-parse --short HEAD)\` ($(git rev-parse --abbrev-ref HEAD))"
echo

# --- Working tree status ---
echo "## Working tree status"
echo
echo '```'
git status --short --branch || true
echo '```'
echo

# --- Unstaged + staged diff ---
echo "## Unstaged + staged diff (vs HEAD)"
echo
echo '```diff'
git diff HEAD 2>/dev/null || true
echo '```'
echo

# --- HEAD vs base_ref diff ---
echo "## Diff: $BASE_REF → HEAD"
echo
echo '```diff'
if git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  git diff "$BASE_REF"..HEAD
else
  echo "(base ref $BASE_REF not found — likely a shallow clone or first commit)"
fi
echo '```'
echo

# --- Diff stat for shape ---
echo "## Diff stat ($BASE_REF → HEAD + working tree)"
echo
echo '```'
git diff "$BASE_REF" --stat 2>/dev/null || git diff --stat
echo '```'
echo

# --- Recent commits ---
echo "## Recent commits (last 10)"
echo
echo '```'
git log -n 10 --oneline --decorate
echo '```'
echo

# --- Issue references found in commit messages and branch name ---
echo "## Issue / ticket references"
echo
BRANCH_NAME="$(git rev-parse --abbrev-ref HEAD)"
RECENT_MSGS="$(git log -n 10 --format=%B 2>/dev/null || true)"
ALL_TEXT="$BRANCH_NAME"$'\n'"$RECENT_MSGS"

# Common ticket patterns: #123, GH-123, JIRA-456, PROJ-789, fixes/closes/resolves keywords
ISSUE_REFS="$(echo "$ALL_TEXT" | grep -oE '(#[0-9]+|[A-Z][A-Z0-9]+-[0-9]+|(closes?|fixes?|resolves?)[[:space:]]+[A-Za-z0-9#/-]+)' | sort -u || true)"

if [[ -n "$ISSUE_REFS" ]]; then
  echo '```'
  echo "$ISSUE_REFS"
  echo '```'
else
  echo "_(none detected)_"
fi
echo

# --- Refactor heuristic signals (advisory for the main agent) ---
echo "## Refactor heuristic signals (advisory)"
echo
NEW_TEST_LINES="$(git diff "$BASE_REF" --stat -- '*test*' '*spec*' 2>/dev/null | tail -n1 | grep -oE '[0-9]+ insertion' || echo '0 insertion')"
TOTAL_FILES="$(git diff "$BASE_REF" --name-only 2>/dev/null | wc -l | tr -d ' ')"
NET_ADD="$(git diff "$BASE_REF" --shortstat 2>/dev/null | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)"
NET_DEL="$(git diff "$BASE_REF" --shortstat 2>/dev/null | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0)"

echo "- Files touched: $TOTAL_FILES"
echo "- Insertions: $NET_ADD  /  Deletions: $NET_DEL"
echo "- Test-file insertions: $NEW_TEST_LINES"
echo

# Match branch name and recent commit subjects against refactor keywords
REFACTOR_KEYWORDS='refactor|rename|extract|inline|cleanup|tidy|reorganize|reformat|reword|move'
RECENT_SUBJECTS="$(git log -n 10 --format=%s 2>/dev/null || true)"

REFACTOR_HITS=""
if echo "$BRANCH_NAME" | grep -iqE "$REFACTOR_KEYWORDS"; then
  REFACTOR_HITS+="- Branch name matches refactor keywords"$'\n'
fi
if echo "$RECENT_SUBJECTS" | grep -iqE "$REFACTOR_KEYWORDS"; then
  REFACTOR_HITS+="- Recent commit subjects match refactor keywords"$'\n'
fi
if [[ "$NEW_TEST_LINES" == "0 insertion" ]] || [[ -z "$NEW_TEST_LINES" ]]; then
  REFACTOR_HITS+="- No new test lines in diff"$'\n'
fi

if [[ -n "$REFACTOR_HITS" ]]; then
  echo "Potentially refactor-shaped:"
  echo
  echo "$REFACTOR_HITS"
  echo "_Apply heuristics in references/differential-mode.md before deciding._"
else
  echo "_No strong refactor signals detected._"
fi
echo

# --- Diff size sanity warning ---
DIFF_LINE_COUNT="$(git diff "$BASE_REF" HEAD 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$DIFF_LINE_COUNT" -gt 2000 ]]; then
  echo "## ⚠ Large diff warning"
  echo
  echo "Diff is $DIFF_LINE_COUNT lines. Intent extraction quality degrades on very large diffs."
  echo "Consider asking the user which subset of the change to verify."
  echo
fi
