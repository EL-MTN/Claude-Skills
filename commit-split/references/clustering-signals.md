# Clustering signals — turning hunks into commits

The hard, valuable part of `commit-split`: deciding which hunks belong together. `git diff` shows the hunks; this decides the *groups*. Read the actual changed lines, not just file names — a single file routinely holds two unrelated intents.

## The one test every group must pass

> Could this group be committed and reviewed on its own, and described in one message **without the word "and"?**

If the natural message is "add retry logic **and** fix the logging bug," it's two groups. If it's "rename `Foo` → `Bar` across the module," that's one — even across twelve files — because it's a single intent.

## Grouping signals, strongest first

### 1. Change-type category
The classic separate-commit axis. Sort hunks into:
- **Feature / behavior change** — the actual new thing.
- **Bugfix** — unrelated to the feature, noticed in passing. Almost always its own commit (it may need cherry-picking or backporting later).
- **Refactor / rename / move** — mechanical, no behavior change. Own commit; it swamps review if mixed with logic.
- **Tests** — usually travel *with* the code they cover (same commit) unless they're a standalone test-only change.
- **Formatting / whitespace / lint-only** — own commit, or drop if accidental. Never mix with logic; it hides the real diff.
- **Dependency / lockfile bump** — own commit.
- **Config / build / CI** — own commit unless it's the point of the change.
- **Docs** — own commit unless documenting the feature in the same change.

Two hunks in the *same file* but different categories → different groups.

### 2. Symbol / dependency coupling
Hunks that **must land together to stay consistent** are one group: a new function and the call sites that use it; a new type and the code that constructs it; a renamed symbol and every reference to it. If splitting them would leave an intermediate commit that doesn't compile or references something undefined, they belong together (or must be ordered — see below).

### 3. Shared intent across files
A feature legitimately spans files (route + handler + test + migration). Co-location by directory is a *hint*, not the rule — bind by purpose. The migration for feature X goes with feature X, not with an unrelated migration that happens to live in the same folder.

### 4. Mechanical churn is its own commit
A rename or move touching many files produces a large, low-information diff. Isolate it so the logic commits stay small and readable. Same for generated artifacts (lockfiles, build output, snapshot/golden files) — own commit, or don't-commit (below).

## The don't-commit detector

Hunks that usually belong in **no** commit. Flag them; let the user confirm — never auto-drop, but never silently commit them either.

- **Debug output** — added `console.log` / `print(` / `fmt.Print` / `dbg!` / `System.out.print` / `var_dump` / stray `puts`.
- **Focused / skipped tests** — `.only(`, `fdescribe`, `fit(`, `test.only`, `it.only`, a lone `xit`/`skip` left in.
- **Commented-out code** — a block commented out beside its replacement; leftover dead code.
- **Leftover scaffolding** — `TODO: remove`, `FIXME before merge`, temporary hardcoded values, `if (true) //` short-circuits.
- **Secrets** — anything matching `API_KEY` / `SECRET` / `PASSWORD` / `TOKEN` / `PRIVATE_KEY` / an `AKIA…` access key, or an edited `.env`. Treat as urgent.
- **Conflict markers** — `<<<<<<<`, `=======`, `>>>>>>>`. This means **stop**: the tree is mid-conflict, don't split anything until it's resolved.
- **Accidental large binaries** — committed build output, images, vendored blobs the user didn't mean to add.

The gather script runs a cheap regex pass for these as hints. Confirm by reading the hunk in context — a `print(` inside a CLI's actual output path is not debug noise.

## Ordering the commits

The constraint is **consistency**, the tiebreaker is **readability**.

1. **No commit may reference something defined in a later commit.** Callee before caller; type/interface before its use; the rename before code that relies on the new name. This is what keeps each commit independently consistent (and bisectable).
2. **Foundational mechanical change first** when later commits build on it (e.g., a rename the feature then uses).
3. **Pure cleanup last** when nothing depends on it (formatting, dead-code removal) — so the logic commits read clean.
4. **Bugfix usually early** if the feature builds on the fixed behavior; otherwise its position is free — pick whatever keeps each commit consistent.

If two groups are *mutually* dependent (A needs B and B needs A), they can't be separated into ordered commits — collapse them into one and say why.

## Entanglement — when a clean split isn't possible

Sometimes two intents live in the **same hunk** (a few changed lines do two things at once). Be honest (hard constraint #2). Options, best first:

1. **Line-level split.** Slice the hunk so each intent lands in its own commit (see `references/execution.md` — patch surgery). Use when the lines are clearly separable.
2. **Commit together, name both.** If the two changes are tiny and truly interleaved, one commit whose message names both is acceptable — but say so, don't pretend it's clean.
3. **Ask.** When you can't tell which lines serve which intent, ask the user rather than guess.

Never silently fold an unrelated change into a neighboring commit to make the buckets look tidy.

## Don't over-split

A commit should be the **smallest change that is still independently meaningful**. Twelve one-line commits fragment review as badly as one giant commit buries it. If you've produced more than ~5–7 groups for an ordinary working tree, reconsider whether some are facets of the same intent.
