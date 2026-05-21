# The independence boundary — what crosses, what does not

This boundary is the structural enforcement that makes the test-author subagent unable to write tests against the implementation. If it leaks, the entire skill collapses into a tautology generator.

## The single rule

The test-author subagent receives:
- **WHAT** should be true (confirmed intent bullets), and
- **HOW** to run a test (environment metadata).

It does NOT receive:
- **HOW** the code currently does that thing.

Anything that conveys implementation shape — function names, return shapes, control flow, variable names, the diff, the source files of the changed area — is on the wrong side of the boundary, even if it would make the subagent's job easier.

## Allowed (may cross)

Pass these in the env metadata block:

- **Test framework + runner.** "pytest, invoked as `pytest -x`"; "vitest, invoked as `pnpm test`".
- **CLI binary + invocation.** "Binary is `./bin/mytool`, exits with conventional codes (0 success, 1 error, 2 usage)."
- **Dev-server start command + URL.** "`pnpm dev` serves on http://localhost:5173; ready when stdout contains `Local:`."
- **Log file paths + format.** "Logs to `./logs/app.jsonl`, one JSON object per line with keys `ts`, `level`, `event`, `request_id`."
- **Fixture / sample directories.** "Sample inputs in `./tests/fixtures/`; safe to read."
- **Env vars needed to run.** "Set `MYTOOL_CONFIG=./tests/fixtures/config.toml`."
- **Existing harness commands.** "Project has a `./scripts/seed-db.sh` that you may call before tests."
- **Available MCP servers.** "Playwright MCP is available for UI; filesystem MCP for log reading."
- **OS / shell / interpreter facts.** "macOS, zsh, Node 20, Python 3.12."

Each entry is a *capability* statement, not a *code* statement. "Logs to `./logs/app.jsonl`" is allowed; "the logger is initialized in `src/log/init.ts:42`" is not.

## Forbidden (must NOT cross)

Never include in the subagent prompt:

- The diff (in whole or in part).
- Names of changed files in the source tree, except as paths the test must *not* import from.
- Function or method signatures of the changed code.
- Return types or shapes produced by the new code.
- Control flow descriptions ("it first checks X, then Y, then…").
- Variable names from the implementation.
- "Here's how it works internally."
- "The bug we just fixed was…"
- Implementation rationale ("we switched to a token bucket because…").
- Quotes from commit messages that describe how the change works.

If you find yourself wanting to pass any of the above "just for context" — STOP. That is the failure mode reasserting itself. The subagent can write tests from the *what*; it does not need the *how*.

## The grey area (default to forbidden)

When you're not sure:

- **Error messages and exit-code semantics that are *user-facing*** → allowed (they're an interface). But the *internal exception type* that produces them → forbidden.
- **HTTP endpoints, URLs, route paths** → allowed (interface). The handler function names → forbidden.
- **Config keys and their types** → allowed (interface). The struct that parses them → forbidden.
- **Log line schemas** → allowed (interface). The logger module → forbidden.
- **Database table names and the columns the tests should observe** → allowed. The ORM model class → forbidden.

Heuristic: if a *user* of the system would know this fact, it's likely an interface and may cross. If only the *implementer* would know it, it does not cross.

## Audit checklist (run before invoking the subagent)

Before calling the Agent tool, paste the prepared subagent prompt into a mental review:

1. Does this prompt contain any string that names a function, class, method, or variable from the changed code?
2. Does this prompt describe control flow ("first X, then Y") of the implementation?
3. Does this prompt include any line of the diff?
4. Does this prompt include the path to a file in `src/`, `lib/`, `app/`, `internal/`, etc. — except as a fixture path or a path the test should explicitly *not* import from?
5. Does this prompt include phrases like "the way it works is", "internally it", "the logic is"?

If any answer is yes — fix it before invoking. Strip the offending content; do not invoke until the prompt is clean.

## The subagent's own enforcement

The locked-down prompt (in `test-author-prompt.md`) further enforces the boundary from inside:

- The subagent is instructed to refuse to read files in `src/`, `lib/`, `app/`, `internal/`, and equivalent directories.
- It is instructed to refuse to run `git diff`, `git log -p`, `git show`, or any source-revealing command.
- It is instructed to produce an **audit summary** at the end stating which directories it accessed, confirming none were source.
- It is instructed to flag and abort if it notices the prompt itself contains forbidden content (defensive against operator mistakes).

This is belt-and-suspenders: the main agent strips the prompt, AND the subagent refuses leaks. Either alone is fragile; both together is the contract.

## Visibility: the header in every test file

Every test file the subagent generates must begin with this header (adapted to the file's comment syntax):

```
# ────────────────────────────────────────────────────────────────────
# verify-change: authored from confirmed intent.
# No access to implementation. Independence boundary enforced.
# Intent bullet(s) this test maps to: <list of bullet numbers>
# Source files read while authoring: <directories accessed — should be fixtures/ only>
# Intent sidecar: ./INTENT.md
# ────────────────────────────────────────────────────────────────────
```

If the user opens any generated test file and the header is missing or claims source-tree access, the contract was violated — surface that loudly and re-run.

## Constructing the subagent prompt (step 6 of the workflow)

Build the prompt in this exact order:

1. **Locked-down system prompt** (verbatim from `references/test-author-prompt.md`).
2. **Confirmed intent block** — the numbered bullets, exactly as confirmed, including their layer tags.
3. **Environment metadata block** — the output of `build_env_metadata.sh`, reviewed against this document's allowed/forbidden lists.
4. **No additional context.**

Pass the result as `prompt` to the Agent tool with `subagent_type: general-purpose`. Do not set any other "helpful" fields, do not append helpful tips, do not "ground" the agent by sharing what the diff was about.

## What about the user's optional one-line note?

The user's note ("I added a `--dry-run` flag") was used as a *seed* for intent extraction and then surfaced for confirmation. After confirmation, the note has done its job — only the confirmed bullets cross the boundary. The note itself does **not** get appended to the subagent prompt, even though it might seem harmless. If the note had useful content, it's now in the bullets.

## What about a multi-model setup (deferred)?

v1 runs the test-author subagent on the same model as the main agent. The architecture supports swapping the model later (the Agent tool accepts a `model` parameter). When this is enabled, the independence boundary becomes *cross-model* independence, which is even stronger. Design new code so this remains possible — don't pass model-specific context, prompt fragments, or assumptions through the boundary.

---

## The three-tier isolation ladder

Pick the strongest isolation tier actually available. Each tier is structurally weaker than the one above; pick down only when the higher tier truly isn't available.

### Tier 1 — Agent tool (preferred)

Available at the top level of a Claude Code session. The Agent tool creates an isolated context with its own tool calls visible to the user, and is the cleanest path. See `references/test-author-prompt.md` for the prompt construction.

### Tier 2 — `claude -p` subprocess (also strong)

Available when the Agent tool isn't (typically: inside a nested subagent context, where Agent isn't exposed). Spawn a fresh Claude Code process via Bash. This is *process-level* isolation — fully separate session, no shared memory, no shared context — and in some ways is stronger than Agent. Invocation:

```bash
claude -p "$LOCKED_PROMPT" --cwd "$REPO_ROOT"
```

Where `$LOCKED_PROMPT` is `references/test-author-prompt.md` + confirmed intent + env metadata, concatenated. The subprocess writes `.verify-change/` artifacts in `--cwd` and returns its summary on stdout. The locked prompt's contract (refuse source reads, emit AUDIT.md) is identical to the Agent-tier behavior.

**Important:** the spawned process inherits filesystem access and project context but starts with no conversation history. Do not pre-load it with diff context via env vars, command-line context, or anything other than the locked prompt itself.

**AUDIT.md tag for this tier:** `Tier 2 — claude -p subprocess`.

### Tier 3 — in-process protocol (last resort)

When neither Agent nor `claude -p` is available — very constrained runtimes, sandbox restrictions, no Claude Code binary on PATH. **Do not silently merge the roles** — that's the failure mode the whole skill exists to prevent.

Switch to the **in-process protocol**: the main agent plays both roles, separated by discipline rather than by context isolation. The boundary becomes procedural, not structural. This is weaker than tiers 1 and 2; the audit must make the degradation visible.

### The protocol, step by step

1. **Announce the fallback to the user**, before writing any tests. One short sentence:
   > "The Agent tool isn't available here. I'll author the tests in-process under a strict no-implementation-rereads protocol, and AUDIT.md will declare the fallback. This is procedurally enforced rather than structurally isolated — review the AUDIT and tests with that in mind."

2. **Lock in the inputs.** Re-state the confirmed intent bullets and env metadata block in your working context as the *only* facts you'll author from. Treat anything else (diff, source files, recent file contents) as out of scope for the next phase.

3. **Stop reading implementation.** From this point until tests + harness + AUDIT.md are written, do NOT:
   - Re-read any file under `src/`, `lib/`, `app/`, `internal/`, etc.
   - Re-run `git diff` / `git log -p` / `git show`.
   - Quote, paraphrase, or rely on memory of the diff or source.
   - Read any test file in the changed area (existing tests can reveal expected internal behavior).
   You may read: fixture files explicitly listed in env metadata, your own confirmed `INTENT.md`, the env metadata block, and the locked test-author prompt for self-guidance.

4. **Author every assertion from the bullet text.** Before committing each assertion, run the explicit check:
   > "Could I have written this assertion using only the bullet text and env metadata, with no memory of the implementation?"
   If no — rewrite the assertion or remove it. Note the moment in `AUDIT.md`.

5. **No "I remember it does X" reasoning.** If you catch yourself thinking "the code probably checks for Y first" — STOP. That thought belongs to the diff. The bullet either states the observable or it does not. If the bullet is missing an observable you want to test, go back to the user with a proposed bullet revision — don't quietly add an assertion based on remembered code.

6. **Audit it loudly.** `AUDIT.md` must include a dedicated section:

   ```
   ## In-process protocol used (Agent tool unavailable)

   - Reason: <one sentence>
   - Cutoff point: <when I stopped reading implementation>
   - Sources read during authoring: <list — should be fixtures, INTENT.md, env metadata only>
   - Near-leaks (moments I almost used remembered code): <list — be specific>
   - Confidence the procedural boundary held: <high / medium / low — with reason>
   ```

   Be honest about near-leaks. Listing one is not a failure; hiding one is.

### When the in-process protocol is unsafe

Skip the fallback and stop the workflow with a clear message if any of these are true:

- The diff is very large (more than ~500 lines): too much to reliably "set aside" from working memory.
- The change is in safety-critical or security-critical code where weakened boundary risk is unacceptable.
- The intent bullets reference behavior that's so tightly coupled to internals that you'd need to reason about implementation to test it (this usually means the bullet was under-specified — go back to step 3 of the workflow).

In those cases, report to the user: "I can't run this safely without a real subagent here. Please rerun in an environment with Agent available, or scope the change smaller."

### Why the audit matters more in this mode

When the boundary is structural (spawned subagent), the audit is a courtesy. When the boundary is procedural (in-process), the audit is the *only* visible signal that the boundary held. The user can't inspect the subagent's tool calls because there was no subagent. The audit is their only window. Treat it accordingly: write it as if the user will read it before trusting the tests.
