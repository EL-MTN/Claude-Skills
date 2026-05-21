# Test layers — per-surface recipes

This is reference material the main agent loads when **debugging or tuning** what the subagent produced. The subagent itself has the same layer guidance baked into its locked prompt; this doc is for the main agent to evaluate whether the right layers were picked.

Four layers, picked per-bullet based on its tag and shape.

---

## Layer 1 — Deterministic example tests

The regression backbone. Fast (< 1s typically), debuggable, runs on every save. Use whenever a bullet has a single trigger → single observable effect.

### CLI surface

```
- spawn the binary (env metadata names it)
- supply stdin / args / env
- capture stdout, stderr, exit code
- assert exact strings, exact code, exact files touched
```

Snapshot stdout/stderr when the *exact bytes* matter (e.g., `--help` output). For partial matches, prefer specific substring assertions over regexes — regexes invite false-pass when the agent picks them too loose.

**Concrete observables to assert on:**
- Exit code (integer).
- Stdout / stderr bytes (snapshot or exact substring).
- Filesystem deltas (set of files created/modified/deleted).
- Side effects in named locations (DB rows, config files, log files).

### UI surface (stable selectors)

```
- launch dev server (env metadata names the command)
- navigate to the URL
- click selectors that are stable: data-testid, aria-label, role+name
- assert visible text, URL, DOM state
```

Stable selectors mean: chosen by the page author for testing (data-testid) or required by accessibility (aria). Avoid CSS-class selectors that may change with refactors.

**Concrete observables:**
- Current URL.
- Text content of named elements.
- Element presence / absence.
- Form field values.
- Cookie / localStorage state.

### Log surface

```
- trigger the action
- read the log file from env metadata
- parse structured lines (JSON) and assert exact key/value
```

If logs are unstructured, the test should still extract specific lines (by regex) and assert exact content of those lines — not "logs contain 'success'."

**Concrete observables:**
- Number of log lines emitted by the action.
- Exact level / event / message of each.
- Absence of forbidden fields (token values, PII).

### Filesystem surface

```
- snapshot the directory tree before
- run the action
- compare after
```

Assert the *exact set* of changes — not just "the file exists." A test that asserts `config.toml` exists but doesn't notice that 50 stray temp files also got written has missed a real bug.

---

## Layer 2 — Property / invariant tests

For bullets tagged `[invariant]`. The invariant must hold across *many* inputs:

- "must never log raw tokens"
- "must exit non-zero on malformed input"
- "two concurrent transfers must never overdraw"
- "UI must never show stale data after refresh"

### v1 stub pattern

A single example test that asserts the invariant on 3–5 representative inputs, with a `TODO` comment noting full fuzz coverage is deferred. The invariant lives in `INTENT.md` regardless — that's the durable record.

```python
# TODO: expand to property-based fuzzing (hypothesis)
@pytest.mark.parametrize("token", [
    "sk_test_abc123",
    "Bearer xyz789",
    "AKIA" + "X" * 16,  # AWS-shaped
    "ghp_" + "y" * 36,  # GitHub-shaped
])
def test_no_token_ever_in_logs(token):
    run_action_with_token(token)
    log_content = read_log()
    assert token not in log_content
```

### Full property pattern (when a framework is available)

Use hypothesis (Python), fast-check (JS/TS), proptest (Rust). Generate inputs, run the action, assert the invariant. Shrink on failure.

**The invariant must still be pinned to observables.** "Output is correct" is not an invariant; "output is a JSON object with key `status` whose value is either `ok` or `err`" is.

---

## Layer 3 — Semi-deterministic agent tests (scripted-steps)

For bullets tagged `[agent-flow]` — multi-step UI flows or interactive CLI sessions where:
- Selectors may be unstable (the page is new or in flux).
- The flow branches (success vs error path, conditional UI).
- The "how" of each step is genuinely flexible but the "what" is pinned.

### The scripted-steps pattern

The steps are pinned. The agent figures out the how.

```
step granularity = "what a human tester would write on a sticky note"
```

Wrong granularity (too coarse): "Complete the signup flow."
Wrong granularity (too fine): "Move mouse to coordinates 380, 240, then click."
Right: "Click the 'Sign up' button in the top-right header."

### Re-orient between major steps

Each step ends with a verification — a re-orient — that catches state drift before the next step. Without this, an agent that ended up in a wrong sub-flow will keep going and rationalize a pass.

```
step 3: "Click 'Continue to payment'."
  verify: "the page URL contains '/payment' AND the heading reads 'Payment details'."
  if verify fails → fail the whole test here, do not proceed.
```

### MCP integration

Use the Playwright MCP for browser, filesystem MCP for files/logs. The harness should not contain hand-rolled browser-driving code — that's wasted infra. The subagent's job is the **script of steps**, not the **how to drive a browser**.

### When NOT to reach for Layer 3

If the bullet *could* be tested at Layer 1 with a stable selector, do that. Layer 3 is more expensive (token cost, runtime, flake risk). Use it only when Layer 1 is genuinely insufficient.

---

## Layer 4 — Differential / snapshot tests

For bullets tagged `[differential]`, OR when the whole change is refactor-shaped (see `differential-mode.md`).

### The pattern

```
- run the surface at HEAD     → capture output
- run the surface at HEAD~1   → capture output
- normalize both              → strip timestamps, paths, UUIDs, hostnames
- diff
- assert: empty diff (for refactor) OR diff matches expected delta (for spec'd change)
```

### Output normalization

Volatile fields will produce false-positive diffs. Normalize before comparison:
- Timestamps → `<TS>`
- Absolute paths → relativize to repo root
- UUIDs / random IDs → `<UUID>`
- Hostnames, process IDs, ports → tokens
- Sorting: if order is non-deterministic, sort lines

**State each normalization in the test.** Hidden normalization is how a real regression gets papered over.

### Snapshot tests (when there's no second ref)

When the user wants "this output should not change, period" — capture once, commit the snapshot, fail on diff. The snapshot itself is the contract.

**Snapshots must be small and reviewable.** A 10MB binary snapshot teaches nothing and gets blind-accepted. If the output is big, snapshot a *structural digest* (sorted hash of fields) instead of the full bytes.

---

## Picking layers per bullet

| Bullet shape | Likely layer(s) |
|---|---|
| `[deterministic]` single input → single output | Layer 1 |
| `[invariant]` must hold across inputs | Layer 2 (stub in v1) |
| `[agent-flow]` multi-step UI/CLI with branches | Layer 3 |
| `[differential]` output matches/differs from baseline | Layer 4 |
| Refactor-mode (no intent bullets) | Layer 4 only |
| `[deterministic]` AND CLI with text output | Layer 1 + Layer 4 (snapshot the text) |

A bullet may map to multiple layers. A bullet should never map to zero layers — if it does, it was descriptive (not falsifiable) and should be rewritten.

---

## Portability constraints on the generated harness

The generated `verify.sh` and any bash test files must run on **bash 3.2** (macOS default). That means:

- No `mapfile` / `readarray` — use `while IFS= read -r line; do arr+=("$line"); done < <(...)` instead.
- No `${var,,}` / `${var^^}` lowercasing — use `tr '[:upper:]' '[:lower:]'`.
- No associative arrays (`declare -A`) — use parallel arrays or files keyed by name.
- No `[[ $a < $b ]]` for arbitrary string comparison expecting locale-aware behavior; stick to `[[ "$a" = "$b" ]]` for equality and `sort` for ordering.
- Process substitution `<(...)` is fine, `<<<` here-strings are fine.

If the test framework genuinely needs bash 4+ features, document that as a prerequisite in `verify.sh`'s preflight and `exit 2` with a clear error — don't ship a harness that silently fails on stock macOS.

## What the main agent checks after the subagent runs

When the subagent returns:

1. Did every bullet end up mapped to at least one test? Cross-check with the test file headers ("Intent bullet(s) this test maps to: …").
2. Are all assertions concrete (no "verify it worked" patterns)?
3. Is `verify.sh` one-command runnable?
4. Did the audit show only fixture / docs directories were accessed?

If any of these fail, push back on the subagent (re-invoke with feedback) before running the harness.
