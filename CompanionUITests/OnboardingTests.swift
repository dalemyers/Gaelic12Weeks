import XCTest

final class OnboardingTests: XCTestCase {
    /// A fresh installation instructs users to download and import, without bundling recordings.
    @MainActor
    func testOnboardingAndAbout() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["importAudio"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["welcomeImport"].exists)
        XCTAssertTrue(app.links["publisherLink"].exists)
        assertEmptyPlayer(in: app)
        app.buttons["aboutAudio"].tap()
        XCTAssertTrue(app.navigationBars["About & download"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[
            "Unofficial Companion to 'Scottish Gaelic In 12 Weeks'"
        ].exists)
        assertEmptyPlayer(in: app)
        app.buttons["Done"].tap()
        app.buttons["importAudio"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 20))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["welcomeImport"].exists)
        assertEmptyPlayer(in: app)
    }

    /// The persistent player remains visible but cannot act until a recording has been selected.
    @MainActor
    private func assertEmptyPlayer(in app: XCUIApplication) {
        XCTAssertTrue(app.otherElements["miniPlayer"].exists)
        XCTAssertTrue(app.staticTexts["Select a recording"].exists)
        for identifier in ["skipBackward", "togglePlayback", "skipForward"] {
            let control = app.buttons[identifier].firstMatch
            XCTAssertTrue(control.exists)
            XCTAssertFalse(control.isEnabled)
            XCTAssertLessThanOrEqual(control.frame.maxY, app.frame.maxY)
        }
        XCTAssertEqual(app.buttons["skipBackward"].firstMatch.label, "Back 5 seconds")
        XCTAssertEqual(app.buttons["skipForward"].firstMatch.label, "Forward 5 seconds")
    }

    /// The one-minute synthetic fixture keeps the same working player visible throughout navigation.
    @MainActor
    func testPlayerAcrossLibraryNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["importAudio"].waitForExistence(timeout: 10))
        guard app.buttons["lesson-1"].exists else {
            throw XCTSkip("Requires an imported lesson-1 fixture on an isolated test simulator.")
        }
        assertEmptyPlayer(in: app)
        app.buttons["lesson-1"].tap()
        XCTAssertTrue(app.buttons["section-1"].waitForExistence(timeout: 5))
        assertEmptyPlayer(in: app)
        app.buttons["section-1"].tap()
        XCTAssertTrue(app.buttons["track-2"].waitForExistence(timeout: 5))
        assertEmptyPlayer(in: app)
        app.buttons["track-2"].tap()
        let toggle = app.buttons["togglePlayback"]
        let playing = NSPredicate(format: "label == 'Pause' AND enabled == true")
        expectation(for: playing, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        toggle.tap()
        XCTAssertEqual(toggle.label, "Play")
        app.sliders["playbackPosition"].adjust(toNormalizedSliderPosition: 0)
        // Slider drags are pixel-based; clamp to the exact start before asserting skip distances.
        app.buttons["skipBackward"].tap()
        XCTAssertEqual(app.sliders["playbackPosition"].value as? String, "0:00 of 1:00")
        app.buttons["skipForward"].tap()
        XCTAssertEqual(app.sliders["playbackPosition"].value as? String, "0:05 of 1:00")
        app.buttons["skipBackward"].tap()
        XCTAssertEqual(app.sliders["playbackPosition"].value as? String, "0:00 of 1:00")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["section-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isHittable)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["lesson-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        expectation(for: playing, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        toggle.tap()
    }
}
