# Triage — classifying test failures

When tests fail, the triage subagent classifies each failure into one of three buckets. Unlike the test-author subagent, **the triage subagent IS allowed to see both code and intent** — its job is classification, not authoring, so the independence boundary doesn't apply here.

## The three verdicts

### 1. `code bug`

The intent bullet is well-formed, the test is fair, and the code is wrong.

Evidence shapes:
- The observable produced by the code does not match what the bullet states should happen.
- The code branches mentioned in the bullet are not all exercised (a branch is missing or unreachable).
- The code produces the expected output only by coincidence (e.g., on a fixture but not in the test's input).

**Recommended action:** fix the code. Quote the bullet, quote the test, quote the actual output, point at the file(s) most likely responsible.

### 2. `intent ambiguity`

The intent bullet was under-specified or genuinely ambiguous, so the test asserted something the user didn't actually mean.

Evidence shapes:
- The bullet uses a word that could be interpreted multiple ways ("validates", "handles", "processes").
- The test picked a reasonable interpretation but the code implements a different reasonable interpretation.
- The user's optional note conflicts with what the bullet states.
- The bullet asserts an effect that wasn't an explicit goal (e.g., asserting an exit code the user never specified, just inferred).

**Recommended action:** refine the bullet and re-run. The triage report should propose specific revised wording for the bullet so the user can accept-or-edit in one step.

### 3. `flaky / environment`

The failure is not deterministic or is caused by the test environment, not the code.

Evidence shapes:
- The test passes when re-run.
- The test fails because a required service / fixture / env var is missing.
- The test fails because of unrelated state in the working tree.
- The test depends on wall-clock time, network, or other non-determinism.

**Recommended action:** identify the source of flakiness. Either fix the test (e.g., add a wait condition, mock the time source) or quarantine it with an explicit note (`@pytest.mark.skip(reason="verify-change: flaky on missing X, see TRIAGE.md")`). Do NOT silently retry until it passes.

## Triage subagent prompt shape

When spawning triage, the main agent passes:

1. **The intent bullets** (confirmed, from `INTENT.md`).
2. **The failing test files** (with their headers, so the bullet→test mapping is clear).
3. **The failure output** (stderr, assertion messages, stack traces).
4. **Access to the source tree.** This is what makes triage different from the test-author — the triage agent MUST read the source to assign blame.
5. **The task:** "classify each failure into {code bug, intent ambiguity, flaky/environment}, with evidence and a suggested next step. Do NOT propose code edits. Do NOT auto-fix."

## Output format (`TRIAGE.md`)

```markdown
# Triage report — verify-change

## Summary
- Total failures: N
- Code bugs: x
- Intent ambiguities: y
- Flaky / environment: z

## Per-failure detail

### Failure 1: <test file path> :: <test name>

- **Verdict:** code bug
- **Intent bullet:** "<bullet text verbatim>"
- **Test asserted:** "<assertion text>"
- **Actual observed:** "<actual output>"
- **Evidence:** <1-3 sentences citing specific code locations (file:line) and reasoning>
- **Suggested next step:** <"fix at src/foo.ts:42 to do X" | "refine bullet to '...' and re-run" | "quarantine and investigate flake source in <area>">

### Failure 2: ...
```

## What triage MUST NOT do

- Edit code, even to "demonstrate" the fix.
- Edit tests, even to "demonstrate" the better assertion.
- Edit `INTENT.md` directly. (Suggest revised wording in the report; the user accepts and re-runs.)
- Soften a verdict to avoid confrontation. If the evidence says code bug, say code bug — don't hedge to "could be intent or code." Hedging is what makes triage useless.

## What the main agent does with the report

1. Surface `TRIAGE.md` to the user.
2. Do NOT auto-apply suggested fixes.
3. If there are ambiguity verdicts, offer to update the relevant bullets in `INTENT.md` (paste the suggested revised wording, ask for ok/edit), then re-spawn the test-author subagent with the corrected intent.
4. If there are code-bug verdicts, the user fixes the code and re-runs the harness. Tests stay as they are.
5. If there are flake verdicts, the user investigates the underlying flake source (don't retry-until-pass).
