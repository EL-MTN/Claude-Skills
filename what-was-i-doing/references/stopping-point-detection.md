# Stopping-point detection

The valuable, hard part of `what-was-i-doing`: finding where the thread was cut. `git status` tells you *which* files changed; this tells you *where in them you stopped*. Read the actual changed files (the diff alone often isn't enough — you need surrounding context to spot a stub or a dangling edge).

## The signals, strongest first

### 1. Syntax / parse / type errors in the working tree
The strongest "interrupted mid-keystroke" signal. A file that doesn't parse, an unclosed brace, a half-typed statement, a type error a linter would catch. You almost certainly stopped *here*.

How to detect: run the project's linter/typechecker/compiler on changed files if cheap (`tsc --noEmit`, `python -m py_compile`, `cargo check`, `go build`). Or eyeball the diff for obviously incomplete lines. **Don't fix it** — just report it as the cut point.

Implies: "You were mid-edit at `<file:line>` — it doesn't currently parse."

### 2. A new/changed test that fails, mapping to incomplete code
TDD signal. You wrote the test that specifies the behavior, haven't finished the code. Or you changed code and a test now fails because you're partway through.

How to detect: if a test file is new/modified in the diff, run just that test (or the suite if fast). A failing new test next to a stub implementation is a near-certain "implement this next."

**If the test runner isn't available** (not installed, no venv, missing deps): don't give up — fall back to *static* reading. A new test that calls a function whose body only `raise`s / stubs is failing-by-inspection; you don't need to execute it to know. State that you inferred the failure by reading rather than running, so the user can weight it.

Implies: "Test `<name>` exists and fails; the implementation at `<file:line>` is a stub — you were doing test-first and stopped before the code."

### 3. Stub / placeholder bodies
A function whose body is `pass`, `...`, `raise NotImplementedError`, `throw new Error("not implemented")`, `TODO()`, `unimplemented!()`, an empty block, or a lone `return null` with a `// TODO` next to it — *and* it's part of the uncommitted diff.

How to detect: read changed files; scan added/modified functions for stub bodies. Cross-check it's in the diff (a long-standing stub elsewhere isn't your stopping point).

Implies: "You declared `<fn>` but haven't written its body."

### 4. The most-recently-modified file (cursor location)
Whichever changed file has the newest mtime is probably where you were typing last. Weak on its own, strong as a tiebreaker.

How to detect: the gather script reports changed files sorted by mtime. The top one is your likely cursor.

Implies: "Last file you touched was `<file>` (mtime <time>)."

### 5. Added-but-unused symbol
An `import` / `use` / `require` added in the diff with no use yet, or a new variable/constant/helper defined but never referenced. You started wiring something up.

How to detect: for symbols added in the diff, grep the file (and nearby) for a second occurrence. None → unused.

Implies: "You added `import X` / defined `Y` but haven't used it — you were about to."

### 6. New function/method signature with no callers
You defined the interface, haven't connected it.

How to detect: a new top-level function/method in the diff; grep the repo for calls. Zero → dangling.

Implies: "You defined `<fn>` but nothing calls it yet."

### 7. Leftover merge-conflict markers
`<<<<<<<`, `=======`, `>>>>>>>` in a changed file. You were mid-merge/rebase and stopped.

How to detect: grep changed files for conflict markers.

Implies: "Unresolved conflict in `<file>` — you were mid-merge." (Also a Safety note: the repo may be mid-rebase; check `git status` for "rebase in progress".)

### 8. Mid-refactor: commented-out old block beside new one
A block commented out (not deleted) right next to its replacement suggests you were swapping an implementation and hadn't committed to deleting the old one.

Implies: "You're partway through replacing `<old>` with `<new>` at `<file:line>`."

## Ranking when there are several candidates

Real working trees often have more than one signal. Pick the 1–4 that best answer "where do I resume?":

1. **Fit with the reconstructed goal wins.** A stub in the file that matches the branch's feature is more relevant than an unused import in an unrelated file.
2. **Recency breaks ties.** Newer mtime ≈ closer to where you stopped.
3. **Stronger signal type wins.** A parse error or failing-test-next-to-stub beats a lone unused import.
4. **Cluster, don't enumerate.** If there are eight stub functions (you scaffolded a module), say "scaffolded `<module>` with 8 stubbed methods; none implemented yet" — not eight bullets.

## When there's no clear stopping point

Sometimes the working tree is clean-ish or the changes are complete-looking (everything compiles, tests pass, no stubs). Then there may be no "cut thread" — you might have finished and just not committed. Say that:

> "Everything in the working tree looks complete (compiles, no stubs, tests pass). You may have finished this change and just not committed it — the next step might simply be to commit."

That itself is a useful finding: it reframes "where did I stop" as "you're done, ship it."

## What NOT to do

- **Don't fix anything.** This skill reports the stopping point; it doesn't resume the work. Fixing the parse error or implementing the stub is the user's call (or a separate explicit request).
- **Don't run slow/destructive checks.** Linters and single-test runs are fine; a full CI run or anything that writes state is not. If a check would be slow, note the candidate from static reading instead.
- **Don't treat pre-existing stubs as your stopping point.** Only signals that intersect the uncommitted diff (or very recent commits) reflect *this* session's work.
