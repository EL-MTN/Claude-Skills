---
name: verify-change
description: Independently verifies that an active code change does what was intended, by extracting falsifiable intent from the diff, confirming it, then generating a layered test suite (deterministic + agent-driven) from that intent without the test-author seeing the implementation. Use this whenever the user wants to verify, test, or sanity-check a change they're working on — especially for CLI behavior, frontend/UI flows, log output, or other things a normal unit-test suite can't easily cover — even if they don't say the word "test." Also use it when the user asks "does this change actually work" or wants confidence before opening a PR.
---

# verify-change

Generates a behavior-verification suite for an **active code change**, targeting the things normal unit-test suites miss: CLI ergonomics, frontend/UI flows, log output, filesystem side effects.

The skill orchestrates a workflow built around **change-first experience, intent-first architecture**: the user triggers on a diff, not a spec; before any test is written, the user's *intent* is made explicit and confirmed; that confirmed intent — not the code — is what tests get derived from, by a subagent that has never seen the implementation.

## The three non-negotiables

These are the product. Everything else is implementation detail.

1. **Falsifiable intent.** Intent statements must be branch-level, checkable claims that *could be wrong*. Descriptive summaries ("adds retry logic") are forbidden. See `references/intent-extraction.md`.

2. **Independent test-author.** A subagent authors the tests with access ONLY to confirmed intent + environment metadata needed to *run* tests. It MUST NOT receive the diff, the changed source files, or any "how it works" description. See `references/independence-boundary.md`.

3. **Mandatory confirmation, frictionless UX.** After drafting intent bullets, the main agent MUST pause and surface them to the user. Default to "all correct"; corrections are quick edits, never a form. Never skip this — even on "obvious" changes.

If any one of these is compromised, the tool becomes a tautology generator that confirms the code does what the code does, including its bugs.

## Workflow

```
1. Detect change context (diff, HEAD~1, recent commits, linked issue, optional user note).
2. Classify: feature/behavior change vs refactor (→ §Refactor branch).
3. Draft 3–8 falsifiable intent bullets and surface them inline.
4. Pause for user confirmation. Apply any corrections.
5. Assemble environment metadata (allowed facts only — see independence-boundary).
6. Spawn the test-author subagent with {intent, env_metadata}. NO diff. NO source files.
7. Run the generated suite via the harness. Report results.
8. On failure: spawn the triage subagent (which MAY see both code and intent) to
   classify each failure as: code bug | intent ambiguity | flaky/environment.
9. Persist the confirmed intent as a sidecar next to the tests.
```

### Step 1 — Collect change context

Run `scripts/collect_change_context.sh` from the repo root. It captures:
- `git diff` (unstaged + staged)
- The diff between `HEAD~1` and `HEAD`
- Recent commits (last 10) for tone/intent clues
- Any issue references (`#123`, `JIRA-456`) found in commit messages or branch name

Also accept an optional one-line user note ("I meant to add a `--dry-run` flag") and weave it into the intent draft. The note is a hint, not a spec — still draft falsifiable bullets and confirm.

### Step 2 — Classify the change

Apply the refactor heuristics in `references/differential-mode.md`. The headline signal: public surface preserved, no new behavior implied, no new tests in the diff. If refactor-shaped, **say so explicitly to the user** and offer to verify via differential mode instead of inventing feature intent. Do not silently switch — let the user override.

Load `references/differential-mode.md` only when this branch is taken.

### Step 3 — Draft falsifiable intent

Load `references/intent-extraction.md`. Produce 3–8 bullets, each:
- Branch-aware (states what happens in each branch — happy path, edge, error)
- Concrete (cites specific observable effects: exit codes, file paths, log lines, URLs)
- Checkable (a test could prove it wrong)

Tag each bullet with a layer hint when obvious: `[deterministic]`, `[invariant]`, `[agent-flow]`, `[differential]`. The subagent uses these to pick test layers.

If the diff is ambiguous and you can't draft falsifiable bullets in good faith, **ask the user one clarifying question** before drafting. Don't fabricate intent.

### Step 4 — Confirmation pause (mandatory)

Present the bullets inline and ask:

> Here's what I think you meant. Reply "ok" to confirm, or correct any bullet by quoting it.

Default-accept on "ok", "yes", "lgtm", "looks good", silence-then-go-ahead. On any correction, edit only the affected bullet(s) and re-present briefly. Do not turn this into a form. Do not skip this step under any circumstance, including when the change is "obvious."

The first time the skill shows a subtly wrong bullet — "I think you meant to silently swallow auth errors" when the user meant log-and-rethrow — and the user catches a real bug at zero cost is the moment that makes the whole tool worth using. Protect that moment.

### Step 5 — Build environment metadata

Run `scripts/build_env_metadata.sh`. It assembles ONLY the runtime facts allowed across the independence boundary:
- Test framework + runner command (pytest/jest/vitest/cargo/etc.)
- CLI binary name + invocation pattern (if applicable)
- Dev-server start command + URL (if applicable)
- Log file paths + format/structure (if applicable)
- Fixture directories
- Env vars needed to run

Review the output against the **forbidden list** in `references/independence-boundary.md` before passing it on. If you find yourself wanting to add "context" beyond the allowed list — STOP. That is the failure mode reasserting itself.

### Step 6 — Author the tests via an independent context

Pick the strongest isolation mechanism actually available in your runtime. Three tiers, in preference order:

**Tier 1 (preferred): Agent tool.** Spawn the test-author subagent via the Agent tool with `subagent_type: general-purpose`. Available when verify-change is invoked at the top level of a Claude Code session.

**Tier 2: `claude -p` subprocess.** If the Agent tool isn't in your tool list (e.g., you're already inside an Agent context and nested Agent calls are blocked), spawn a fresh Claude Code process via Bash. This gives *stronger* isolation than Agent in some ways — a separate process with no shared context. Invocation pattern:

```bash
claude -p "$(cat <<'EOF'
<locked prompt from references/test-author-prompt.md, verbatim>

## Confirmed intent bullets

<numbered bullets>

## Environment metadata

<env block>
EOF
)" --cwd "$REPO_ROOT"
```

The spawned process emits its files to `.verify-change/` in the cwd and returns when done. Capture its stdout for the brief summary it reports. The locked prompt does the same work it would inside an Agent — refuse source reads, produce AUDIT.md.

**Tier 3 (last resort): in-process protocol.** If neither Agent nor `claude -p` is available (very constrained runtime), do NOT silently merge the roles. Switch to the in-process protocol defined in `references/independence-boundary.md` ("If the Agent tool is unavailable"). Lock inputs, stop reading implementation, and emit `AUDIT.md` with a dedicated in-process section declaring the fallback.

In all three tiers, the prompt construction is identical:

1. Read `references/test-author-prompt.md` (the locked-down system prompt template).
2. Append the confirmed intent bullets verbatim.
3. Append the environment metadata block.

Pass NOTHING ELSE. No diff, no file paths into changed source, no "by the way the function is called X." Whichever tier ran must produce `AUDIT.md` declaring which tier was used and what directories were accessed. The audit is how the user sees which guarantee actually held.

Each generated test file must carry this header:

```
# Authored from confirmed intent. No access to implementation.
# Independence boundary: enforced by verify-change skill.
# Intent sidecar: ./INTENT.md
```

That header is the visibility surface — the user can scan tests and see the boundary held.

### Step 7 — Run the harness

The subagent emits a `verify.sh` (or platform-equivalent) entry point alongside the tests. Run it via `scripts/run_harness.sh`. Stream output to the user.

The harness must run all generated layers with one command. If it requires manual wiring, the subagent has failed its contract — push back.

### Step 8 — Triage failures

If any test fails, spawn the **triage subagent** (separate Agent call). This one MAY see both intent AND code — its job is classification, not authoring. Load `references/triage.md` and pass it as the prompt along with: the intent bullets, the failing test files, the failure output, and access to the source.

Triage output, per failure:
- **Verdict:** `code bug` | `intent ambiguity` | `flaky/environment`
- **Evidence:** what specifically supports the verdict
- **Suggested next step:** fix the code | refine the intent bullet & re-run | re-run / quarantine

Surface the triage report to the user. Do NOT auto-fix.

### Step 9 — Persist the intent sidecar

Write `INTENT.md` (or `.verify-change/intent.md`) next to the tests. Use `templates/intent-sidecar.md`. This is the reviewable, diffable record of what the tests were checking against. Doubles as a PR-description seed.

## The four test layers (the subagent picks; you don't have to)

The test-author subagent chooses which layers apply to each intent bullet. You don't need to load `references/test-layers.md` unless you're debugging what it produced. Brief summary:

1. **Deterministic example tests** — regression backbone. Fast, pinned assertions. CLI invocation + stdout/exit-code snapshot; Playwright with stable selectors; structured log assertions.
2. **Property / invariant tests** — from bullets tagged `[invariant]` ("must never log raw tokens"). v1 stubs the tagging; full fuzz layer deferred.
3. **Semi-deterministic agent tests** — scripted-steps pattern. Steps are pinned and derived from intent; the agent figures out *how* (which selector, which button). For branching UI / interactive CLI flows. Uses Playwright MCP + filesystem MCP — do not reinvent harness infra.
4. **Differential / snapshot tests** — for output-format changes and refactor verification. See `references/differential-mode.md`.

**All assertions must be concrete.** Pinned to observable effects (exit codes, URLs, DB rows, file existence, log lines). Never soft judgments ("verify it worked"). A soft assertion lets the agent rationalize a pass.

## Refactor branch (differential mode)

When step 2 classifies the change as refactor-shaped:

1. Announce explicitly: "this looks like a refactor — I'll verify behavior is unchanged rather than test for new behavior. Correct me if you actually changed behavior."
2. Skip intent extraction. The intent is: *behavior should not change.*
3. Identify the relevant surfaces (CLI commands, exported APIs, log emitters) — these are extracted as environment metadata only.
4. Use `scripts/differential_run.sh` to execute each surface at `HEAD` and `HEAD~1` against the same inputs, normalize outputs (timestamps, absolute paths, hostnames), diff.
5. Any diff is a candidate regression. Surface them all to the user — don't filter.

The subagent in this branch generates *runners*, not assertion-based tests. The diff IS the assertion.

## Output layout (everything plain files, Git-committable)

Inside the user's repo, generate under `.verify-change/`:

```
.verify-change/
├── INTENT.md                  # the confirmed intent bullets (sidecar)
├── ENV.md                     # the metadata that crossed the boundary
├── tests/                     # generated test files (each carrying the audit header)
│   ├── cli/
│   ├── ui/
│   ├── logs/
│   └── differential/
├── verify.sh                  # one-command harness
└── TRIAGE.md                  # only present after a failing run
```

Add `.verify-change/` to `.gitignore` only if the user requests it; the default is to keep it committable so the record survives.

## Reference files (load on demand)

| Reference | Load when |
|---|---|
| `references/intent-extraction.md` | Drafting intent bullets (step 3). |
| `references/independence-boundary.md` | Building env metadata (step 5) and constructing the subagent prompt (step 6). |
| `references/test-layers.md` | Debugging or tuning what the subagent produced. |
| `references/differential-mode.md` | Refactor branch (step 2 → differential). |
| `references/triage.md` | Triage subagent (step 8). |
| `references/test-author-prompt.md` | Always loaded at step 6. The locked-down subagent prompt. |

## Scripts

| Script | Purpose |
|---|---|
| `scripts/collect_change_context.sh` | Step 1. Gather diff + history + issue refs. |
| `scripts/build_env_metadata.sh` | Step 5. Assemble runtime facts only. |
| `scripts/run_harness.sh` | Step 7. Run the generated `verify.sh`. |
| `scripts/differential_run.sh` | Refactor branch. Run a command at two refs, diff outputs. |

## Failure modes to actively resist

- **"Just for context, here's how the function works."** No. That's the boundary breaking.
- **"This change is obvious, I'll skip confirmation."** No. The skip is what makes the tool useless.
- **"The intent bullet sounds smart, ship it."** Re-check: could it be falsified by a test? If not, rewrite or drop.
- **"It's a refactor but maybe I'll guess feature intent anyway."** No. Switch to differential and say so.
- **"Soft assertion is fine if the agent agrees."** No. The agent will rationalize. Pin to observable effects.

## Done criteria

A run is "done" when:
- Intent bullets are confirmed and persisted in `INTENT.md`.
- All generated tests carry the independence-boundary header.
- `verify.sh` runs all layers with one command.
- Test results + triage (if any failures) are surfaced to the user.
