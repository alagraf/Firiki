//
//  DemoSmokeUITests.swift
//  FirikiUITests
//
//  Phase 2b (POC_PROGRESS.md): opt-in smoke test asking the four README prompts in the live app,
//  backed by Apple's on-device model and the library active in the app. The UI-test target supports
//  iPhone and the iPhone Simulator only (`SUPPORTED_PLATFORMS`), so it runs in the Simulator, whose
//  model answers like the Mac's; running it on "My Mac" needs macOS added to the target in
//  project.pbxproj (owner's approval). Trigger with:
//    TEST_RUNNER_OI_DEMO_SMOKE=1 xcodebuild test -scheme FirikiUITests -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:FirikiUITests/DemoSmokeUITests
//

import XCTest

final class DemoSmokeUITests: XCTestCase {
    private static let prompts: [(question: String, expectedHints: [String])] = [
        ("Πόσες ημέρες άδεια πατρότητας δικαιούται ο εργαζόμενος;", ["άρθρ", "14", "ν."]),
        // Hints are words of the answer that the prompt doesn't contain, so the user's own message
        // on screen can't satisfy them (review, 15 Nov 2026).
        ("Συνόψισε το ν. 5278/2026", ["Σύνοψη", "Κύριες διατάξεις"]),
        (
            "Ο εργοδότης ζητά από υπάλληλο πενθήμερης εργασίας να κάνει τέσσερις ώρες υπερωρία την ημέρα. Επιτρέπεται, πώς αμείβεται και μπορεί ο εργαζόμενος να αρνηθεί; Θέλω γνωμοδότηση.",
            ["Εφαρμοστέο δίκαιο", "άρθρ", "5239"]
        ),
        ("Ποιο υπόδειγμα σύμβασης ταιριάζει για τηλεργασία;", ["Υπογραφές", "Αιτιολόγηση", "Συμβαλλόμενοι"]),
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

            // Wait for the request to start (Stop appears) and then to finish (Stop goes away).
            let stop = app.buttons["stopGenerationButton"]
            XCTAssertTrue(stop.waitForExistence(timeout: 15), "Prompt \(index + 1) did not start")
            XCTAssertTrue(stop.waitForNonExistence(timeout: 240), "Prompt \(index + 1) did not finish within 240 s")

            // The answer is not always a static text (Markdown views expose it as a label or value
            // of another element), so every element's label and value is read.
            let texts = app.descendants(matching: .any).allElementsBoundByIndex
                .map { "\($0.label) \(($0.value as? String) ?? "")" }
                .joined(separator: "\n")
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
