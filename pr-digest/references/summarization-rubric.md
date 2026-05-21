# Summarization rubric

The rubric for turning PRs and commits into the user-perspective lines the digest prints. Three rules: phrasing, noise filtering, length.

## Rule 1 — User-perspective phrasing

Every line answers: **"what does someone using this codebase get out of this?"**

| ❌ Author-perspective (what the diff did) | ✅ User-perspective (what changed for someone using this) |
|---|---|
| Refactors the auth module to use the new token store. | No user-visible change; internal cleanup ahead of OAuth work. |
| Adds a `--dry-run` flag to the CLI. | You can now preview what `tidy` would move without touching files. |
| Updates dependencies (12 packages bumped). | Patches CVE-2025-1234 in `lodash`; otherwise routine bumps. |
| Modifies error handling in the request handler. | Failed API requests now retry up to 3 times on 5xx; 4xx still fails immediately. |
| Improves logging output. | Logs are now structured JSON (was free text); old log scrapers will need updating. |
| Bumps Node to 22. | Drops Node 18 support. CI now requires Node 22+. |

The line is for someone scanning a list, not reading a code review. Make every word earn its place.

### When you genuinely can't tell

If the diff is opaque and the PR has no description, write what you *can* tell honestly and stop:
- "Touches 6 files in `src/auth/`; no description provided. Run `gh pr view <n>` for detail."

Do NOT invent user-impact claims. A vague-but-honest line beats an authoritative-sounding fiction.

## Rule 2 — Noise filter

Drop these commits from the per-commit list silently:

- **Merge commits** (`Merge branch '...' into ...`, `Merge pull request #...`).
- **Auto-formatter / linter / pre-commit hook commits** (`prettier`, `black`, `gofmt`, `eslint --fix`, `style:` prefix, `chore: format`).
- **"WIP" / fixup commits** (`wip`, `wip 2`, `fixup!`, `squash!`).
- **CI-only churn** (`fix CI`, `try again`, `ci: bump cache key`, `re-run flaky test`).
- **Review-feedback bookkeeping** that doesn't change behavior (`address review`, `feedback`, `pr review nits`, `rename per @reviewer`) — UNLESS it's the only commit in the PR.
- **Commits whose entire diff is `.md` typo fixes within a larger PR.**

If a commit is borderline (small but real change), keep it. Err on inclusion when there's behavior change; exclude when there's only stylistic change.

### Grouping rule

Consecutive commits by the same author that clearly refine the same change should be merged into one line. Heuristic: if the subject lines look like "X" → "X, but better" → "X, fix lint", that's one user-perspective line ("X"). The grouped line should describe the final state, not the journey.

### When ALL commits are noise

Sometimes a PR's commit list is 100% noise (typical for squash-merge workflows where the PR has one squashed commit + the original branch's commits). In that case:
- Skip the per-commit section entirely.
- Make the per-PR summary carry the full description of what changed.
- Don't apologize for the missing commits — the user doesn't care.

## Rule 3 — Length

- **Per-commit line:** one phrase, ~5–12 words. No trailing punctuation needed.
- **Per-PR summary:** 1–2 sentences. Hard cap at 2.
- **Per-PR commit list:** cap at ~8 lines. If a PR has more meaningful commits than that, group aggressively or summarize ("6 commits adding rate-limit handling across the API layer").
- **Whole digest:** if you're producing > ~40 PR entries, the window is too wide — say so and offer to narrow.

### Writing the per-PR summary

If the PR description is good (specific, user-perspective, has a "what changed" section), use it — but rewrite for tone consistency. If it's a template ("## Summary\n## Test plan"), template-only, or author-perspective, write your own from the diff + commit messages.

Two-sentence template that fits most PRs:
1. *What changed (user-visible)*: "<thing>"
2. *Why or constraint worth knowing*: "<reason or risk>" — only if non-obvious.

The second sentence is optional. Don't pad to two sentences when one is enough.

## Rule 4 — Clustering low-signal PRs

When **3+ consecutive PRs** in the output would all summarize as "no user-visible change" / "internal cleanup" / "CI hygiene" / "routine dep bump", collapse them into a single section rather than rendering them as separate near-identical entries. Three "no behavior change" lines in a row don't scan — one labeled cluster does.

### Cluster format

```
## Internal cleanup (4 merged, mostly @williammartin)
- #13476 Remove discussion workflow
- #13474 Remove dependency on persistent token
- #13470 Remove third-party license debris
- #13461 Bump goreleaser-action 7.2.1 → 7.2.2 (@dependabot)
```

Keep PR numbers and titles (a user who's curious can still dig in). Drop the per-PR summary sentence. The cluster *theme* (section header) names the kind of low-signal — pick the most specific honest label:

- "Internal cleanup" — release-pipeline / CI / build / housekeeping
- "Routine dependency bumps" — dependabot/renovate version-only bumps with no notable upstream changes
- "Docs / typo fixes" — markdown-only PRs
- "Test scaffolding" — adds tests without changing behavior

If the substance is genuinely mixed and no single label fits, the PRs probably shouldn't be clustered.

### Thresholds and edge cases

- **Threshold: 3+ consecutive.** A 2-PR group stays expanded; let it stand on its own. The point is to suppress *repetition*, not to compress aggressively.
- **Mixed authors are fine** if the substance is uniform (e.g., 3 human chore PRs + 2 dependabot bumps can still cluster). Note the dominant author in the header.
- **A bot-only cluster** (e.g., 5 dependabot PRs in a row) renders the bot as the "author" of the cluster.
- **Don't cluster across boundaries.** Don't mix merged + open in one cluster; the merged-vs-open distinction matters more than the cluster theme.

### When NOT to cluster (override rules)

Even with 3+ "no user-visible change" PRs in a row, pull a PR out and let it stand alone when:

- **It touches security-sensitive code.** A one-line "fix token handling on redirect" isn't routine no matter how small the diff is.
- **It's a notable upstream changelog inside a dep bump.** A `go-containerregistry` bump that picks up SSRF fixes is interesting; the bump from `v0.21.5` to `v0.21.6` isn't.
- **It would surprise a careful reviewer.** "Remove third-party license debris" sounds routine, but if you'd expect any reviewer to ask "wait, why?", let it stand.

Use judgment. The rule exists to suppress noise, not to compress signal.

## Examples (the same PR, before and after the rubric)

### Raw `gh` / `git log` output

```
PR #214: "Auth refactor" — author: alice
Description: ## Summary\n- refactor\n## Test plan\n- [ ] manual

Commits:
  abc1234 wip
  def5678 wip 2
  ghi9012 actually working now
  jkl3456 fix tests
  mno7890 address review
  pqr1234 lint
  stu5678 final
```

### After the rubric

```
## #214 Auth refactor (merged Aug 14, @alice)
Centralizes auth-token reading into a single helper; no behavior change for
callers, but `getToken()` is now the only supported import path.

- (no meaningful commit-level breakdown — squash-merge workflow with 7
  WIP commits collapsed into the final state)
```

The summary was *derived from the diff*, not from the useless description and commit messages. That's the rubric working.
