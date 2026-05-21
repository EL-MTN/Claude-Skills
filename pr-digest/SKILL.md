---
name: pr-digest
description: Generates a per-PR digest of repo activity over a time window, with one-line user-perspective summaries of each PR and its commits. Use this when the user asks "what's shipped recently", "what's in flight", "PR digest", "catch me up on PRs", "what merged this week", or wants a quick scan of recent repo activity that's more readable than `gh pr list`. Also use when the user wants a recap of recent work in a specific repo without having to chase down individual diffs.
---

# pr-digest

Generates a structured, **user-perspective** digest of merged + open PRs in a time window. Each PR gets a 1–2 sentence summary; each non-noise commit gets a one-line phrase describing what changed for a user of the codebase.

## The load-bearing rule

**Every line answers "what does someone using this codebase get out of this?" — not "what does the diff do."**

Naive `gh pr list` and `git log --oneline` already enumerate. The value here is the user-perspective rewrite: each commit summarized as if it were a tiny PR title, each PR summarized as a user-visible delta. If a line could be replaced by a `cat` of the commit message and lose nothing — rewrite it.

See `references/summarization-rubric.md` for the phrasing rules, noise filter, and length budget.

## Inputs

- **Repo:** the current working directory's git repo. If not in a repo, ask the user to point at one.
- **Window:** defaults to **7 days**. Accept overrides like "last 2 weeks", "since Monday", "since v1.2", an ISO date, or a git ref.
- **Scope:** merged + open PRs by default. Skip drafts and closed-without-merge unless the user asks for them.

## Workflow

### 1. Resolve the window

If the user gave a phrase, normalize it to an ISO date or a ref:
- "last N days/weeks" → date math from today
- "since Monday" / "since yesterday" → resolve to date
- ISO date / git ref → use as-is

Default if unspecified: `since=$(date -v-7d -Iseconds)` (or `date -d '7 days ago'` on Linux).

State the resolved window back to the user in one line before producing the digest:
> "Digesting PRs in `<repo>` since `<resolved>` (merged + open)."

### 2. List PRs in scope

```
# Merged in the window
gh pr list --state merged --search "merged:>$SINCE" --json number,title,author,mergedAt,headRefName,body,additions,deletions,baseRefName --limit 100

# Currently open AND touched in the window (avoid pulling unbounded ancient open PRs)
gh pr list --state open --draft=false --search "updated:>$SINCE" --json number,title,author,createdAt,updatedAt,headRefName,body,additions,deletions,baseRefName --limit 100
```

Both queries are time-bounded. The open query uses `updated:>` (not `created:>`) so a PR opened months ago that someone touched yesterday still shows up — that's "in flight" for the purpose of a catch-up. Without the time filter, the open query can pull tens of KB across long-stale PRs and bury the signal.

If `gh` isn't authenticated, fall back to git-only mode (commits on the default branch since the window, grouped by merge commit if present). Tell the user `gh` was unavailable so the digest is commit-shaped, not PR-shaped.

### 3. For each PR, gather commits and a representative diff

```
gh pr view <num> --json commits,files,body
# OR if you need diffs:
gh pr diff <num>
```

For each commit, you want:
- the short SHA
- the commit message subject
- a small diff sample (first ~200 lines of `git show <sha>` is usually enough)

Skip the noise filter's targets (see rubric).

### 4. Summarize

For each PR:
- **Per-PR summary:** 1–2 sentences, user-perspective. Use the PR description if present and good; rewrite if it's "wip" / template-only / author-perspective.
- **Per-commit lines:** one short phrase each, after applying the noise filter. Group consecutive commits by the same author that refine the same change ("add feature" + "fix lint on it" → single line).

Cap each PR at ~8 commit lines. If a PR has 30 commits, summarize the work into groups rather than enumerating.

**Note on squash-merged PRs (very common).** Most modern GitHub repos squash-merge by default, so a merged PR's commit list will often be a single squashed commit (sometimes with the original branch's WIP commits still attached). The rubric handles this: when every commit is noise or there's only the squash commit, **skip the per-commit section entirely** and let the per-PR summary carry the full description. This is correct behavior, not cutting corners — don't apologize for the missing section. See `references/summarization-rubric.md` ("When ALL commits are noise").

### 5. Render

Use the format below. Order PRs: merged first (most recent → oldest), then open (most recently updated first). Within each, no other re-ordering.

```
# PR digest — <repo>, since <resolved-window>

## #<num> <title> (<state>, <author>, <date>)
<1–2 sentence user-perspective summary>

- <commit phrase 1>
- <commit phrase 2>
- ...

## #<num> ...
```

If there are no PRs in the window, say so plainly and offer to widen the window or switch to commit-shaped mode.

### 6. Footer

Two lines:
- `<N merged> · <M open> · <K skipped>` (skipped = drafts + closed-without-merge — only show if non-zero)
- A `gh` command the user can run to see the underlying list. Because merged + open are two separate queries, give the user a combined one using the search-syntax `OR`:

  ```
  gh pr list --search "merged:>$SINCE OR updated:>$SINCE"
  ```

  This collapses the two queries into one the user can paste and tweak. Don't render multiple footer commands — pick the single best one.

## Failure modes to resist

- **Author-perspective phrasing.** "Refactors the X module to use Y" is what *the diff did*. "Cuts ~30% off cold-start time on the main endpoint" is what *a user got*. Stay on the user side. The rubric has examples.
- **Enumerating without summarizing.** If you find yourself listing 15 commits verbatim from `git log`, you've fallen back to a digest. Summarize.
- **Skipping the noise filter.** Merge commits, lint-only commits, "wip" / "fix CI" / "address review feedback" commits are noise. Cut them silently unless they're the *only* commit (then explain what the PR actually changed from the diff).
- **Inventing details.** If the description is empty and the diff is opaque, say so: "PR has no description; diff touches X files in Y. Run `gh pr view <n>` for detail." Don't fabricate user-impact claims.

## When the user has a follow-up

Common next asks:
- "What happened in PR #X specifically?" → `gh pr view <n>` + `gh pr diff <n>` and summarize at higher detail using the same rubric.
- "Filter to just my PRs" → re-run with `--author @me`.
- "Show closed-without-merge too" → re-run including `--state closed`.
- "Group by feature area" → re-render by clustering PRs whose changed files share a top-level directory.
