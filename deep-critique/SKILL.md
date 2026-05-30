---
name: deep-critique
description: Critiques a visual/UI design across independent expert lenses (usability, accessibility, visual hierarchy, typography, color, brand/content, consistency) and synthesizes a prioritized, severity-ranked fix list. Each lens is reviewed by a critic that never sees the others, findings are adversarially verified to drop taste-only claims, and overlapping issues are merged. Use when the user wants a design review of a screenshot, a live URL, or a Figma file — "critique this design", "review this UI/screen/mockup", "what's wrong with this layout", "design feedback", "is this accessible", "deep-critique". Input is an image path, URL, or Figma link plus optional context (audience, brand, the specific concern). Distinct from /code-review (judges code) — this judges the rendered design a user sees.
---

# deep-critique

## What this does

Runs a multi-lens design critique. Instead of one shallow pass ("looks clean, maybe tweak the spacing"), it fans out **independent critics** — one per expertise lens — each blind to the others, then adversarially verifies their findings, merges overlaps, and produces a **prioritized, severity-ranked fix list** for a UI screenshot, a live page, or a Figma frame.

It applies the deep-research harness pattern (fan-out → independent perspectives → verify → synthesize) to visual design.

## When to use this

Use when the user wants design feedback on something rendered:
- "Critique this screen / mockup / landing page"
- "What's wrong with this layout?"
- "Is this accessible / readable / on-brand?"
- Before shipping a UI, or before a design review

Don't use when:
- The user wants code quality judged → that's `/code-review`
- The user wants to *build* a design in Figma → that's the `figma-*` skills
- The user just wants a single quick gut-check on one element (answer inline; the full harness is overkill)

## Inputs

- `$1` — the design to critique: an **image path**, a **URL**, or a **Figma link** (`figma.com/design/...?node-id=...`).
- `$2` (optional) — context that sharpens the critique: target audience, brand/voice guidelines, platform (mobile/desktop), or the specific concern ("does the CTA stand out?", "is the form intimidating?").

If no design is given, ask for one — never critique from imagination.

## The procedure

### Step 1 — Ingest the design

Get the artifact into an analyzable form. You must actually look at it; a critique from description is not a critique.

- **Image path** → Read it with the Read tool (it renders visually).
- **URL** → open it with the browser tools and screenshot it. Load `mcp__claude-in-chrome__*` via ToolSearch, `navigate` to the URL, then `read_page` / screenshot. Capture both the default viewport and, when relevant, a mobile width via `resize_window`.
- **Figma link** → use the Figma MCP: `get_screenshot` for the visual, `get_metadata` for structure, `get_variable_defs` for the tokens it's supposed to honor.

Record the **viewport / device** you're judging — a desktop-width critique of a mobile screen is a wrong critique.

### Step 2 — Pick the lens panel

Read `references/critique-lenses.md` for the full catalog. Each lens is one expertise with its own checklist, principles, and severity cues:

1. **Usability & interaction** — affordances, discoverability, flow, error/empty/loading states, feedback, target size.
2. **Accessibility (WCAG)** — contrast ratios, text size, focus order, color-only signaling, alt text, motion, target size.
3. **Visual hierarchy & layout** — first-fixation, alignment, spacing rhythm, proximity/grouping, balance, density.
4. **Typography** — type scale, measure (line length), line-height, pairing, weight contrast.
5. **Color** — palette cohesion, semantic use, emphasis contrast (aesthetic, distinct from a11y compliance).
6. **Brand & content** — voice/tone consistency, microcopy clarity, imagery, brand alignment.
7. **Consistency & design-system** — component reuse, token adherence, deviation from established patterns.

Scale the panel to the request:
- **Quick** ("just glance at this") → the 3 core lenses: usability, hierarchy, accessibility.
- **Default** → those plus typography and color (5).
- **Thorough / "deep" / pre-launch** → all 7.

Honor `$2`: if the user names a concern, the relevant lens leads and gets extra scrutiny.

### Step 3 — Fan out the critics (independent)

Run one critic per lens. **Each critic must be blind to the others' findings** — that independence is the whole point; convergence (two lenses flag the same element) is then a strong signal rather than an echo.

Two ways to run the fan-out:

- **Inline** (default, quick/default panels): hold each lens separately in your own pass — fully evaluate one lens and write its findings before starting the next, judging only against that lens's checklist. Do not let a later lens "remember" and restate an earlier one.
- **Workflow** (only when the user opts into multi-agent orchestration, e.g. says "workflow" or it's a large/thorough review): run `scripts/critique-workflow.js` via the Workflow tool. It spawns one critic agent per lens with the artifact attached, each returning structured findings, then runs the verify + synthesize stages below. Pass the artifact reference and chosen lenses as `args`.

Each critic returns findings in this shape (see the template):
`{ lens, issue, location, severity, principle, evidence, fix }`

### Step 4 — Adversarially verify each finding

A critique's credibility dies on one taste-dressed-as-fact claim. For every finding, challenge it against the artifact before it survives:

- **Is it falsifiable?** Keep findings that cite a checkable fact or named principle ("body copy is ~12px, below the 16px mobile floor"; "primary and secondary buttons share identical weight, so there is no visual 'next action'"). **Drop findings that are pure preference** ("I'd prefer a warmer palette") unless `$2` made that a stated goal.
- **Is it actually present?** Re-look at the named location. If you can't point to it in the artifact, cut it.
- **Is the severity honest?** Recalibrate against the rubric in `references/critique-lenses.md`. A contrast failure that blocks reading is not the same tier as a 2px misalignment.

Default to rejection when unsure. A short list of real issues beats a long list padded with taste.

### Step 5 — Merge, rank, and report

- **Merge** overlapping findings across lenses into one entry, noting which lenses converged (convergence raises confidence and usually severity).
- **Rank** by severity, then by confidence. Blockers first.
- **Credit what works.** Name 2–4 things the design does well, specifically — so the user knows what *not* to touch. A critique that only lists problems is both demoralizing and untrustworthy.
- Write the report using `templates/critique-report.md`.

Suggest a concrete fix only when you're confident in it; otherwise state the problem and the principle and leave the solution to the designer (confident-or-silent).

## Design principles

- **Falsifiable over taste.** Every finding cites a measurable fact or a named design principle — something that *could be wrong* — not a feeling. Pure preference gets cut in verification.
- **Independent lenses.** Critics don't see each other's notes. Diversity catches what one pass misses; convergence across lenses is signal, not redundancy.
- **Severity honest, prioritized.** Never flatten a blocker and a nitpick into one undifferentiated list. Rank by impact.
- **Credit what works.** Always name the strengths, specifically. It calibrates trust and protects what's good from a careless "fix."
- **Confident-or-silent on fixes.** Propose a fix only when sure; otherwise name the problem and the principle and stop.
- **Look, don't imagine.** Never critique from a description. If you can't see the artifact, get it or ask.

## Files

- `references/critique-lenses.md` — the lens catalog: what each lens checks, the principles/heuristics behind it, and the shared severity rubric.
- `templates/critique-report.md` — the output format (strengths, prioritized findings, per-finding shape).
- `scripts/critique-workflow.js` — optional Workflow script for the multi-agent fan-out (one critic agent per lens → verify → synthesize). Run via the Workflow tool only when the user opts into orchestration.
