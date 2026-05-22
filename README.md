# Claude Skills

A collection of [Claude Code](https://claude.com/claude-code) skills for working *with* a codebase — reconstructing in-progress work, recapping shipped work, and verifying active changes. Each skill is a self-contained directory (`SKILL.md` + bundled `references/`, `scripts/`, `templates/`) that Claude loads on demand.

## The skills

| Skill | What it does | Reach for it when… |
|---|---|---|
| [`verify-change`](verify-change/) | Verifies an active change does what you *intended* — extracts falsifiable intent from the diff, confirms it with you, then has an **independent** subagent (which never sees the implementation) author a layered test suite. Targets CLI / UI / log / filesystem behavior that unit tests miss. | "does this change actually work?", before opening a PR, sanity-checking CLI or UI behavior. |
| [`pr-digest`](pr-digest/) | A per-PR digest of repo activity over a time window — one-line **user-perspective** summaries of each PR and its commits, with priority-lifting and low-signal clustering. | "what shipped this week?", "catch me up on PRs", "what's in flight?". |
| [`what-was-i-doing`](what-was-i-doing/) | Reconstructs in-progress work from git state (uncommitted diff, branch, recent commits, stashes) — infers the goal, where you stopped, and the safe next step. | Returning to your own work after a context switch: "where did I leave off?". |

## The shared design principle

All three resist the same failure mode: **restating what's already visible.** A naive tool enumerates — `git status` lists changed files, `gh pr list` lists PRs, a diff shows the diff. These skills are built to add the layer enumeration can't:

- **Falsifiable over descriptive.** `verify-change` forbids intent bullets that merely describe the diff ("adds retry logic"); they must be checkable claims that *could be wrong* ("on a 4xx, fails immediately with no retry"). `what-was-i-doing` applies the same discipline to inference — every "you were doing X" cites the signal that implies it, so you can reject a wrong guess at a glance.
- **User-perspective over diff-perspective.** `pr-digest` rewrites each PR as "what someone using this codebase got," not "what the diff did."
- **Confident-or-silent.** `what-was-i-doing` omits a "next step" rather than guess one; `verify-change` asks a clarifying question rather than fabricate intent.

If a line could be replaced by a `cat` of the underlying source and lose nothing, it gets cut.

## Installation

The skills are consumed by symlinking each one into `~/.claude/skills/`:

```sh
for s in verify-change pr-digest what-was-i-doing; do
  ln -s "$PWD/$s" "$HOME/.claude/skills/$s"
done
```

Symlinks (not copies) mean edits in this repo are live immediately — no re-deploy, no drift. Claude triggers a skill automatically based on its `description`, or you can invoke it explicitly with `/<skill-name>`.

## Requirements

- **`verify-change`** — `git`; a test runner in the target repo (jest/vitest/pytest/etc.); optionally Playwright/filesystem MCP for the agent-driven UI/log layers.
- **`pr-digest`** — `git` and the [`gh`](https://cli.github.com/) CLI (authenticated). Falls back to a commit-shaped digest when `gh` is unavailable.
- **`what-was-i-doing`** — `git` only. Fully read-only.

The bundled shell scripts are Bash 3.2-compatible (macOS default) and pass `shellcheck` clean.

## Repo layout

```
.
├── verify-change/      # SKILL.md + references/ + scripts/ + templates/ + BRIEF.md (original build brief)
├── pr-digest/          # SKILL.md + references/
└── what-was-i-doing/   # SKILL.md + references/ + scripts/
```
