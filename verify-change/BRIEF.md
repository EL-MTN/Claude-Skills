# Build Brief: `verify-change` — a Claude Code skill

You are going to build a Claude Code skill. Read this entire brief before writing anything. It contains a few load-bearing design constraints that are easy to accidentally violate, and the whole value of the tool collapses if you do. I'll flag those explicitly.

---

## 1. What this skill does (the mission)

When I'm working on an active change, I invoke this skill. It looks at the change, figures out **what I was trying to do** (not just what the code does), and independently generates a layered test suite — deterministic where possible, agent-driven where not — that I can run locally to verify the behavior is actually correct.

The target is the messy stuff a normal unit-test suite can't easily cover: **CLI behavior and ergonomics, frontend/UI flows, and log output assertions** — plus file-system side effects and other observable effects. This is not a unit-test generator (that space is crowded). It's a behavior verifier for the edges.

---

## 2. The one design principle that everything hangs off

**Change-first experience, intent-first architecture.**

- *Change-first experience*: I trigger the skill on a diff, not on a spec. I never have to write a spec document. The skill meets me where I already am.
- *Intent-first architecture*: before any test is written, the skill makes my **intent** explicit and gets it in front of me to confirm. That confirmed intent — not the code — is what the tests get derived from.

If you collapse these — if you let the skill infer intent from the diff and then write tests in the same breath — you have built a tautology generator. The tests will confirm that the code does what the code does, including its bugs. A subtle bug looks identical to intended behavior in a diff. The entire point of this tool is to break that loop.

So the intent step is **not** optional and **not** removable, even though I never call it a "spec."

---

## 3. The non-negotiables (do not compromise these)

These three constraints are the product. Everything else is negotiable implementation detail.

### 3a. The intent summary must be FALSIFIABLE, not descriptive

When the skill states what it thinks I meant, it must produce specific, checkable claims with explicit branch behavior — claims that *could be wrong* and that I'd catch if they were.

- BAD (descriptive, can't be wrong, teaches nothing): "Adds retry logic to the API client."
- GOOD (falsifiable): "On a 5xx response, retries up to 3 times with exponential backoff. On a 4xx, fails immediately with no retry. On the 4th consecutive 5xx, surfaces the original error to the caller."

The quality of these intent statements *is* the quality of the whole tool. Push the intent-extraction prompt hard toward concrete, branch-level, checkable assertions. If a stated intent can't be checked by a test, it shouldn't be in the list.

### 3b. The test-author must be INDEPENDENT of the implementation

This is enforced structurally using Claude Code subagents, not just requested politely.

- The **main agent** reads the diff and my intent hint, drafts the falsifiable intent bullets, and gets my confirmation.
- After I confirm, the skill spawns a **separate subagent (via the Task tool)** to author the tests. This subagent's context contains **only**:
  - the confirmed intent bullets, and
  - **environment metadata needed to make tests runnable** (see allowed/forbidden list below).
- The test-author subagent does **NOT** receive the diff, the changed source files, or any description of *how* the code works. It literally cannot write tests against the implementation because it has never seen it.

**What may cross the independence boundary** (facts needed to *run* a test): the CLI binary name and how to invoke it, the dev-server start command and URL, log file paths and log format/structure, the test framework and runner available in the repo, relevant fixture/sample file locations, env vars needed to run.

**What may NOT cross the boundary** (facts about what the code *does*): function/method signatures of the changed code, return types or shapes produced by the new code, control flow, the diff itself, variable names from the implementation, or any "here's how it works internally" context. If you find yourself wanting to pass the diff "just for context," that is the failure mode reasserting itself — don't.

Make this boundary visible to me in the output: each generated test file should carry a header noting it was authored from confirmed intent with no access to the implementation. That visibility is a trust feature, not decoration.

(Optional, but design for it: let me configure the test-author subagent to run on a *different model* than the main agent, for genuine cross-model independence. Don't build the multi-model plumbing in v1, but don't architect in a way that forecloses it.)

### 3c. The confirmation step is mandatory and must feel weightless

After the skill drafts intent bullets, it shows them to me and waits. I confirm (one keystroke / "looks good") or correct any bullet. Only then does test authoring begin.

Do not skip this even for "obvious" changes. The first time the skill shows me a subtly wrong bullet — "I think you meant to silently swallow auth errors" when I meant to log-and-rethrow — I catch a real bug at zero cost, and that moment is what makes the tool trustworthy. But make confirming frictionless: default to "all correct," show bullets inline, treat corrections as quick edits, never a form.

---

## 4. The workflow the skill orchestrates

```
1. I invoke the skill on an active change (optionally with a one-line note on what I meant).
2. MAIN AGENT: read `git diff` (and HEAD~1 context, recent commits, linked issue if present)
   + my note. Detect whether this is a feature/behavior change or a refactor (see §6).
3. MAIN AGENT: draft 3-8 FALSIFIABLE intent bullets (§3a). Surface them to me inline.
4. ME: confirm or correct. (Mandatory pause — §3c.)
5. MAIN AGENT: assemble environment metadata (allowed facts only — §3b).
6. SPAWN TEST-AUTHOR SUBAGENT with {confirmed intent + environment metadata}, NO diff.
   It produces the layered test suite (§5) + a run harness (§7).
7. Run the suite. Show me results.
8. On failure: spawn a TRIAGE SUBAGENT (this one MAY see both intent and code) that
   classifies each failure as: likely code bug | intent ambiguity | flaky/environment.
9. Persist the confirmed intent as a passive sidecar next to the tests (§8).
```

Follow the skill-creator conventions for structure: a `SKILL.md` with YAML frontmatter (`name`, `description`) plus markdown instructions, and bundled `scripts/` and `references/` directories. Keep `SKILL.md` under ~500 lines; push detail into `references/` and point to it. Use progressive disclosure — the main agent shouldn't need to load the differential-testing reference unless it's handling a refactor.

---

## 5. The four test layers

The test-author subagent generates from these layers, choosing which apply to each intent bullet. Not every change needs all four.

1. **Deterministic example tests** — the regression backbone. Fast, debuggable, run on every save.
   - CLI: spawn the binary, pipe stdin, snapshot stdout/stderr/exit code, assert.
   - UI: Playwright with concrete selectors where they're stable.
   - Logs: trigger an action, capture the log output, assert on structured patterns/levels.

2. **Property / invariant tests** — derived from intent bullets tagged as invariants ("must never log raw tokens," "must exit non-zero on malformed input," "UI must never show stale data after refresh"). Drive with a fuzzer / structured input generator. Catches cases neither I nor the agent enumerated.

3. **Semi-deterministic agent tests** (scripted-steps pattern) — for branching UI flows and interactive CLI sessions. The *steps* are pinned and derived from intent ("run `mytool init`, answer prompts with X, verify a `.config` dir exists with keys A/B"); the agent figures out the *how* (which button, which selector). This is where "things a normal suite can't do" lives. Use Playwright MCP for browser and filesystem MCP for log/file reading rather than reinventing harness infrastructure. Keep step granularity at "what a human tester would write on a sticky note" — not coordinate-clicking, not "complete the whole flow." Re-orient between major steps ("you should now be on the payment page; if not, fail") so state drift doesn't let the agent rationalize success.

4. **Differential / snapshot tests** — see §6. Especially valuable for CLI output and log-format changes.

**Assertions must be concrete**, pinned to observable effects (exit codes, URLs, DB rows, emitted events, file existence, log lines), never soft judgments ("verify it worked"). A soft assertion lets an agent rationalize a pass.

---

## 6. Refactor detection (build this early, it's a large fraction of real changes)

Before extracting feature intent, classify the diff. If it's **refactor-shaped** — public interface preserved, internal changes only, no new behavior implied, no new tests in the diff — do **not** hallucinate feature intent. Switch to **differential mode**:

- Run the relevant surface at `HEAD` and at `HEAD~1` against the same inputs, diff the outputs, and flag any difference as a potential regression.
- This needs no intent extraction at all — the intent *is* "behavior should not change."

Surface this branch to me explicitly ("this looks like a refactor — I'll verify behavior is unchanged rather than test for new behavior; correct me if you actually changed behavior"). A tool that tries to infer feature intent from a pure refactor generates pure noise.

---

## 7. Generate the run harness, not just the tests

Adoption dies if I have to wire up Playwright, configure log tailing, and set up the CLI runner myself. The test-author subagent must also emit a single entry point (`verify.sh` or equivalent) that sets up the harness and runs all layers with one command, plus whatever config the chosen frameworks need. Lean on existing MCP servers (Playwright MCP, filesystem MCP) so you're orchestrating infrastructure, not building it.

All artifacts — the intent sidecar, the `tests/` directory, the triage report — must be plain files, Git-committable from day one.

---

## 8. The intent sidecar

Persist the confirmed intent bullets next to the generated tests (a comment header in the test file and/or a small sidecar file). I never had to "write" it, but it's now a reviewable, diffable record of what the tests were checking against. This doubles as a PR-description seed. Don't make it heavyweight — it's a record, not a document I maintain.

---

## 9. Scope for v1 (resist building everything)

**Build now:** intent extraction (falsifiable bullets) → confirmation → independent test-author subagent → deterministic CLI layer + semi-deterministic agent layer for UI/logs → refactor detection with differential mode → one-command harness → basic failure triage → intent sidecar.

**Defer:** property/fuzz layer (stub the tagging, implement later), multi-model independence, any dashboard/SaaS surface, multi-repo support, team features, coverage-mapping metrics. Architect so these slot in later; don't build them yet.

Spend the most effort on the **intent-extraction prompt** — it's the highest-leverage, hardest-to-get-right component, and it's where competing tools quietly fail by treating intent as a throwaway intermediate.

---

## 10. The frontmatter `description` (triggering)

The `description` is the only thing that makes the skill fire, and Claude tends to *under*-trigger skills, so make it specific and a little pushy. Something like:

> Independently verifies that an active code change does what was intended, by extracting falsifiable intent from the diff, confirming it, then generating a layered test suite (deterministic + agent-driven) from that intent without the test-author seeing the implementation. Use this whenever the user wants to verify, test, or sanity-check a change they're working on — especially for CLI behavior, frontend/UI flows, log output, or other things a normal unit-test suite can't easily cover — even if they don't say the word "test." Also use it when the user asks "does this change actually work" or wants confidence before opening a PR.

Refine the wording, but keep it specific about *both* what it does and *when* to reach for it.

---

## 11. Validate the skill before declaring done

After drafting, run it against 2-3 realistic changes I'd actually make:
1. A CLI feature change with branch behavior (e.g., a new flag that changes output).
2. A frontend flow change (e.g., a checkout/login step) where selectors may be unstable.
3. A pure refactor (to confirm it switches to differential mode and doesn't invent intent).

For each, check the load-bearing properties specifically: Are the intent bullets falsifiable rather than descriptive? Did the test-author subagent actually run without the diff in its context? Did the refactor case avoid hallucinating feature intent? Show me the outputs and let me review before you iterate.

---

## 12. Suggested layout (adjust as you see fit)

```
verify-change/
├── SKILL.md                       # workflow + the non-negotiables, kept tight
├── references/
│   ├── intent-extraction.md       # how to write falsifiable bullets (+ examples)
│   ├── independence-boundary.md   # allowed/forbidden metadata, subagent prompt
│   ├── test-layers.md             # the four layers, per-surface recipes
│   ├── differential-mode.md       # refactor detection + HEAD/HEAD~1 diffing
│   └── triage.md                  # failure classification rubric
└── scripts/
    ├── collect_change_context.*   # git diff, HEAD~1, recent commits, linked issue
    ├── build_env_metadata.*       # assemble ONLY allowed facts for the boundary
    ├── run_harness.*              # generate/run verify.sh across layers
    └── differential_run.*         # run a surface at two refs and diff outputs
```

Keep the independence boundary logic in its own reference and its own script so it's auditable and hard to accidentally bypass — that's the part I most want to be able to inspect.

---

Build it, then walk me through what you made and how you upheld the three non-negotiables in §3.
