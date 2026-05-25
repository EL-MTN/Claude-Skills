---
name: commit-split
description: Groups a sprawling working tree into a sequence of focused, logically-coherent commits — inferring which hunks form each change, ordering them so each commit stands on its own, and flagging hunks that shouldn't be committed at all (debug prints, secrets, conflict markers). Use when the user has mixed several unrelated changes together and wants to commit them cleanly: "split my changes into commits", "untangle my working tree", "break this into logical commits", "clean up before I open a PR", "I made a bunch of unrelated edits", "commit-split". Distinct from what-was-i-doing (which reconstructs in-progress work to resume it) — this acts on a finished-but-tangled tree to produce clean history. It stages and commits, but only after you confirm the plan, and is fully reversible.
---

# commit-split

Turns one tangled working tree into an ordered sequence of focused commits. You scaffolded a feature, fixed an unrelated bug you noticed, renamed a thing across six files, and left two debug prints in — all uncommitted. This skill infers the logical groups, proposes a commit order, names each one, and (on your go-ahead) realizes the split safely.

## The load-bearing rule

**The plan must add the map, not restate `git status`.** `git status` already lists changed files; `git diff` already shows the hunks flat. The value here is the inference on top: *which hunks form one logical change, in what order they must land, and which hunks belong in no commit at all.*

A proposed commit is only worth more than `git add -p` if it's a coherent unit — something a reviewer could read and a message could describe **without the word "and."** If a group's message needs "and," it's probably two groups. If a group is just "the remaining files," you haven't inferred anything — merge it or split it.

See `references/clustering-signals.md` for the grouping taxonomy, the don't-commit detector, and ordering rules.

## Two hard constraints

1. **Lossless and reversible.** The sum of the proposed commits (plus anything deliberately left unstaged) must equal the original working tree, byte for byte — verify this with the reconstruction check before declaring done. Never run a tree-destroying op (`reset --hard`, `checkout -- .`, `clean`). The entire split is one command from undone (`git reset --mixed <orig-head>`), and the gather script records that SHA up front.

2. **Confident-or-silent on separation.** If two intents are genuinely tangled in the same hunk, or two groups are mutually dependent, **say so** — don't propose commits that don't actually separate the changes. A fake-clean split that lumps a bugfix into a feature commit is worse than admitting "these two can't be cleanly separated; here's the best I can do." Same discipline as `verify-change`'s falsifiable intent: every group is a claim the user can reject at a glance.

## Workflow

### 1. Gather hunks

Run `scripts/gather_hunks.sh` from anywhere in the repo. Read-only with respect to your changes — it stages nothing and never touches the working tree. It records the original HEAD and a baseline diff (under `.git/`, untracked) for the later lossless check, then emits: a hunk index, the full diff (for building group patches), untracked files, recent commit subjects (for message style), a cheap don't-commit scan, and guards for mid-operation state and pre-existing staged content.

### 2. Handle the trivial cases first

Before planning a split, check the gather output for these — and stop early if they apply:

- **Clean tree** → nothing to split. Say so.
- **Git operation in progress** (rebase/merge/cherry-pick) → **do not split.** Staging hunks mid-operation corrupts it. Tell the user to finish or abort first.
- **One coherent change** → don't fabricate a multi-commit split to justify the skill. Say "this is already one logical commit," propose a message, and offer to just commit it.
- **Index already has staged content** → surface it. Pre-staging is itself an intent signal (the user may have started grouping by hand). Ask whether to fold it in or reset, and note that the full-undo command unstages it too.

### 3. Cluster into a plan

Load `references/clustering-signals.md`. Produce three things:

- **Ordered commit groups** — each a coherent unit, in dependency order (nothing references something defined in a later commit). Cite which files/hunks belong to each and the shared intent that binds them.
- **A don't-commit bucket** — hunks that shouldn't land in any commit (debug prints, `.only` focused tests, secrets, leftover `TODO: remove` scaffolding, conflict markers). Heuristic; flag, don't auto-drop.
- **A can't-separate note** — any entangled hunks, stated honestly (constraint #2).

### 4. Confirmation pause (mandatory)

Surface the plan (format below) and pause. The user can merge groups, split one further, reorder, drop a group, or move a hunk to the don't-commit bucket. Default-accept on "ok" / "yes" / "lgtm" / silence-then-go-ahead. Apply corrections and re-show only what changed. **Never stage or commit before this confirmation** — this skill writes to history, so the pause is non-negotiable, exactly as in `verify-change`.

### 5. Execute the plan

Load `references/execution.md`. Per group, in order:

- **File-level group (preferred, robust):** if no single file is split across groups, stage with `git add -- <paths>` and commit with the approved message.
- **Hunk-level group (a file's hunks span groups):** slice that group's hunks from a *fresh* `git diff` into a patch, validate-and-stage it with `scripts/apply_group.sh`, then commit. Always re-slice from the current `git diff` before each group so line offsets match the current index.

Commit messages match the repo's recent style (gather reports it). If a commit hook fails, the commit aborts with the group still staged — report it and let the user decide; only pass `--no-verify` if they ask.

### 6. Verify lossless and report

Run `scripts/verify_split.sh` — it compares a tree of the current full working state to the pre-split snapshot, so it's robust to new files becoming committed (a plain `git diff` is not). Do this *before* discarding any don't-commit leftovers (discarding them is a deliberate change that would correctly report DIVERGED). Then report:
- the commits created, in order;
- the don't-commit bucket, still sitting unstaged in the working tree, with what to do with it;
- the one-line full undo (`git reset --mixed <orig-head>`) in case the user wants to start over.

If `verify_split.sh` reports **DIVERGED**, something was dropped or altered — say so loudly and recommend the undo. Do not report success.

## Render (the plan, step 4)

```
# Commit plan — <repo>, <N> logical changes in the working tree

## Proposed commits (in order)
1. **<commit message>**  ·  <files / hunk IDs>
   One commit because: <the shared intent>
2. **<commit message>**  ·  <files / hunk IDs>
   One commit because: <…>  (after #1: depends on <what>)

## Don't commit — left in the working tree        ← omit if empty
- <file:line> — <debug print / secret / conflict marker / …>

## Can't cleanly separate                          ← omit if none
- <which hunks are tangled, and why>

Reply "ok" to apply in this order, or adjust (merge 1+2, drop 3, reorder…).
```

For the one-coherent-change case, collapse to a single line: "This is already one logical commit — suggested message: `<…>`. Want me to commit it?"

## Failure modes to resist

- **Restating `git status`.** "Commit 1: the changes in `auth/`" is not a plan. "Commit 1: fail fast on 4xx instead of retrying (`auth/refresh.py` hunks H2–H3)" is. If a group line doesn't name the intent, it adds nothing.
- **Faking a clean split.** Don't bury an unrelated bugfix inside the feature commit just to make the buckets tidy. Tangled means tangled — say it.
- **Over-splitting.** Twelve one-line commits is as unreviewable as one mega-commit. Group at the granularity a reviewer wants: the smallest change that's still independently meaningful.
- **Committing the debug prints.** The don't-commit scan exists because leftover `console.log`/secrets/`.only` are the most common thing that shouldn't ship. Surface them every time.
- **Staging before confirmation.** The plan is a proposal. Writing to the index or history before the user says "ok" is the cardinal sin here.
- **Declaring done without the lossless check.** A split that silently dropped a hunk is the worst outcome. Always reconstruct-verify.

## Reference files (load on demand)

| Reference | Load when |
|---|---|
| `references/clustering-signals.md` | Building the plan (step 3): grouping taxonomy, don't-commit detector, ordering. |
| `references/execution.md` | Realizing the split (step 5): patch construction, safe staging, undo, lossless check. |

## Scripts

| Script | Purpose |
|---|---|
| `scripts/gather_hunks.sh` | Step 1. Hunk inventory + baseline snapshot + don't-commit scan. Stages nothing. |
| `scripts/apply_group.sh` | Step 5. Validate (`--check`) then stage one group's patch onto the index. Never commits. |
| `scripts/verify_split.sh` | Step 6. Tree-hash check that the split lost nothing. Read-only. |

## Done criteria

- Each created commit is a coherent unit with a message that needs no "and."
- The don't-commit bucket was surfaced and left out of history.
- The reconstruction check is byte-identical — the split lost nothing.
- The user has the one-line full-undo command.
