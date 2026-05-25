# Execution — realizing the split safely

How to turn the confirmed plan into commits without losing or altering a single line. This skill writes to the index and to history, so every step here is reversible and the end state is verified.

## Two staging mechanisms — prefer the first

### File-level (robust, no patch surgery)
When a group consists of **whole files** that no other group touches, just stage the files and commit:

```sh
git add -- path/one.py path/two.py
git commit -m "fail fast on 4xx instead of retrying"
```

This covers most real splits — unrelated changes usually live in different files. No line numbers, no patch text, nothing to get wrong. Use it whenever the grouping is clean at the file boundary.

Untracked files are always file-level: `git add -- newfile.py`. (A large/generated untracked file is often its own commit, or a don't-commit.)

### Hunk-level (when one file's hunks span groups)
Only needed when a single file's hunks must go to different commits. Slice that group's hunks into a patch and apply it to the index:

1. **Re-slice from a *fresh* diff every time.** Build the patch from the current `git diff` (working tree vs index), not from the original gather output. After you stage group 1, the index changes, and only `git diff` reflects the correct line offsets for what's left. Slicing from stale text is the main cause of "patch does not apply."
2. **Keep the file headers.** A valid patch for a file needs its `diff --git a/… b/…`, the `index …` line, and the `--- a/…` / `+++ b/…` header, followed by the chosen `@@ … @@` hunk(s). Copy hunk bodies byte-exact (leading space / `+` / `-` preserved). End the file with a trailing newline.
3. **Validate, then stage** with the helper:

```sh
scripts/apply_group.sh --check group-2.patch   # dry-run: does it apply?
scripts/apply_group.sh group-2.patch           # apply to the index only
git commit -m "rename Session → Connection"
```

`apply_group.sh` runs `git apply --cached --check` first and refuses to touch the index if the patch doesn't apply cleanly. It stages only — it never commits, so the message stays human-reviewed.

### Line-level (entangled hunk)
When two intents share one hunk and you chose to split them (see `clustering-signals.md` → Entanglement): hand-edit the patch so each commit's patch contains only its lines, converting the other intent's `+`/`-` lines back to ` ` context (or dropping them) so the hunk still applies. Validate each with `--check`. This is fiddly — only do it when the lines are clearly separable; otherwise commit together and name both.

## The per-group loop

For each group, in the planned order:

1. Stage it (file-level `git add`, or hunk-level patch).
2. `git diff --cached --stat` — confirm exactly the intended change is staged, nothing more.
3. `git commit -m "<approved message>"`.
4. Move to the next group. (For hunk-level groups, re-slice from a fresh `git diff` first.)

If a **pre-commit hook fails**, the commit aborts and the group stays staged. Report the hook output and let the user fix it or decide; only use `git commit --no-verify` if they explicitly ask.

## Verifying the split lost nothing

Run the skill's helper after all commits:

```sh
scripts/verify_split.sh
```

It compares a tree object of the **current full working state** (tracked + untracked) to the snapshot `gather_hunks.sh` took before the split. Committing hunks never changes file content on disk, so a lossless split leaves the working tree byte-for-byte identical — the trees must match. A tree-hash comparison (not a text diff) is used on purpose: it's immune to the untracked→committed transition that would make a naive `git diff` baseline cry wolf on any split that adds a new file.

- **IDENTICAL** → the union of (new commits + leftover unstaged) reproduces the original tree exactly. Done.
- **DIVERGED** → a hunk was dropped or altered. Stop, report it, recommend the full undo. Do not claim success.

**Order matters:** run this *before* you discard any don't-commit leftovers (debug prints, secrets). Discarding those is a deliberate change to the working tree, so verifying afterward would (correctly) report DIVERGED. Verify lossless first, then discard.

## Undo

- **Full undo (start over):** `git reset --mixed <orig-head>` — drops the new commits and unstages everything, restoring the exact pre-split working tree. Nothing is lost because the changes were only ever staged/committed, never removed from disk.
  - Caveat: this also unstages anything that was staged *before* the split began. If gather reported pre-existing staged content, mention this.
- **Uncommit the last group only:** `git reset --soft HEAD~1` (keeps it staged) or `git reset HEAD~1` (unstages it too).
- **Unstage without committing:** `git restore --staged -- <paths>`.

## Never do these

These destroy working-tree content and violate the lossless constraint:
- `git reset --hard`
- `git checkout -- <path>` / `git restore --worktree` (without a source)
- `git clean`
- `git stash drop` / `git stash pop` on stashes you didn't create here

`git apply --cached` and the `reset` variants above only move things between working tree, index, and HEAD — they never delete the underlying changes.
