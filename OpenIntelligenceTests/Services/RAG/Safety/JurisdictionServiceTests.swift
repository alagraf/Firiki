//
//  JurisdictionServiceTests.swift
//  OpenIntelligenceTests
//
//  The medical domain-isolation gate (in vitro / in vivo) replaced drafted answers with "DOMAIN
//  ISOLATION BREACH". The legal fork removed it. Evidence from another legal order is now used and
//  the answer carries a caveat naming it; nothing is refused.
//

import XCTest

@testable import OpenIntelligence

final class JurisdictionServiceTests: XCTestCase {
    private typealias Service = JurisdictionService

    private func passage(_ text: String, source: String = "source.pdf") -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: text, embedding: [], metadata: ChunkMetadata(chunkIndex: 0)),
            similarityScore: 0.8, rank: 0, sourceDocument: source, pageNumber: 1)
    }

    private let greekStatute = "Σύμφωνα με το άρθρο 66 του ν. 4808/2021 (ΦΕΚ Α' 101/2021), η καταγγελία πρέπει να είναι έγγραφη."
    private let greekCourt = "Η ΑΠ 1234/2022 έκρινε ότι η καταγγελία της σύμβασης εργασίας είναι άκυρη."
    private let cypriotCourt = "Το Δικαστήριο Εργατικών Διαφορών έκρινε ότι ο εργοδότης στην Κύπρο οφείλει αποζημίωση."
    private let euRuling = "Το ΔΕΕ στην υπόθεση C-55/18 ερμήνευσε την Οδηγία 2003/88/ΕΚ για τον χρόνο εργασίας."

    // MARK: - Classification

    func testGreekStatuteAndCourtAreGreek() {
        XCTAssertEqual(Service.classify(greekStatute).jurisdiction, .greece)
        XCTAssertEqual(Service.classify(greekCourt).jurisdiction, .greece)
    }

    func testCJEURulingIsEU() {
        XCTAssertEqual(Service.classify(euRuling).jurisdiction, .europeanUnion)
    }

    func testCypriotCourtIsCypriotEvenThoughItIsInGreek() {
        XCTAssertEqual(Service.classify(cypriotCourt).jurisdiction, .cyprus)
    }

    func testPlainProseIsUnknown() {
        XCTAssertEqual(Service.classify("Give the document a civil and separate report.").jurisdiction, .unknown)
        XCTAssertEqual(Service.classify("Ο εργαζόμενος ζήτησε άδεια για δύο ημέρες.").jurisdiction, .unknown)
    }

    // MARK: - Target

    func testTargetDefaultsToGreeceAndFollowsANamedForeignLaw() {
        XCTAssertEqual(Service.targetJurisdiction(for: "Ποια είναι η προθεσμία καταγγελίας;"), .greece)
        XCTAssertEqual(Service.targetJurisdiction(for: "Τι ισχύει κατά την Οδηγία 2003/88/ΕΚ;"), .greece)
        XCTAssertEqual(Service.targetJurisdiction(for: "Τι προβλέπει το κυπριακό δίκαιο για την απόλυση;"), .cyprus)
    }

    // MARK: - Caveat

    func testGreekAndEUEvidenceForAGreekQuestionCarriesNoCaveat() {
        let assessment = Service.assess(
            query: "Πότε είναι άκυρη η καταγγελία;",
            chunks: [passage(greekStatute), passage(greekCourt), passage(euRuling)]
        )
        XCTAssertNil(assessment.caveat)
        XCTAssertEqual(assessment.compatibleShare, 1.0)
    }

    func testCypriotEvidenceForAGreekQuestionCarriesAGreekCaveat() throws {
        let assessment = Service.assess(
            query: "Πότε οφείλεται αποζημίωση απόλυσης;",
            chunks: [passage(greekStatute), passage(cypriotCourt)]
        )
        XCTAssertEqual(assessment.mismatched, [.cyprus])
        XCTAssertFalse(assessment.allRecognisedEvidenceMismatched)
        let caveat = try XCTUnwrap(assessment.caveat)
        XCTAssertTrue(caveat.hasPrefix("Σημείωση: Μέρος των διαθέσιμων πηγών αφορά το κυπριακό δίκαιο"))
        XCTAssertTrue(caveat.contains("ερμηνευτικό βοήθημα"))
    }

    func testEnglishQuestionGetsAnEnglishCaveat() throws {
        let assessment = Service.assess(
            query: "When is severance pay owed?",
            chunks: [passage(cypriotCourt)]
        )
        XCTAssertTrue(assessment.allRecognisedEvidenceMismatched)
        let caveat = try XCTUnwrap(assessment.caveat)
        XCTAssertTrue(caveat.hasPrefix("Note: The available sources concern Cypriot law, while your question concerns Greek law."))
    }

    func testUnknownEvidenceNeverTriggersACaveat() {
        let assessment = Service.assess(
            query: "Πότε οφείλεται αποζημίωση;",
            chunks: [passage("Ο εργαζόμενος ζήτησε άδεια για δύο ημέρες.")]
        )
        XCTAssertNil(assessment.caveat)
    }

    func testCaveatIsAppliedOnce() {
        let once = Service.applyingCaveat("Note: x", to: "Answer.")
        XCTAssertEqual(once, "*Note: x*\n\nAnswer.")
        XCTAssertEqual(Service.applyingCaveat("Note: x", to: once), once)
    }
}
