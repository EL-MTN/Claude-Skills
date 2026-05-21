# Intent extraction — how to write falsifiable bullets

This is the highest-leverage step of the whole skill. Most "test generators" produce noise because they treat intent as a throwaway intermediate. We treat it as the contract.

## The bar: each bullet must be *falsifiable*

A bullet is falsifiable when:
1. It states a **specific, observable** claim about behavior.
2. A reasonable test could prove it **wrong**.
3. It distinguishes the branches of the change — what happens on the happy path, edge case, error case.

A bullet is NOT falsifiable when it merely describes what the diff contains, what files changed, or what the code "does" at a high level. Those statements can't be tested because they restate the code.

## Examples

| ❌ Descriptive (tells me nothing testable) | ✅ Falsifiable (a test could prove this wrong) |
|---|---|
| Adds retry logic to the API client. | On a 5xx response, retries up to 3 times with exponential backoff. On a 4xx, fails immediately with no retry. On the 4th consecutive 5xx, surfaces the original error to the caller. |
| Improves the login flow. | An empty password field shows "Password required" inline and does not submit the form. A wrong password shows "Invalid credentials" without revealing whether the email exists. A successful login redirects to `/dashboard` within 2s. |
| Refactors logging. | Every emitted log line is a single JSON object with `ts`, `level`, `event`, `request_id`. Auth-related events never contain the raw token value. |
| Adds a `--dry-run` flag. | With `--dry-run`, the command writes nothing to disk and the process exits 0 after printing "DRY-RUN: would do X" lines. Without `--dry-run`, the same command produces the same files as before. Combining `--dry-run` with `--force` is a usage error and exits 2. |
| Fixes a race condition. | Two concurrent calls to `transfer()` on the same account never produce a final balance less than zero. The losing call returns the `ERR_LOCKED` exit code rather than silently no-op'ing. |

## The shape of a good bullet

```
[<layer hint>] <surface> <input/trigger> → <expected observable effect>
```

Examples:
- `[deterministic]` CLI invoked with `mytool init --no-git` exits 0 and creates `./project/.config/` containing `settings.json` but no `.git/`.
- `[invariant]` No log line at any level contains the substring of a value passed via `--api-key=`.
- `[agent-flow]` From the dashboard, clicking "Add member" → entering an email → clicking "Send invite" results in a toast "Invitation sent" and a new row in the `Pending invites` table whose email matches what was entered.
- `[differential]` `mytool --help` output is byte-identical to `HEAD~1` except for the new line documenting `--dry-run`.

## Branch coverage

For any conditional in the change, write at least one bullet per branch the user could care about. A single "it handles errors gracefully" is not enough — split it:

- What happens on `error_type_A`?
- What happens on `error_type_B`?
- What happens when both happen at once?
- What is reported to the user vs. the log?

If you only have one bullet for code that has three branches, you have not extracted intent — you have summarized.

## Sourcing intent (in priority order)

1. **The user's optional one-line note**, if provided. ("I added a --dry-run flag.") Use this as the seed, not the constraint — still verify it against the diff and probe for branches the user didn't mention.
2. **The diff itself**, read for *intent signals*, not implementation: new flags, new error messages, new HTTP routes, new log calls, new selectors, changed exit codes, changed config keys.
3. **Recent commits and the linked issue** (if any). These often state the user-facing goal more honestly than the diff. A commit message that says "fix: stop leaking session tokens to logs" is a gift — that's the invariant.
4. **The tests already in the diff** — these are a hint about what the user themselves thought worth verifying. Treat them as bullets the user has already implicitly drafted; you may extend but don't ignore them.

## Tag for layers

Append one tag per bullet so the test-author subagent can route:

- `[deterministic]` — single input, single observable output, fast.
- `[invariant]` — must hold across many inputs (property-style). v1 stubs the fuzzer; the bullet still gets written.
- `[agent-flow]` — multi-step UI or interactive CLI; needs the scripted-steps agent pattern.
- `[differential]` — output should match (or differ in a specific way from) a known baseline / `HEAD~1`.

A bullet can have multiple tags if genuinely applicable.

## How many bullets?

3–8. Fewer than 3 means the change has too few testable claims (or you're under-extracting). More than 8 usually means you're describing implementation steps, not intent — collapse them.

## When the diff is genuinely ambiguous

Don't fabricate. Ask one clarifying question:

> "Looking at the diff, I see you changed both the retry policy and the timeout. Which one is the load-bearing change for this PR — or both? I want to make sure I draft bullets for the right behavior."

Then draft.

## When the user provides a note that contradicts the diff

This is a high-value moment. Surface the contradiction:

> "Your note says you added a `--dry-run` flag, but I don't see a flag parser change in the diff — only the file-write paths got conditional checks on an existing `env.DRY_RUN`. Did you mean the env var, or is there an unstaged change?"

This catches "I thought I committed it" bugs before tests even get written.

## Obvious observables to always pin (the "always-pin" checklist)

LLM-driven intent extraction is variable in how aggressively it pins observables. The same bullet can be written soft ("`tidy --help` mentions `--dry-run`") or pinned ("`tidy --help` exits 0 AND stdout contains `--dry-run`") — and the pinned version catches latent bugs the soft version misses. Always pin these when the surface is in scope:

- **`--help` / `-h` exits 0** with the documented usage on stdout. This convention exposes argparse/clap-style wrappers that accidentally remap exit codes.
- **`--version` / `-V` exits 0** with the version string on stdout (not stderr).
- **stdout vs stderr discipline.** When a bullet asserts an error message, pin which stream it lands on. Mixing them is a common regression and harder to spot once `2>&1` masks it.
- **Exit codes are explicit integers.** Not "non-zero." A bullet that says "fails" should say "exits 1" or "exits 2" — not "exits with an error."
- **No trailing whitespace / no extra newlines in error output.** If the user cares about clean output, pin it; if they don't, you can skip — but make the decision consciously rather than by omission.
- **Idempotency on re-run.** If a command is supposed to be safe to re-run (a tidy/cleanup/dry-run operation), pin that running it twice produces the same final filesystem state.
- **No new directories / files created in error paths.** A `--dry-run` that fails early should not have created the target directory on its way out.
- **Environment-clean exits.** Process exits with no children left running (matters for background-process bugs).

These are interface conventions, not implementation details, so they cross the boundary cleanly. Adding them costs one line per bullet and is the difference between "test passes the change" and "test catches a latent bug in code that was already there."

## Self-check before presenting

Before showing bullets to the user, re-read each one and ask:
1. Could a test prove this wrong? If no → rewrite or drop.
2. Does it cite a specific observable effect (exit code, file path, log line, URL, DB row, emitted event)? If no → make it concrete.
3. Does it describe what the code *does* (descriptive) or what *should be true* (falsifiable)? If the former → rewrite.
4. Is the same effect stated across multiple bullets? If yes → merge.
5. Have I assumed a branch I haven't actually seen evidence for? If yes → mark as inferred and ask the user.

## What gets shown to the user (step 4 confirmation)

```
Here's what I think you meant by this change:

1. [deterministic] <bullet 1>
2. [invariant]     <bullet 2>
3. [agent-flow]    <bullet 3>
...

Reply "ok" to confirm all, or quote a bullet to correct it.
```

Keep it inline. Do not prompt with a form. Do not enumerate alternatives. Trust the user to either ack or correct.
