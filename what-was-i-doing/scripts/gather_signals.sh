#!/usr/bin/env bash
# gather_signals.sh
#
# Read-only collection of every git signal the what-was-i-doing skill needs to
# reconstruct in-progress work. Emits a single markdown report on stdout.
#
# Nothing here writes state: no checkout, no stash, no commit. Safe to run any
# time. Bash 3.2 compatible (macOS default).
#
# Usage: ./gather_signals.sh

set -u

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not inside a git repo" >&2; exit 1; }
cd "$REPO_ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

# Identify the main branch (prefer main, then master, then origin/HEAD).
MAIN_BRANCH=""
for cand in main master; do
  if git rev-parse --verify "$cand" >/dev/null 2>&1; then MAIN_BRANCH="$cand"; break; fi
done
if [ -z "$MAIN_BRANCH" ]; then
  MAIN_BRANCH="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
fi

# Portable mtime helper: epoch seconds for a file.
mtime_of() {
  if [ "$(uname -s)" = "Darwin" ]; then stat -f %m "$1" 2>/dev/null; else stat -c %Y "$1" 2>/dev/null; fi
}

# Flat list of changed files. `git status --porcelain` collapses untracked
# content to its directory (e.g. `?? newdir/`); expand those to real files so
# untracked work is never invisible. Cap dir expansion to avoid blowing up on a
# huge untracked tree (e.g. an un-ignored node_modules).
enumerate_changed_files() {
  git status --porcelain 2>/dev/null | sed 's/^...//' | sed 's/.* -> //' | while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    if [ -d "$entry" ]; then
      find "$entry" -type f 2>/dev/null | head -200
    elif [ -f "$entry" ]; then
      echo "$entry"
    fi
  done
}

NOW="$(date +%s)"

echo "# what-was-i-doing — signals"
echo
echo "Repo: \`$REPO_ROOT\`"
echo "Branch: \`$BRANCH\`  ·  Main: \`${MAIN_BRANCH:-unknown}\`"
echo

# ---------- Gap detection ----------
echo "## Gap since last activity"
echo
LAST_COMMIT_EPOCH="$(git log -1 --format=%ct 2>/dev/null)"
# Most-recent mtime among changed (tracked-modified + untracked) files.
NEWEST_WT_EPOCH=0
NEWEST_WT_FILE=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  m="$(mtime_of "$f")"
  [ -z "$m" ] && continue
  if [ "$m" -gt "$NEWEST_WT_EPOCH" ]; then NEWEST_WT_EPOCH="$m"; NEWEST_WT_FILE="$f"; fi
done < <(enumerate_changed_files)

LAST_ACTIVITY="$LAST_COMMIT_EPOCH"
[ -z "$LAST_ACTIVITY" ] && LAST_ACTIVITY=0
if [ "$NEWEST_WT_EPOCH" -gt "$LAST_ACTIVITY" ]; then LAST_ACTIVITY="$NEWEST_WT_EPOCH"; fi

if [ "$LAST_ACTIVITY" -gt 0 ]; then
  DELTA=$(( NOW - LAST_ACTIVITY ))
  HOURS=$(( DELTA / 3600 ))
  DAYS=$(( DELTA / 86400 ))
  if [ "$DELTA" -lt 14400 ]; then
    BUCKET="recent (< ~4h) → TERSE mode"
  else
    BUCKET="a while (≥ ~4h) → FULL mode"
  fi
  echo "- Last activity: ~${HOURS}h ago (${DAYS}d). Bucket: **$BUCKET**"
  [ -n "$NEWEST_WT_FILE" ] && echo "- Most recently modified changed file: \`$NEWEST_WT_FILE\`"
else
  echo "- No commits and no working-tree changes detected."
fi
echo

# ---------- Working tree status ----------
echo "## git status"
echo
echo '```'
git status --short --branch 2>/dev/null
echo '```'
echo

# ---------- Changed files by mtime (cursor hint) ----------
echo "## Changed files, newest first (cursor hint)"
echo
echo '```'
# Build "epoch<TAB>path", sort desc, strip epoch. Bash 3.2 friendly.
TMP_LIST=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  m="$(mtime_of "$f")"
  [ -z "$m" ] && continue
  TMP_LIST="$TMP_LIST$m	$f
"
done < <(enumerate_changed_files)
if [ -n "$TMP_LIST" ]; then
  printf "%s" "$TMP_LIST" | sort -rn | head -10 | while IFS=$'\t' read -r ep path; do
    [ -z "$path" ] && continue
    if [ "$(uname -s)" = "Darwin" ]; then human="$(date -r "$ep" '+%Y-%m-%d %H:%M' 2>/dev/null)"; else human="$(date -d "@$ep" '+%Y-%m-%d %H:%M' 2>/dev/null)"; fi
    echo "$human  $path"
  done
else
  echo "(no changed files)"
fi
echo '```'
echo

# ---------- Uncommitted diff ----------
echo "## Uncommitted changes"
echo
echo "_\`git diff\` covers TRACKED changes only. Untracked files are shown in their own block below — that's frequently where the real in-progress work lives, so don't stop at the tracked diff._"
echo
echo "### Tracked (modified + staged) diff — stat"
echo '```'
git diff HEAD --stat 2>/dev/null | tail -40
echo '```'
echo
echo "### Tracked diff — full (first 300 lines)"
echo '```diff'
git diff HEAD 2>/dev/null | head -300
echo '```'
echo
echo "### Untracked file contents (first 250 lines total)"
echo
UNTRACKED="$(git ls-files --others --exclude-standard 2>/dev/null)"
if [ -n "$UNTRACKED" ]; then
  echo '```diff'
  printf "%s\n" "$UNTRACKED" | head -50 | while IFS= read -r uf; do
    [ -f "$uf" ] || continue
    # Skip binaries / build artifacts (pyc, images, .o) — "Binary files differ"
    # teaches nothing about in-progress work. grep -I treats binary as no-match.
    grep -Iq . "$uf" 2>/dev/null || { echo "(skipped non-text file: $uf)"; continue; }
    # --no-index renders the file as an all-addition diff without touching the index (read-only).
    git diff --no-index /dev/null "$uf" 2>/dev/null
  done | head -250
  echo '```'
else
  echo "_(no untracked files)_"
fi
echo

# ---------- Commits since divergence from main ----------
echo "## Commits on this branch since it diverged from \`${MAIN_BRANCH:-main}\`"
echo
echo '```'
if [ -n "$MAIN_BRANCH" ] && [ "$BRANCH" != "$MAIN_BRANCH" ]; then
  BASE="$(git merge-base HEAD "$MAIN_BRANCH" 2>/dev/null)"
  if [ -n "$BASE" ]; then
    git log "$BASE"..HEAD --oneline 2>/dev/null
  else
    git log -10 --oneline 2>/dev/null
  fi
else
  echo "(on $MAIN_BRANCH or main unknown — showing last 10 commits)"
  git log -10 --oneline 2>/dev/null
fi
echo '```'
echo

# ---------- Ahead / behind main ----------
if [ -n "$MAIN_BRANCH" ] && [ "$BRANCH" != "$MAIN_BRANCH" ]; then
  echo "## Divergence vs. \`$MAIN_BRANCH\`"
  echo
  COUNTS="$(git rev-list --left-right --count "$MAIN_BRANCH"...HEAD 2>/dev/null)"
  if [ -n "$COUNTS" ]; then
    BEHIND="$(echo "$COUNTS" | awk '{print $1}')"
    AHEAD="$(echo "$COUNTS" | awk '{print $2}')"
    echo "- Ahead $AHEAD · behind $BEHIND (vs. $MAIN_BRANCH)"
    [ "${BEHIND:-0}" -gt 0 ] && echo "- ⚠ Behind by $BEHIND — a rebase/merge may conflict."
  fi
  echo
fi

# ---------- Stashes ----------
echo "## Stashes (possibly forgotten work)"
echo
STASHES="$(git stash list 2>/dev/null)"
if [ -n "$STASHES" ]; then
  echo '```'
  echo "$STASHES"
  echo '```'
  echo "_Surface every one of these in Safety notes — they're easy to lose._"
else
  echo "_(none)_"
fi
echo

# ---------- Other recently-touched branches ----------
echo "## Other branches touched recently (top 8 by last commit)"
echo
echo '```'
git for-each-ref --sort=-committerdate refs/heads/ --format='%(committerdate:relative)%09%(refname:short)' 2>/dev/null | head -8
echo '```'
echo

# ---------- Mid-operation state ----------
GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)"
INFLIGHT=""
[ -d "$GIT_DIR/rebase-merge" ] && INFLIGHT="$INFLIGHT rebase-in-progress"
[ -d "$GIT_DIR/rebase-apply" ] && INFLIGHT="$INFLIGHT rebase/am-in-progress"
[ -f "$GIT_DIR/MERGE_HEAD" ] && INFLIGHT="$INFLIGHT merge-in-progress"
[ -f "$GIT_DIR/CHERRY_PICK_HEAD" ] && INFLIGHT="$INFLIGHT cherry-pick-in-progress"
[ -f "$GIT_DIR/BISECT_LOG" ] && INFLIGHT="$INFLIGHT bisect-in-progress"
if [ -n "$INFLIGHT" ]; then
  echo "## ⚠ Git operation in progress"
  echo
  echo "-$INFLIGHT"
  echo
  echo "_This is a Safety note: the repo is mid-operation. Resuming work means finishing or aborting it first._"
  echo
fi
