import XCTest
@testable import Firiki

/// Tests that isolated statute paragraph numbers (such as `"4. ..."`) and legal references
/// (`"... παρ. 4. ..."`) stay normal paragraphs rather than rendering as numbered-list badges,
/// while genuine inline and multi-line ordered lists keep `.numberedList`.
final class MarkdownRendererNumberedListTests: XCTestCase {

    func testIsolatedStatuteParagraphRemainsParagraph() {
        let input = """
        **Άρθρο 8:** Οι κανονιστικοί όροι εξακολουθούν να ισχύουν για τρεις μήνες.

        4. Μετά τη λήξη του τριμήνου εξακολουθούν να ισχύουν όλοι οι κανονιστικοί όροι.
        """
        let blocks = MarkdownParserTesting.parseBlockKinds(input)
        XCTAssertEqual(blocks, [
            .paragraph("**Άρθρο 8:** Οι κανονιστικοί όροι εξακολουθούν να ισχύουν για τρεις μήνες."),
            .paragraph("4. Μετά τη λήξη του τριμήνου εξακολουθούν να ισχύουν όλοι οι κανονιστικοί όροι."),
        ])
    }

    func testInlineStatuteReferenceNotSplitIntoNumberedList() {
        let input = "**Άρθρο 8:** Εφαρμόζεται κατά τα οριζόμενα στην παρ. 4. **Εξαίρεση:** καμία δεν ισχύει."
        let blocks = MarkdownParserTesting.parseBlockKinds(input)
        XCTAssertEqual(blocks, [.paragraph(input)])
    }

    func testInlineStatuteParagraphAfterPeriodNotSplitIntoBadge() {
        let input = "**Άρθρο 8:** Οι όροι ισχύουν για τρεις μήνες. 4. Μετά το τρίμηνο παραμένουν σε ισχύ."
        let blocks = MarkdownParserTesting.parseBlockKinds(input)
        XCTAssertEqual(blocks, [.paragraph(input)])
    }

    func testInlineAndMultilineOrderedListsRemainNumberedLists() {
        let inline = "Χαρακτηριστικά: 1. **Πρώτο** στοιχείο. 2. **Δεύτερο** στοιχείο."
        XCTAssertEqual(MarkdownParserTesting.parseBlockKinds(inline), [
            .paragraph("Χαρακτηριστικά:"),
            .numberedList([1, 2], ["**Πρώτο** στοιχείο.", "**Δεύτερο** στοιχείο."]),
        ])

        let multiline = """
        1. Πρώτο
        2. Δεύτερο
        3. Τρίτο
        """
        XCTAssertEqual(MarkdownParserTesting.parseBlockKinds(multiline), [
            .numberedList([1, 2, 3], ["Πρώτο", "Δεύτερο", "Τρίτο"]),
        ])

        let continuation = """
        4. Τέταρτη παράγραφος
        5. Πέμπτη παράγραφος
        """
        XCTAssertEqual(MarkdownParserTesting.parseBlockKinds(continuation), [
            .numberedList([4, 5], ["Τέταρτη παράγραφος", "Πέμπτη παράγραφος"]),
        ])
    }
}
