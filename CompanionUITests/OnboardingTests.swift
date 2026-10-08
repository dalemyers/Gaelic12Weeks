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
        guard app.buttons["lesson-1"].waitForExistence(timeout: 10) else {
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

    /// A section follows child progress from both manual marks and playback, including reload and undo.
    @MainActor
    func testSectionListenedStatusFollowsChildren() throws {
        let app = XCUIApplication()
        app.launch()
        guard app.buttons["lesson-1"].waitForExistence(timeout: 10) else {
            throw XCTSkip("Requires the synthetic SectionLibrary fixture on an isolated test simulator.")
        }
        app.buttons["lesson-1"].tap()
        guard app.buttons["section-4"].exists else {
            throw XCTSkip("Requires section 4 with its main recording and two subsection fixtures.")
        }
        let section = app.buttons["section-4"]
        XCTAssertEqual(section.value as? String, "Unlistened")
        section.tap()
        for id in [6, 7] {
            app.buttons["track-\(id)"].swipeLeft()
            app.buttons["Mark listened"].tap()
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        XCTAssertEqual(section.value as? String, "Unlistened")
        section.tap()
        app.buttons["track-8"].tap()
        let toggle = app.buttons["togglePlayback"]
        expectation(for: NSPredicate(format: "label == 'Pause' AND enabled == true"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        app.sliders["playbackPosition"].adjust(toNormalizedSliderPosition: 0.95)
        expectation(for: NSPredicate(format: "label == 'Play' AND enabled == true"), evaluatedWith: toggle)
        waitForExpectations(timeout: 15)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        XCTAssertEqual(section.value as? String, "Listened")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["lesson-1"].waitForExistence(timeout: 10))
        app.buttons["lesson-1"].tap()
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        XCTAssertEqual(section.value as? String, "Listened")
        section.tap()
        app.buttons["track-8"].swipeLeft()
        app.buttons["Mark unlistened"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        XCTAssertEqual(section.value as? String, "Unlistened")
    }

    /// Imported libraries omit the permanent banner and keep safe replacement available only from About.
    @MainActor
    func testLibraryReplacementLivesInAbout() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        guard app.buttons["lesson-1"].waitForExistence(timeout: 10) else {
            throw XCTSkip("Requires an imported lesson-1 fixture on an isolated test simulator.")
        }
        XCTAssertFalse(app.buttons["importAudio"].exists)
        XCTAssertFalse(app.buttons["replaceAudio"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'recordings imported'")).firstMatch.exists)

        for chooseZIP in [false, true] {
            app.buttons["aboutAudio"].tap()
            let replacement = app.buttons["replaceAudio"]
            XCTAssertTrue(replacement.waitForExistence(timeout: 5))
            let scroll = app.scrollViews["aboutScroll"]
            for _ in 0..<6 {
                if replacement.isHittable { break }
                scroll.swipeUp()
            }
            replacement.tap()
            let choose = app.buttons["Choose replacement ZIP"]
            XCTAssertTrue(choose.waitForExistence(timeout: 5))
            if chooseZIP {
                choose.tap()
                XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 20))
                app.buttons["Cancel"].tap()
            } else if app.buttons["Cancel"].exists {
                app.buttons["Cancel"].tap()
            } else {
                // Popover confirmations dismiss outside their bounds rather than offering Cancel.
                let navigationBar = app.navigationBars["Gaelic Companion"]
                XCTAssertTrue(navigationBar.exists)
                let frame = navigationBar.frame
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            }
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: choose)
            waitForExpectations(timeout: 5)
            XCTAssertTrue(app.buttons["lesson-1"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["importAudio"].exists)
        }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["lesson-1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["importAudio"].exists)
    }
}
