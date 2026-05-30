# Critique lenses

Each lens is one expertise. A critic running a lens judges **only** against that lens's checklist and principles, and reports findings in the shared shape (below). The point of separate lenses is independence — convergence across lenses is a strong signal, so don't let one lens silently absorb another.

## Finding shape

Every finding, from every lens, is one record:

- **lens** — which lens produced it.
- **issue** — the problem, in one falsifiable sentence (something that could be shown wrong).
- **location** — where in the artifact ("primary CTA, top-right"; "body paragraph under the hero"; "nav row"). Must be pointable-to.
- **severity** — `blocker` | `major` | `minor` | `polish` (rubric below).
- **principle** — the named heuristic or measurable standard it violates (e.g. "WCAG 1.4.3 contrast", "Fitts's law", "proximity grouping", "16px mobile body floor").
- **evidence** — the observed fact ("contrast ≈ 2.1:1", "two equal-weight buttons", "line length ≈ 120 characters").
- **fix** — a concrete change *only if you're confident*; otherwise leave empty and let the principle guide the designer.

A finding with no `principle` and no `evidence` is taste. Cut it in verification.

## Severity rubric (shared across lenses)

- **blocker** — the design fails its job for some users: text that can't be read (contrast/size), an action that can't be found or operated, a flow with no error/empty state, a control below minimum target size. Ship-stopping.
- **major** — works but materially hurts: weak hierarchy that hides the primary action, inconsistent components that confuse, cramped density that raises cognitive load, copy that misleads.
- **minor** — noticeable friction or inconsistency that most users absorb: slightly off spacing rhythm, a secondary color that clashes, an imperfect type pairing.
- **polish** — refinement only: sub-pixel alignment, a marginally tighter scale, optional delight. Never let polish crowd out blockers in the report.

Calibrate honestly. Most "this feels off" reactions are `minor` at most; reserve `blocker`/`major` for impact you can defend.

---

## 1. Usability & interaction

Can a user understand and operate this without friction?

Checklist:
- **Affordance** — do interactive elements look interactive (and static ones not)?
- **Discoverability** — is the primary action obvious within the first fixation?
- **Flow** — is the path to the goal short and unambiguous? Any dead ends?
- **States** — are error, empty, loading, disabled, and success states designed (not just the happy path)?
- **Feedback** — does the UI confirm actions (hover, active, validation, progress)?
- **Cognitive load** — count the decisions on screen; is anything asking the user to think that the design could decide?
- **Target size** — are tap/click targets comfortably hittable (≥44×44px touch)?

Principles: Fitts's law, Hick's law, recognition-over-recall, progressive disclosure, the happy-path-isn't-enough rule.

## 2. Accessibility (WCAG)

Can people with disabilities use it? This lens is about *compliance and inclusion*, measurable, distinct from aesthetic color.

Checklist:
- **Text contrast** — ≥4.5:1 for normal text, ≥3:1 for large text (WCAG 1.4.3). Estimate ratios; flag anything close.
- **Non-text contrast** — ≥3:1 for UI components and meaningful graphics (1.4.11).
- **Text size** — body text not below ~16px on mobile; nothing relying on tiny type.
- **Color-only signaling** — is any state/meaning conveyed by color alone (error = red only)? Needs a second cue.
- **Focus & order** — is there a visible focus state and a logical reading/tab order?
- **Alt / labels** — do images and icon-only controls have text equivalents?
- **Motion** — any autoplay/parallax that could trigger vestibular issues without a reduce-motion path?
- **Target size** — ≥24×24px (WCAG 2.5.8), ≥44px preferred.

Principles: WCAG 2.2 AA. Cite the specific success criterion when you can.

## 3. Visual hierarchy & layout

Does the eye land where it should, in the right order?

Checklist:
- **First fixation** — squint at it: what do you see first? Is that what matters most?
- **Hierarchy levels** — are primary / secondary / tertiary clearly distinct (size, weight, color, position)?
- **Alignment** — do elements share edges and a grid, or drift?
- **Spacing rhythm** — is whitespace consistent and on a scale (4/8px), or arbitrary?
- **Proximity & grouping** — do related things sit together and unrelated things apart?
- **Balance & density** — is weight distributed, or is one region overloaded and another empty?

Principles: Gestalt (proximity, similarity, common region), visual weight, the squint test, 8-point grid.

## 4. Typography

Is the text set well and legibly?

Checklist:
- **Scale** — is there a clear, limited type scale, or many near-identical sizes?
- **Measure** — line length ~45–75 characters for body; flag very long/short lines.
- **Line-height** — comfortable for the size (~1.4–1.6 for body)?
- **Pairing** — at most ~2 families, with a clear role for each; do they harmonize?
- **Weight contrast** — enough weight difference to build hierarchy without relying on size alone?
- **Hierarchy** — heading/body/caption visually distinct and consistent.

Principles: measure, vertical rhythm, type-scale ratios, contrast through weight.

## 5. Color

Is color used cohesively and meaningfully (aesthetics, beyond a11y compliance)?

Checklist:
- **Palette cohesion** — a deliberate, limited palette, or accumulated one-off colors?
- **Semantic use** — do success/warning/error/info read consistently and conventionally?
- **Emphasis** — does the accent/brand color reliably mark the primary action, or is it sprinkled?
- **Neutrals** — is there a proper neutral ramp for surfaces/text, not just pure black/white?
- **Saturation balance** — anything vibrating or fighting for attention?

Principles: 60-30-10, semantic consistency, restraint, accent-marks-action.

## 6. Brand & content

Does it sound and feel like the right product, and is the copy clear?

Checklist:
- **Voice/tone** — consistent and appropriate to the audience (from `$2` if given)?
- **Microcopy** — are labels, buttons, and errors clear, specific, and human ("Save changes" vs "Submit"; useful error vs "Something went wrong")?
- **Imagery** — does photography/illustration/icon style match and earn its space?
- **Brand alignment** — does the visual language match stated brand guidelines (when provided)?

Principles: clarity over cleverness, consistency of voice, content-as-UI.

## 7. Consistency & design-system

Is the design internally consistent and faithful to its system?

Checklist:
- **Component reuse** — same purpose, same component? Or several near-duplicate variants?
- **Token adherence** — do colors/spacing/radius/type match the defined tokens (check Figma `get_variable_defs` when available)?
- **Pattern deviation** — does anything reinvent an existing solved pattern?
- **State consistency** — do equivalent elements behave/look the same across the screen?

Principles: single source of truth, token discipline, least astonishment.
