# Ready-made agent prompts

Prompts to paste into Claude Code or Antigravity. They follow the workflow in `AGENTS.md`: Claude
Code plans, Antigravity executes an approved plan, and nothing is edited before the owner approves.
Each prompt names the exact files and functions, so the agent doesn't spend tokens searching the
large files.

## 1. Plan a second OCR engine behind a setting (Claude Code)

```text
Read Docs/ai/codemap/INDEX.md and the document-ingestion-pipeline slice first.
Then read parsePageImage in Firiki/Services/Document/Processing/StructuredDocumentParser.swift,
performOCR in Firiki/Services/Document/Processing/DocumentProcessor.swift,
and validateAndCleanOCR in StructuredDocumentParser.swift. Read them by line range, not whole files.
Don't change anything yet.
Write me a plan for adding a second OCR engine (PaddleOCR's Greek model, el_PP-OCRv5_mobile_rec, run
through ONNX Runtime) next to the current Vision OCR, chosen by a setting. List every file you'd touch
and what changes in each, how validateAndCleanOCR would treat Greek text, and how we'd compare the
two engines on the same pages. Save the plan as Docs/Thesis/plans/greek-ocr.md and wait for my OK.
```

## 2. Execute an approved plan (Antigravity)

```text
Read AGENTS.md and GEMINI.md, then execute the approved plan in Docs/Thesis/plans/<name>.md.
Change only the files it lists. If anything outside the plan has to change, stop and tell me why.
When you're done, run the build and the tests named in the plan and paste their output, then
record the change in Docs/Thesis/FORK_CHANGES.md and CHANGELOG.md.
```

## 3. Plan any change (Claude Code, template)

```text
Goal: <one sentence>.
Start from Docs/ai/codemap/INDEX.md. The code I think is involved: <file> / <function>.
Don't change anything yet. Write a plan: files and line ranges you read, every file you'd change
and what changes, how you'll verify it (exact commands), and open questions. Wait for my OK.
```

## 4. Large reading job (Antigravity with Argon)

```text
Read AGENTS.md first. Using Argon, read <feature or files> and write a short map of how
<behaviour> flows through them: functions in order, with file and line ranges. Don't change
anything. Save it as Docs/Thesis/notes/<name>.md.
```
