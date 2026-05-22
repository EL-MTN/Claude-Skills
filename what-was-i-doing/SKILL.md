---
name: what-was-i-doing
description: Reconstructs what you were in the middle of doing in a repo — the goal, where you stopped, and (only when clear) the safe next step — from git state: uncommitted diff, branch name, recent commits, stashes, and which files you touched last. Use when the user returns to their own in-progress work and asks "what was I doing", "where did I leave off", "pick up where I left off", "what's my in-progress work", "help me get back into this", or context-switches back to a branch after time away. This is about resuming your own unfinished work — distinct from a code review (judging quality) or a PR digest (recapping others' shipped work).
---

# what-was-i-doing

Reconstructs an in-progress task from git artifacts so you can resume after a context switch. The deliverable is **inference**, not a status dump: the goal you were pursuing, the exact point where the thread was cut, and — when the signals are clear — the single next action.

## The load-bearing rule

**Every section must add inference you couldn't get from `git status` alone, and every inference must cite its evidence.**

`git status` already lists modified files. The value here is: *what were you trying to do, and where did you stop?* If a line just restates which files changed, cut it. If you state "you were doing X," follow it with the signals that imply X — so the user can reject a wrong guess at a glance (same falsifiable-claim discipline as `verify-change`).

If the working tree is too scattered to reconstruct a single intent, **say so** ("changes span three unrelated areas — no single thread to resume") rather than padding with a file list.

## Two hard constraints

1. **Next step is confident-or-silent.** Only emit a "Next step" when the signals point to one obvious action. If multiple changes are in flight, or there's no clear incomplete edge, OMIT the section — optionally noting "next step isn't clear; the changes span X, Y, Z." Never guess a next step to fill the template. A confidently-wrong next step is worse than none.

2. **Never lose parked work.** Forgotten stashes, other branches with uncommitted-looking divergence, and unstaged changes that could be clobbered by a checkout — these always surface in Safety notes, even when the main reconstruction is about the current branch.

## Workflow

### 1. Gather signals

Run `scripts/gather_signals.sh` from the repo root. It collects: current branch, the gap since last activity, `git status`, the unstaged + staged diff, commits since the branch diverged from main, stash list, the most-recently-modified changed files, other recently-touched branches, and ahead/behind vs. main. All read-only.

### 2. Detect the gap → set verbosity

The script reports time since last activity (max of last-commit time and most-recent working-tree file mtime).

- **Recent (< ~4 hours):** terse mode. One or two lines — "You're mid-edit in `auth/refresh.py` (`refresh_token` stub), last touched 40 min ago." The user just stepped away; they need a pointer, not a reconstruction.
- **A while (≥ ~4 hours, or ≥ 1 day):** full mode. The sections below.

Don't over-produce for a coffee-break return.

### 3. Reconstruct the goal

Infer what the user was building from: the branch name, the commit subjects since divergence, and the *shape* of the uncommitted diff (which directories/files, what kind of change). State it as one sentence, then cite the evidence.

> "You were adding OAuth refresh-token support to the auth module.
> Evidence: branch `feature/oauth-refresh`, last 3 commits, all uncommitted changes under `auth/`."

If the branch is `main`/`master` and there's no clear feature arc, lean harder on the diff shape and recent commits. If even that is ambiguous, say the goal is unclear and describe what you can see.

### 4. Find the stopping point

This is the highest-value, hardest part. Read the actual changed files (not just the diff) to locate where the thread was cut. Load `references/stopping-point-detection.md` for the catalog of signals — stub bodies, a failing new test, added-but-unused imports, syntax/type errors mid-edit, the most-recently-touched file, new signatures with no callers, leftover conflict markers.

Report the 1–4 strongest stopping-point signals with `file:line` and what each implies. Rank by recency (most-recent mtime is likely where your cursor was) and by fit with the reconstructed goal.

### 5. Next step — only if confident

Apply hard constraint #1. If one action clearly follows from the goal + stopping point, state it in one line. Otherwise omit the section (optionally one line on why it's unclear).

### 6. Safety notes

Always include, per hard constraint #2:
- Uncommitted/unstaged file count + how long since last activity.
- Forgotten stashes (with age and message) — flag any older than the current work as "possibly forgotten."
- Other branches touched recently that have their own in-flight look.
- Ahead/behind vs. main — warn if a rebase/merge is likely to conflict.

### 7. Render

```
# Where you left off — <repo>, branch <name>

## The goal (reconstructed)
<one sentence> 
Evidence: <signals>

## Where you stopped
- <file:line> — <what's incomplete and what it implies>
- ...

## Next step          ← omit entirely if not confident
<one concrete action>

## Safety notes
- <uncommitted state>
- <stashes>
- <other branches / divergence>
```

Terse mode collapses this to 1–2 lines (a pointer to the cursor + any urgent safety flag).

## Failure modes to resist

- **Restating `git status`.** "3 files modified in auth/" is not a finding. "You wrote the test but not the implementation" is. If a section doesn't add inference, cut it.
- **Guessing a next step to fill the template.** Confident-or-silent. A wrong "next step" sends the user down the wrong path on re-entry — the worst possible failure for this skill.
- **Uncited inferences.** "You were refactoring auth" with no evidence is unfalsifiable and untrustworthy. Always show the signals.
- **Losing a stash.** If there's a stash and you don't mention it, the user may never find it. Surface every one.
- **Over-producing on a quick return.** If they stepped away 15 minutes ago, don't write four sections. Re-orient and stop.
