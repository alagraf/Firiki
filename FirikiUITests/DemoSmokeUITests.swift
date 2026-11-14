//
//  DemoSmokeUITests.swift
//  FirikiUITests
//
//  Phase 2b (POC_PROGRESS.md): opt-in macOS smoke test asking the four README prompts in a live
//  window backed by Apple Intelligence and the pre-imported labour library. Trigger with:
//    TEST_RUNNER_OI_DEMO_SMOKE=1 xcodebuild test -scheme FirikiUITests -destination 'platform=macOS' -only-testing:FirikiUITests/DemoSmokeUITests
//

import XCTest

final class DemoSmokeUITests: XCTestCase {
    private static let prompts: [(question: String, expectedHints: [String])] = [
        ("Πόσες ημέρες άδεια πατρότητας δικαιούται ο εργαζόμενος;", ["άρθρ", "14", "ν."]),
        ("Συνόψισε το ν. 5278/2026", ["5278/2026", "Άρθρ", "άρθρ"]),
        (
            "Ο εργοδότης ζητά από υπάλληλο πενθήμερης εργασίας να κάνει τέσσερις ώρες υπερωρία την ημέρα. Επιτρέπεται, πώς αμείβεται και μπορεί ο εργαζόμενος να αρνηθεί; Θέλω γνωμοδότηση.",
            ["Εφαρμοστέο δίκαιο", "άρθρ", "5239"]
        ),
        ("Ποιο υπόδειγμα σύμβασης ταιριάζει για τηλεργασία;", ["τηλεργασ", "Υπόδειγμα", "Σύμβαση"]),
    ]

    @MainActor
    func testFourReadmePromptsCompleteWithoutErrors() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OI_DEMO_SMOKE"] == "1",
            "Opt-in smoke test for 'My Mac' with Apple Intelligence and pre-imported library (set TEST_RUNNER_OI_DEMO_SMOKE=1)"
        )
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launchArguments += ["-showSiliconHUD", "NO"]
        app.launch()

        let skipOnboarding = app.buttons["I'll add my own documents"]
        if skipOnboarding.waitForExistence(timeout: 5) {
            skipOnboarding.tap()
        }

        let inputField = app.descendants(matching: .any)["chatComposerField"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 20), "Composer field not found")

        for (index, prompt) in Self.prompts.enumerated() {
            #if os(macOS)
            inputField.click()
            #else
            inputField.tap()
            #endif
            inputField.typeText(prompt.question)

            let sendButton = app.buttons["sendMessageButton"]
            XCTAssertTrue(sendButton.waitForExistence(timeout: 5) && sendButton.isEnabled, "Send button not ready for prompt \(index + 1)")
            #if os(macOS)
            sendButton.click()
            #else
            sendButton.tap()
            #endif

            // Wait for processing to finish once started (`stopGenerationButton` yields to `sendMessageButton`).
            _ = app.buttons["stopGenerationButton"].waitForExistence(timeout: 5)
            XCTAssertTrue(
                app.buttons["sendMessageButton"].waitForExistence(timeout: 240),
                "Prompt \(index + 1) did not finish within 240 s"
            )

            let texts = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n")
            XCTAssertFalse(texts.contains("Σφάλμα"), "Unexpected 'Σφάλμα' on screen after prompt \(index + 1)")
            XCTAssertFalse(texts.localizedCaseInsensitiveContains("Error:"), "Unexpected 'Error:' on screen after prompt \(index + 1)")
            let hasCitationOrMatch = prompt.expectedHints.contains { texts.localizedCaseInsensitiveContains($0) }
            XCTAssertTrue(
                hasCitationOrMatch,
                "Expected one of \(prompt.expectedHints) after prompt \(index + 1); visible text sample: \(texts.suffix(400))"
            )
        }
    }
}
