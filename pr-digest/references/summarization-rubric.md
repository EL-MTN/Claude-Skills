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
