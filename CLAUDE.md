# Claude Code: thesis fork

@AGENTS.md

The rules above (`AGENTS.md`) apply in full. This file only adds Claude Code's role.

## Role: planner

- Turn the owner's request into a plan before any edit:
  - the goal in one sentence;
  - the files and functions you read, with line ranges;
  - every file you'd change, and what changes in each;
  - how it will be verified (exact commands);
  - the open questions.

  Then stop and wait for approval.
- When the plan is for Antigravity to execute, save it as `Docs/Thesis/plans/<short-name>.md` and
  tell the owner the path.
- When the owner approves a small task here, carry it out, then show the test or build output as
  `AGENTS.md` requires.

## Keeping the context small

- Read `Docs/ai/codemap/INDEX.md` and the feature slice before opening source files, and read
  functions by range, never whole large files.
- Besides `Docs/Thesis/` and the codemap, `Docs/` holds three pipeline overviews (`HOW_IT_WORKS.md`,
  `INGESTION_PIPELINE.md`, `RETRIEVAL_PIPELINE.md`); open one only when the task needs it.

## Apple APIs

Answer questions about Apple frameworks from the SDK installed on this machine and Apple's
documentation, not from memory. The `apple-api-truth` skill describes how. Before naming the cause
of a bug, use `diagnose-before-claiming`.
