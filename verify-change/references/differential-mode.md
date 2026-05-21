# Differential mode — refactor detection and HEAD/HEAD~1 diffing

A large fraction of real changes are refactors: public surface preserved, internals reshuffled. A tool that tries to extract "feature intent" from a pure refactor will hallucinate intent and produce noise tests that pass for the wrong reason.

The fix: detect refactor shape early; switch to differential mode; verify behavior is unchanged instead of testing for new behavior.

## Refactor heuristics (run during step 2)

Apply these to the diff. Strong signal → likely refactor; weak signal → still feature-shaped.

| Signal | Direction |
|---|---|
| No new public function/method/class names | refactor |
| No new flags / CLI options / HTTP routes | refactor |
| No new user-facing strings (errors, prompts, log events) | refactor |
| No new tests in the diff | refactor |
| Net line delta is small relative to # files touched (lots of moving, little adding) | refactor |
| Commit messages contain "refactor", "rename", "extract", "move", "inline", "cleanup" | refactor |
| Branch name contains "refactor", "cleanup", "tidy" | refactor |
| Many files touched but each by a small delta | refactor |
| One file touched with large net additions | feature |
| New function names appear at module top-level | feature |
| New `if` branches, new error types | feature |
| New tests added by the user | feature |
| New dependencies added | feature (probably) |

The above are signals, not proofs. The decision rule is: if **most signals point refactor AND no signals point feature**, classify refactor. Otherwise feature, even if there's mixed evidence.

**Always announce the classification to the user before acting on it:**

> "This looks like a refactor — I see no new public API names, no new user-facing strings, and the commits say 'extract auth helper'. I'll verify behavior is unchanged via differential mode rather than test for new behavior. Correct me if you actually changed user-facing behavior."

If the user says "no, there's new behavior in there," go back to intent extraction. Don't argue.

## Differential mode workflow

When refactor classification stands:

1. **Skip intent extraction.** The intent IS: behavior should not change.
2. **Identify the surfaces to verify.** Ask: what observable outputs would change if this refactor accidentally broke something? Candidates:
   - CLI commands (run `<binary> --help`; pick the top-level commands).
   - HTTP routes (if the project has them — read the route table, not the handlers).
   - Exported library functions (if it's a library — read the public interface, not the bodies).
   - Log emitter call sites (run a representative action; what does it log?).
3. **Pick concrete inputs.** Fixtures from the repo, or canonical commands like `--help`, `--version`, `<command> --dry-run <fixture-file>`.
4. **Run each surface at HEAD and HEAD~1** via `scripts/differential_run.sh`.
5. **Normalize and diff.** Surface every non-empty diff to the user.

## `differential_run.sh` contract

The script:
1. Stashes any uncommitted changes (so we can return to them cleanly).
2. Runs each given command at the current `HEAD`, captures stdout/stderr/exit code to a temp file.
3. `git checkout HEAD~1` (or whatever base ref is specified).
4. Runs the same command, captures to another temp file.
5. `git checkout -` to return.
6. Restores the stash.
7. Normalizes both outputs (timestamp → `<TS>`, abs paths → relative, UUIDs → `<UUID>`).
8. Diffs.

The script must be **defensive** about the stash/checkout dance:
- Use `git stash push --include-untracked --message verify-change` so the stash is identifiable.
- On any error, restore HEAD and the stash before exiting.
- If the working tree is dirty AND the user hasn't committed, warn loudly — differential mode against `HEAD~1` will not test the user's current uncommitted work unless we capture it first.

## Output normalization rules

Apply uniformly to both outputs before diffing:

| Field | Pattern | Replace with |
|---|---|---|
| ISO timestamps | `\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}` | `<TS>` |
| Unix timestamps (10+ digits in obvious time positions) | context-dependent | `<TS>` |
| Absolute paths under `$REPO_ROOT` | the prefix | `.` (relativize) |
| Absolute paths under `$HOME` | the prefix | `~` |
| UUIDs | standard regex | `<UUID>` |
| PIDs (in obvious positions like `pid=12345`) | `\d+` | `<PID>` |
| Localhost ports | `localhost:\d+` | `localhost:<PORT>` |

These are *non-load-bearing* fields — if they're load-bearing (e.g., the refactor was specifically about timestamps), do not normalize them. Surface the per-field decision to the user when in doubt.

## Interpreting the diff

- **Empty diff across all surfaces:** behavior is preserved. The refactor is verified. Report PASS with a list of surfaces checked.
- **Non-empty diff:** candidate regression. Show the diff. Do NOT auto-classify as bug — it might be an intentional side change the user forgot to mention. Ask: "I see this output changed at <surface>. Intentional?"
- **Non-empty diff that looks like noise** (e.g., differing key orders in JSON): better normalization needed. Update normalizer, don't paper over.

## When differential mode is insufficient

Differential mode catches output changes. It does NOT catch:
- Internal-state changes that don't show in outputs (e.g., a cache that now thrashes — same correctness, worse performance).
- Race conditions exposed only under concurrency.
- Errors only triggered by inputs the user didn't think to test.

Surface this limitation to the user when reporting PASS:

> "Behavior is unchanged across the surfaces I checked: `[--help, --version, mytool process fixtures/sample.toml]`. Differential mode doesn't catch concurrency or performance regressions; if the refactor touches those, consider adding a targeted intent bullet and re-running in feature mode."

## Hybrid changes

Some PRs are refactor + small feature ("renamed everything AND added `--dry-run`"). For these:
1. Run differential mode on the refactor surfaces (excluding the new feature).
2. Run normal feature mode on the new feature (intent extraction → confirmation → subagent).
3. Report both.

The user can usually tell when this applies. Ask if you're unsure: "this change looks like it has both a refactor part and a new flag — should I verify both?"
