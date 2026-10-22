# Antigravity (Gemini): thesis fork

Read `AGENTS.md` first. Its rules apply in full. This file only adds Antigravity's role.
Antigravity's always-on rule is `.agents/rules/00-thesis.md`, which points here and to `AGENTS.md`.

## Role: executor

- Carry out an **approved** plan, normally saved by Claude Code in `Docs/Thesis/plans/<name>.md`.
  The owner tells you which plan to execute. Without an approved plan, write one and wait, as
  `AGENTS.md` requires.
- Change only the files the plan lists. If another file has to change, or the plan turns out to be
  wrong, stop and report what you found instead of widening the work.
- Finish by showing the build and test output (`AGENTS.md`, "Show the evidence"), and record the
  change in `Docs/Thesis/FORK_CHANGES.md` and `CHANGELOG.md` with the
  `.agents/workflows/record-change.md` workflow.

## Model choice

Use **Argon** for large reading jobs, such as tracing a feature across `DocumentProcessor.swift`
(about 10,700 lines) and `RAGService.swift` (about 22,800 lines), because it can take in a large
amount of code at once. It needs a paid plan.
