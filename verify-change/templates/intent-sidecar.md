# Intent — verify-change

These bullets are what the generated tests check against. They were confirmed by the user before tests were authored. The test-author subagent had no access to the implementation while writing them.

This file doubles as a PR-description seed.

## Change context

- Repo: `{{REPO_NAME}}`
- Base ref: `{{BASE_REF}}`
- HEAD: `{{HEAD_SHA}}` ({{BRANCH}})
- Generated: `{{ISO_DATE}}`
- User note (if provided): {{USER_NOTE_OR_NONE}}

## Confirmed intent bullets

{{NUMBERED_BULLETS}}

<!--
  Layer tags:
    [deterministic] single input → single observable output, fast
    [invariant]     must hold across many inputs (property-style; v1 stubs allowed)
    [agent-flow]    multi-step UI/CLI with branches (scripted-steps pattern)
    [differential]  output matches/differs from baseline in a defined way
-->

## Environment metadata that crossed the boundary

```
{{ENV_METADATA_BLOCK}}
```

## Independence boundary

- Test-author subagent received: confirmed intent bullets above + environment metadata block above.
- Test-author subagent did NOT receive: the diff, any source files under `src/`/`lib/`/`app/`/`internal/`/etc., any description of how the changed code works.
- Each generated test file carries a header declaring the boundary.
- The subagent's self-audit is in `.verify-change/AUDIT.md`.

## How to re-run

```
./scripts/run_harness.sh
# or directly:
./verify.sh
```

## How to revise

- To revise a bullet: edit this file, then re-run the skill — it will detect the existing sidecar and offer to regenerate tests against the updated intent.
- To add a new bullet: same as above.
- To remove a bullet: delete the line; the corresponding test will be marked stale on next run.
