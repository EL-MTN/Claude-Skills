export const meta = {
  name: 'deep-critique',
  description: 'Multi-lens design critique: one independent critic per lens, adversarial verify, synthesize a prioritized fix list',
  phases: [
    { title: 'Critique', detail: 'one blind critic agent per design lens' },
    { title: 'Verify', detail: 'adversarially challenge each finding; drop taste-only claims' },
    { title: 'Synthesize', detail: 'merge cross-lens overlaps, rank by severity, credit strengths' },
  ],
}

// args: {
//   artifact: string,        // how a critic can SEE the design — an image path to Read,
//                            // a URL to screenshot, or a Figma node ref. Embedded verbatim
//                            // into each critic prompt; the critic is responsible for viewing it.
//   context?: string,        // audience / brand / platform / stated concern ($2)
//   lenses?: string[],       // subset of LENS keys; defaults to the 5-lens panel
// }
const a = args || {}
if (!a.artifact) throw new Error('args.artifact is required (image path, URL, or Figma node ref)')
const context = a.context ? `\nContext to weigh: ${a.context}` : ''

const LENS = {
  usability:   'Usability & interaction — affordances, discoverability of the primary action, flow, error/empty/loading states, feedback, cognitive load, target size (>=44px touch). Principles: Fitts, Hick, recognition-over-recall, happy-path-isn\'t-enough.',
  a11y:        'Accessibility (WCAG 2.2 AA) — text contrast (>=4.5:1 normal, >=3:1 large), non-text contrast (>=3:1), body text >=16px on mobile, color-only signaling, visible focus & logical order, alt/labels for icons & images, motion safety, target size (>=24px). Cite the success criterion.',
  hierarchy:   'Visual hierarchy & layout — squint test / first fixation, distinct primary/secondary/tertiary, alignment to a grid, spacing rhythm on a 4/8px scale, proximity grouping, balance and density. Principles: Gestalt, visual weight.',
  typography:  'Typography — clear limited type scale, measure ~45-75 chars, line-height ~1.4-1.6 body, <=2 families with clear roles, weight contrast, consistent heading/body/caption.',
  color:       'Color (aesthetic, beyond a11y) — palette cohesion, semantic success/warning/error consistency, accent reliably marking the primary action, a real neutral ramp, no vibrating saturation. Principles: 60-30-10, restraint.',
  brand:       'Brand & content — voice/tone consistency for the audience, clear specific microcopy (labels/buttons/errors), imagery fit, alignment to brand guidelines. Clarity over cleverness.',
  consistency: 'Consistency & design-system — component reuse vs near-duplicates, token adherence (color/spacing/radius/type), no reinvented patterns, equivalent elements look/behave alike.',
}
const DEFAULT_PANEL = ['usability', 'a11y', 'hierarchy', 'typography', 'color']
const lenses = (a.lenses && a.lenses.length ? a.lenses : DEFAULT_PANEL).filter(k => LENS[k])

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['issue', 'location', 'severity', 'principle', 'evidence'],
        properties: {
          issue: { type: 'string', description: 'one falsifiable sentence' },
          location: { type: 'string', description: 'pointable location in the artifact' },
          severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'polish'] },
          principle: { type: 'string', description: 'named heuristic or measurable standard violated' },
          evidence: { type: 'string', description: 'the observed fact (ratio, size, count)' },
          fix: { type: 'string', description: 'concrete fix, or empty if leaving to the designer' },
        },
      },
    },
    strengths: { type: 'array', items: { type: 'string' }, description: 'specific things this lens found done well' },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['keep', 'severity', 'reason'],
  properties: {
    keep: { type: 'boolean', description: 'false if taste-only or not actually present in the artifact' },
    severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'polish'], description: 'recalibrated severity' },
    reason: { type: 'string' },
  },
}

// Pipeline: each lens critiques, then its findings verify as soon as that critique lands.
const perLens = await pipeline(
  lenses,
  (key) => agent(
    `You are a design critic. Judge the design at: ${a.artifact}\n` +
    `First VIEW it (Read the image, or screenshot the URL/Figma node) — never critique from imagination.${context}\n\n` +
    `Apply ONLY this lens and ignore all others:\n${LENS[key]}\n\n` +
    `Return findings as falsifiable records: each must cite a measurable fact or named principle, not preference. ` +
    `Also list specific strengths you saw through this lens.`,
    { label: `critique:${key}`, phase: 'Critique', schema: FINDINGS_SCHEMA }
  ).then(r => ({ key, ...r })),
  (review) => parallel((review.findings || []).map(f => () =>
    agent(
      `Adversarially verify this design-critique finding against the artifact at ${a.artifact}.\n` +
      `Finding: "${f.issue}" at "${f.location}". Claimed principle: ${f.principle}. Evidence: ${f.evidence}.\n` +
      `View the artifact yourself. Set keep=false if this is pure taste/preference (not a defensible principle) ` +
      `or if you cannot actually locate it in the artifact. Default to keep=false when uncertain. ` +
      `Recalibrate severity honestly.`,
      { label: `verify:${review.key}`, phase: 'Verify', schema: VERDICT_SCHEMA }
    ).then(v => ({ ...f, lens: review.key, verdict: v }))
  )).then(verified => ({ key: review.key, strengths: review.strengths || [], verified: verified.filter(Boolean) }))
)

const survivors = perLens
  .filter(Boolean)
  .flatMap(l => l.verified)
  .filter(f => f.verdict && f.verdict.keep)
  .map(f => ({ ...f, severity: f.verdict.severity }))

const strengths = perLens.filter(Boolean).flatMap(l => l.strengths)

phase('Synthesize')
const synthesis = await agent(
  `Synthesize a design critique report from these verified findings (JSON):\n${JSON.stringify(survivors)}\n\n` +
  `And these observed strengths:\n${JSON.stringify(strengths)}\n\n` +
  `Tasks: (1) MERGE findings that name the same element across lenses into one entry, noting the convergence ` +
  `(convergence raises confidence/severity). (2) RANK by severity then confidence; blockers first. ` +
  `(3) Pick 2-4 specific strengths worth crediting. (4) Give the top 3 highest-leverage fixes.\n` +
  `Format as markdown following the deep-critique report template: artifact + viewport, What's working, ` +
  `Findings (prioritized, each with Where / Lens(es) / Why it matters / Fix), and Top 3.`,
  { label: 'synthesize', phase: 'Synthesize' }
)

return { report: synthesis, findingCount: survivors.length, lenses }
