//
//  GreekTextLayerCheckTests.swift
//  FirikiTests
//
//  Thesis fork (2026-11-13). A Greek text layer is checked against PaddleOCR's reading of the same page, since
//  Vision reads no Greek. A PDF whose Greek font maps to the wrong letters («Η σχέση εξαρτημένης εργασίας» stored
//  as «Ζ ζρέζε εμαξηεκέλεο εξγαζίαο») was kept unchecked and every question about it was refused. These pin the
//  word comparison the check uses.
//

import XCTest

@testable import FirikiEngine

final class GreekTextLayerCheckTests: XCTestCase {
    private let page = """
        Άρθρο 12. Ο εργοδότης οφείλει να καταβάλλει στον εργαζόμενο αμοιβή για κάθε ώρα υπερωριακής απασχόλησης. \
        Η υπερωρία επιτρέπεται μόνο όταν το ζητήσει ο εργοδότης και καταχωρίζεται στο ψηφιακό σύστημα πριν αρχίσει.
        """

    func testACorrectLayerMatchesPaddleOCRDespiteAccentsAndLookalikes() throws {
        // OCR's usual slips: accents lost, capitals, final sigma read as sigma, Latin letters that look Greek.
        let ocr = """
            APΘPO 12. O εργοδοτης οφειλει να καταβαλλει στον εργαζομενο αμοιβη για καθε ωρα υπερωριακησ απασχολησης. \
            Η υπερωρια επιτρεπεται μονο οταν το ζητησει ο εργοδοτης και καταχωριζεται στο ψηφιακο συστημα πριν αρχισει.
            """
        let jaccard = try XCTUnwrap(DocumentProcessor.greekWordJaccard(ocr: ocr, textLayer: page))
        XCTAssertGreaterThan(jaccard, 0.8)
        XCTAssertGreaterThanOrEqual(jaccard, DocumentProcessor.greekTextLayerMinimumJaccard)
    }

    func testALayerWhoseFontMapsToTheWrongLettersIsGarbled() throws {
        let ocr = "Η σχέση εξαρτημένης εργασίας είναι μία διαρκής ενοχική σχέση"
        let layer = "Ζ ζρέζε εμαξηεκέλεο εξγαζίαο είλαη κία δηαξθήο ελνρηθή ζρέζε"
        let jaccard = try XCTUnwrap(DocumentProcessor.greekWordJaccard(ocr: ocr, textLayer: layer))
        XCTAssertLessThan(jaccard, DocumentProcessor.greekTextLayerMinimumJaccard)
    }

    func testNoWordsMeansNoVerdict() {
        XCTAssertNil(DocumentProcessor.greekWordJaccard(ocr: "", textLayer: page))
        XCTAssertNil(DocumentProcessor.greekWordJaccard(ocr: page, textLayer: "12 - 3"))
    }
}
