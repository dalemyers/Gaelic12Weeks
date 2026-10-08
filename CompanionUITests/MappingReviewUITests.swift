import XCTest

final class MappingReviewUITests: XCTestCase {
    /// Opt-in failure fixture: MappingReview.json must be a directory in a dedicated simulator's app container.
    @MainActor
    func testResetWriteFailureWhenBlockedFixtureIsPresent() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        openReview(in: app)
        let error = app.alerts["Mapping review"]
        guard error.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the dedicated write-blocked MappingReview.json directory fixture.")
        }
        error.buttons["OK"].firstMatch.tap()
        let reset = app.buttons["resetMappingReview"]
        reveal(reset, in: app)
        reset.tap()
        let confirmReset = app.buttons.matching(identifier: "confirmResetMappingReview").firstMatch
        XCTAssertTrue(confirmReset.waitForExistence(timeout: 5))
        confirmReset.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 5), "A failed reset must present its error after confirmation.")
        error.buttons["OK"].firstMatch.tap()
        XCTAssertTrue(app.buttons["resetMappingReview"].exists, "The failed draft remains available for recovery.")
        app.buttons["closeMappingReview"].tap()
    }

    /// DEBUG review supports corrections, explicit confirmation, persistence and safe unsaved-change handling.
    @MainActor
    func testCorrectConfirmAndReloadMapping() {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launch()
        openReview(in: app)
        let reset = app.buttons["resetMappingReview"]
        reveal(reset, in: app)
        reset.tap()
        let confirmReset = app.buttons.matching(identifier: "confirmResetMappingReview").firstMatch
        XCTAssertTrue(confirmReset.waitForExistence(timeout: 5), app.debugDescription)
        confirmReset.tap()
        reveal(app.staticTexts["reviewProgress"], in: app, upward: false)
        XCTAssertTrue(app.staticTexts["reviewProgress"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["reviewProgress"].label.contains("0 of 150 confirmed"))

        // Reopen track 003 for review so the fully confirmed catalog still exercises automatic shifting.
        let next = app.buttons["nextReviewTrack"]
        reveal(next, in: app)
        next.tap()
        let save = app.buttons["saveReviewCorrection"]
        reveal(save, in: app)
        save.tap()
        let previous = app.buttons["previousReviewTrack"]
        reveal(previous, in: app, upward: false)
        previous.tap()

        let lesson = app.textFields["reviewLesson"]
        reveal(lesson, in: app)
        replace(lesson, with: "2")
        replace(app.textFields["reviewSection"], with: "14")
        app.buttons["finishReviewEditing"].tap()
        reveal(save, in: app)
        save.tap()
        reveal(app.staticTexts["reviewNotice"], in: app, upward: false)
        XCTAssertTrue(app.staticTexts["reviewNotice"].label.contains("002"))

        let reject = app.buttons["rejectReviewTrack"]
        reveal(reject, in: app)
        reject.tap()
        app.buttons["closeMappingReview"].tap()
        XCTAssertTrue(app.buttons["reviewMapping"].waitForExistence(timeout: 5))
        app.buttons["reviewMapping"].tap()
        XCTAssertTrue(app.staticTexts["reviewProgress"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["reviewProgress"].label.contains("1 incorrect"))
        reveal(lesson, in: app)
        XCTAssertEqual(lesson.value as? String, "2")
        XCTAssertEqual(app.textFields["reviewSection"].value as? String, "14")

        replace(lesson, with: "3")
        app.buttons["closeMappingReview"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "keepReviewEditing").firstMatch.tap()
        reveal(lesson, in: app)
        XCTAssertEqual(lesson.value as? String, "3")
        let confirm = app.buttons["confirmReviewTrack"]
        reveal(confirm, in: app)
        confirm.tap()
        reveal(app.staticTexts["reviewNotice"], in: app, upward: false)
        XCTAssertTrue(app.staticTexts["reviewNotice"].label.contains("Shifted 1 later unconfirmed recordings by +13."))
        reveal(app.textFields["reviewLesson"], in: app)
        XCTAssertEqual(app.textFields["reviewLesson"].value as? String, "1", "Confirmation advances to track 003.")
        XCTAssertEqual(app.textFields["reviewSection"].value as? String, "15")
        let export = app.buttons["exportMapping"]
        reveal(export, in: app)
        XCTAssertTrue(export.isEnabled)
        export.tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 20), app.debugDescription)
        replace(app.textFields["DOCPicker.filenameTextField"], with: "Mapping-review-\(UUID().uuidString)")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["closeMappingReview"].waitForExistence(timeout: 10))
        reveal(app.staticTexts["reviewNotice"], in: app, upward: false)
        XCTAssertEqual(app.staticTexts["reviewNotice"].label, "Export saved. No audio was included.")
        app.buttons["closeMappingReview"].tap()
        app.buttons["Done"].tap()

        app.terminate()
        app.launch()
        openReview(in: app)
        XCTAssertTrue(app.staticTexts["reviewProgress"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["reviewProgress"].label.contains("1 of 150 confirmed; 0 incorrect"))
        reveal(lesson, in: app)
        replace(lesson, with: "4")
        app.buttons["closeMappingReview"].tap()
        let discard = app.buttons.matching(identifier: "discardReviewChanges").firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(app.buttons["reviewMapping"].waitForExistence(timeout: 5))
    }

    /// Finds the DEBUG entry point in About without depending on a particular screen size.
    @MainActor
    private func openReview(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["aboutAudio"].waitForExistence(timeout: 10))
        app.buttons["aboutAudio"].tap()
        let review = app.buttons["reviewMapping"]
        reveal(review, in: app)
        review.tap()
    }

    /// Scrolls until a required form control is interactable, failing rather than hiding missing controls.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        let form = app.collectionViews["reviewForm"]
        for _ in 0..<8 {
            let player = app.otherElements.matching(identifier: "miniPlayer").allElementsBoundByIndex.last
            let visibleBottom = player?.frame.minY ?? app.frame.maxY
            if element.exists && element.isHittable && element.frame.maxY < visibleBottom { return }
            let scrollView = form.exists ? form : app
            if upward { scrollView.swipeUp() } else { scrollView.swipeDown() }
        }
        XCTFail("The requested control did not become reachable above the mini-player: \(element)")
    }

    /// Replaces a numeric field's existing value instead of appending to it.
    @MainActor
    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }
}
