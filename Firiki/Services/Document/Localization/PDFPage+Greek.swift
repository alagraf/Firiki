//
//  PDFPage+Greek.swift
//  Firiki
//
//  Thesis fork, plan stage 2: PDFKit returns some Greek PDFs' mu as the micro sign (U+00B5) and
//  other compatibility characters. Text with Greek in it is NFKC-normalized as it leaves PDFKit,
//  so every later stage (chunking, entity masking, translation, FTS5) sees canonical Greek.
//

import PDFKit

extension PDFPage {
    /// `string`, NFKC-normalized when it contains Greek letters; unchanged otherwise, so English
    /// documents keep superscripts and fractions exactly as before.
    nonisolated var normalizedString: String? {
        guard let text = string else { return nil }
        return Self.normalized(text, pageHasGreek: GreekLegalEntityMasker.containsGreek(text))
    }

    /// Thesis fork (2.11.27): the normalization `normalizedString` applies, for a piece of the raw
    /// `string`. Code that hands ranges to `selection(for:)` must find them in the raw `string` and
    /// normalize only the text it keeps: the ranges count UTF-16 units of the raw string, and NFKC
    /// changes lengths (the Greek keraia U+0384, as in "ΚΕΦΑΛΑΙΟ Α΄", becomes a space and a
    /// combining accent), so a range found in `normalizedString` selects text further on.
    nonisolated static func normalized(_ text: String, pageHasGreek: Bool) -> String {
        pageHasGreek ? text.precomposedStringWithCompatibilityMapping : text
    }
}
