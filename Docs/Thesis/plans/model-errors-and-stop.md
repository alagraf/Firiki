# Plan: summary and opinion survive model errors, and Stop works between passes

Status: implemented 14 Nov 2026 (the owner asked to continue without approvals). Deeper fixes 1
and 3 of `POC_PROGRESS.md`.

## Goal

A summary or opinion does not fail as a whole because one model call was too long, refused or
met a busy model, and a Stop takes effect before the next model call instead of after the last.

## What I read

- `GreekLegalDocumentSummarizer.summarize` (one map call per group of articles, then one call for
  the opening) and `GreekLegalOpinionWriter.write` (one call per source, then the conclusion).
  Both take the model as a `respond` closure, replaceable in tests; neither checks for cancellation
  or handles a model error, so any error ends the whole request.
- `GreekLegalChatRouter.failureReason` maps only `LanguageModelSession.GenerationError`. The SDK
  installed (OS 27) deprecates it for `LanguageModelError` (`contextSizeExceeded`,
  `guardrailViolation`, `refusal`, `rateLimited`, `timeout`), `SystemLanguageModel.Error`
  (`assetsUnavailable`) and `LanguageModelSession.Error` (`concurrentRequests`). On OS 27 those fell
  through to the generic «Δοκιμάστε ξανά.» (read from the SDK's
  `FoundationModels.swiftinterface`; not reproduced on a device).
- `ChatScreen`: Stop cancels the query task; the capability runs inside it, so a
  `Task.checkCancellation()` in the passes sees it.

## Changes

1. **New `GreekLegalModelCall.swift`:**
   - `failure(of:)` classifies both error families (context too long, declined, busy,
     unavailable, unsupported language);
   - `respond(...)` wraps one pass:
     - checks cancellation first;
     - when the prompt is too long, retries with its body cut to 60%, then 35% (`shortened`, which
       keeps the header and cuts at a line or sentence end);
     - when the model is busy, retries once after 1 s;
     - throws `Declined` when the model refuses.
2. **Summarizer:** each map call goes through it, and a declined group is skipped. If the opening
   is declined, the summary is the list of provisions alone. If nothing is left at all, it throws
   `Declined`.
3. **Opinion writer:** each section goes through it, and a declined source is skipped like "Not
   addressed". A declined conclusion refuses the opinion with the reason "the model declined to
   write the conclusion", given in Greek too. Cancellation is checked before each translation step.
4. **`RAGService.greekLegalOpinion`:** cancellation is checked before each document's search.
5. **Router:** `failureReason` uses `failure(of:)`, so OS 27 errors get their specific message;
   `Declined` maps to the "declined" message.
6. **Tests (`GreekLegalModelCallTests`, new):**
   - too long → shorter retry that keeps the header;
   - busy → one retry, no real wait;
   - declined summary group skipped;
   - declined opinion section skipped;
   - declined conclusion → Greek refusal;
   - Stop after the first pass → `CancellationError` with no further model call;
   - the OS 27 errors get their messages.

## Verification

- The new and existing router, summary and opinion suites; the full suite; the macOS build.
- **Summary and opinion dev sets:** they should be unchanged, since no call fails in them.
- **Mac app:** Stop during an opinion, with the time from Stop to the bar going idle.
