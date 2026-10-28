//
//  PDFPage+Greek.swift
//  OpenIntelligence
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
        return GreekLegalEntityMasker.containsGreek(text) ? text.precomposedStringWithCompatibilityMapping : text
    }
}
