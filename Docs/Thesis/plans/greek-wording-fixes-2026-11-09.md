# Plan: remaining Greek wording fixes in opinions, summaries and templates (9 Nov 2026)

Approved by the owner. Continues the 9 Nov 2026 entry in `Docs/Thesis/FORK_CHANGES.md` (read it
first; it lists what was already changed and why). Those changes were made without a Swift
toolchain: the app was rebuilt in Xcode, but **the unit tests have never been run**.

## 0. First: run the tests of the earlier change
- `GreekLegalOpinionTests` (new: `greekWordingIsWrittenByTheProgramAndRepaired`,
  `theConclusionDoesNotRestateTheLinks`, `aQuarterIsThreeMonthsBeforeTranslation`; changed:
  `sectionsAreCheckedAndTheOpinionIsInGreekSections`), plus `GreekLegalSummaryTests` and
  `GreekLegalChatRouterTests`. Build and test commands are in `AGENTS.md`. Fix any failure before
  going on.

## 1. Statute summary (`Services/Legal/GreekLegalDocumentSummarizer.swift`)
Test input: `thesis/demo/poc_pdfs/n_5278_2026_excerpt.pdf` (library «Σύνοψη νόμου»), chat request
«Σύνοψε το ν. 5278/2026».
- «Το καταστατικό αυτό …»: the overview prompt (around line 252) says "statute", and Opus-MT renders
  "This statute" as «καταστατικό» (articles of association). Use "law" in the prompt, and/or map
  "statute" → "law" in `LocalNeuralTranslator.legalEnglishPreEdited`. Expected: «Ο νόμος αυτός …».
- «λεπτού του ψηφοδελτίου»: "minutes" (of a meeting/vote) came back as minutes of time. Expected
  «πρακτικά». Find the English source sentence in the Response Details card first.
- The Article 7 entry ends in «στην …»: a note line is cut with "…" (around line 209). Cut at a
  sentence or clause end instead, or allow a longer line.

## 2. Cross-statute opinion (`Services/Legal/GreekLegalOpinionWriter.swift`)
Library «Γνωμοδότηση» (n_5239 art7, pd_62 art194, ya_8934_2026_decision.pdf; delete the two empty
ya_8934 copies with 0 passages from the library first).
- Two-document question (already correct; keep it correct):
  «Θέλω γνωμοδότηση: ο εργοδότης ζητά από εργαζόμενο να κάνει τέσσερις ώρες υπερωρία την ημέρα.
  Επιτρέπεται, πώς αμείβεται και μπορεί ο εργαζόμενος να αρνηθεί;»
  One loose phrase remains: «ισχύουν για τους εργαζόμενους που υπόκεινται στις … διατάξεις».
- Three-document question: «Θέλω γνωμοδότηση: πόσος είναι ο νομοθετημένος κατώτατος μισθός και πώς
  αμείβονται οι υπερωρίες …». It uses all three enactments, but:
  - it omits the €920 minimum wage from Υ.Α. 8934/2026 (check retrieval of the decision's passages
    and whether the figure survives drafting, verification and translation);
  - «υπό Article 141Α»: an English article anchor left untranslated;
  - «τους εργαζόμενους και τους εργαζόμενους»: duplicated phrase;
  - «νομικές υπερωρίες» (should be «νόμιμες υπερωρίες»);
  - «καταβεβλημένο καταβαλλόμενο ωρομίσθιο»: `repairedGreek` replaced only part of the phrase;
    extend the pattern so a preceding participle is absorbed.
- Add each repair as a unit test in `GreekLegalOpinionTests`, using the Greek strings above.

## 3. Template router (`Services/Legal/LabourContractTemplateRouter.swift`)
Chat request: «Ποιο υπόδειγμα σύμβασης ταιριάζει για τηλεργασία;» (or the part-time, home-based
arrangement in the thesis figure).
- The model's one-sentence `reason` is shown in English in a Greek answer: translate it, or show a
  Greek sentence built from the chosen template's title.
- The template shows an unfilled `{{place_of_signing}}`: leave a visible blank («………») like the other
  fields, or fill it when the request names a place.

## 4. Lower priority
- A question about German law was once not refused; `unsupportedForeignJurisdiction` in
  `Services/RAG/Safety/GreekLegalAnswerService.swift` covers this. Reproduce it before changing anything.

## Done when
- All tests pass, including new ones for every repair.
- The owner has rebuilt the Mac app and the summary and both opinions read correctly in Greek.
- `FORK_CHANGES.md` has a new dated entry.
- If the owner wants new thesis screenshots (Figs. 6.5–6.7, `Apple_Intelligence_for_the_Legal_Industry/figures/firiki_*.png`), they replace the old ones at the same size. The opinion and summary results in Chapter 6 (Table 6.6) were measured before these wording changes. Re-run the opinion and summary suites only if the owner asks.

## Status (9 Nov 2026)
- Steps 0–4 done; tests: `Test run with 119 tests in 20 suites passed`, `** TEST SUCCEEDED **`; Mac build
  `** BUILD SUCCEEDED **` (`/private/tmp/oi-build-mac`). Recorded in `FORK_CHANGES.md` (9 Nov 2026,
  second entry), `CHANGELOG.md` 5.7 and `METHODS_SUMMARY.md`.
- Checked in the Mac app: summary wording, both opinions (the €920 and €41.09 now kept), the Greek
  template reason and «Στ………», the German-law question refused.
- New `firiki_summary.png`, `firiki_opinion.png` and `firiki_template.png` taken from the final build
  (1568 px wide, sharper than before; the LaTeX sets widths relative to the line, captions unchanged;
  old figures kept in `figures/old_2026-11-09/`). Not compiled: no TeX toolchain on this Mac.
- Open:
  - υπάλληλοι and εργατοτεχνίτες both come out «εργαζόμενοι»;
  - the summary's opening (model content) speaks of appointing a court secretary;
  - two empty ya_8934 copies in the owner's library (not deleted);
  - Table 6.6 suites not re-run (measured before these wording changes).
