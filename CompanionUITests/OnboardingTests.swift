import XCTest

final class OnboardingTests: XCTestCase {
    /// A normal imported library exposes the preference, keeps it across launches, and can turn it off again.
    @MainActor
    func testSkipIntroductionsSettingPersists() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        guard app.buttons["lesson-1"].waitForExistence(timeout: 10) else {
            throw XCTSkip("Requires an imported lesson-1 fixture on an isolated test simulator.")
        }
        app.buttons["aboutAudio"].tap()
        let toggle = app.switches["skipSpokenIntroductions"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["Done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["aboutAudio"].waitForExistence(timeout: 10))
        app.buttons["aboutAudio"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["Done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["aboutAudio"].waitForExistence(timeout: 10))
        app.buttons["aboutAudio"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
    }

    /// Onboarding keeps only its primary import action, including after picker cancellation and relaunch.
    @MainActor
    func testOnboardingBeforeImport() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["welcomeImport"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.links["publisherLink"].exists)
        XCTAssertTrue(app.staticTexts[
            "Unofficial Companion to \"Scottish Gaelic in Twelve Weeks\""
        ].exists)
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            assertOnboardingControls(in: app)
        }
        app.buttons["welcomeImport"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 20))
        app.buttons["Cancel"].tap()
        assertOnboardingControls(in: app)
        app.terminate()
        app.launch()
        assertOnboardingControls(in: app)
    }

    @MainActor
    func testPrivacyAndAcknowledgementsBeforeImport() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["welcomeImport"].waitForExistence(timeout: 10))
        let scroll = app.scrollViews["welcomeScroll"]
        for (identifier, title, expectedText) in [
            ("appPrivacy", "Privacy policy", "The app does not send your recordings"),
            ("appAcknowledgements", "Acknowledgements", "Thomas Zoechling")
        ] {
            let button = app.buttons[identifier]
            for _ in 0..<8 {
                if button.isHittable { break }
                scroll.swipeUp()
            }
            XCTAssertTrue(button.isHittable)
            button.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            let contents = app.staticTexts["appDocumentContents"]
            XCTAssertTrue(contents.waitForExistence(timeout: 5))
            XCTAssertTrue(contents.label.contains(expectedText))
            app.buttons["Done"].tap()
        }
        XCTAssertTrue(app.links["appSupport"].exists)
    }

    /// The import action must remain reachable without a player or redundant toolbar controls.
    @MainActor
    private func assertOnboardingControls(in app: XCUIApplication) {
        let button = app.buttons["welcomeImport"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["miniPlayer"].exists)
        XCTAssertFalse(app.buttons["togglePlayback"].exists)
        XCTAssertFalse(app.buttons["importAudio"].exists)
        XCTAssertFalse(app.buttons["aboutAudio"].exists)
        let scroll = app.scrollViews["welcomeScroll"]
        for _ in 0..<8 {
            let top = max(scroll.frame.minY, app.navigationBars.firstMatch.frame.maxY)
            let bottom = min(scroll.frame.maxY, app.frame.maxY)
            if button.isHittable && button.frame.minY >= top && button.frame.maxY <= bottom {
                XCTAssertTrue(button.isEnabled)
                return
            }
            scroll.swipeUp(velocity: .slow)
        }
        XCTFail("The onboarding import action must scroll fully into view.")
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
        XCTAssertTrue(app.buttons["aboutAudio"].exists)
        XCTAssertFalse(app.buttons["importAudio"].exists)
        app.buttons["aboutAudio"].tap()
        XCTAssertTrue(app.navigationBars["About & download"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["replaceAudio"].exists)
        XCTAssertTrue(app.otherElements.matching(identifier: "miniPlayer").allElementsBoundByIndex.last?.exists == true)
        app.buttons["Done"].tap()
        app.buttons["lesson-1"].tap()
        XCTAssertTrue(app.buttons["track-2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Lesson 1"].exists)
        XCTAssertFalse(app.buttons["section-1"].exists)
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
        XCTAssertTrue(app.buttons["lesson-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        expectation(for: playing, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        toggle.tap()
    }

    /// Main recordings and subsections share the lesson list and retain manual/playback progress.
    @MainActor
    func testInlineSectionAndSubsectionProgress() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        guard app.buttons["lesson-1"].waitForExistence(timeout: 10) else {
            throw XCTSkip("Requires the synthetic SectionLibrary fixture on an isolated test simulator.")
        }
        app.buttons["lesson-1"].tap()
        guard app.buttons["track-6"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires section 4 with its main recording and two subsection fixtures.")
        }
        XCTAssertTrue(app.navigationBars["Lesson 1"].exists)
        XCTAssertFalse(app.buttons["section-4"].exists)
        for (id, label) in [(6, "Section 4,"), (7, "Section 4a,"), (8, "Section 4b,")] {
            let track = app.buttons["track-\(id)"]
            XCTAssertTrue(track.exists)
            XCTAssertTrue(track.label.contains(label))
            XCTAssertEqual(track.value as? String, "Unlistened")
        }
        for id in [6, 7] {
            app.buttons["track-\(id)"].swipeLeft()
            app.buttons["Mark listened"].tap()
            XCTAssertEqual(app.buttons["track-\(id)"].value as? String, "Listened")
        }
        XCTAssertEqual(app.buttons["track-8"].value as? String, "Unlistened")
        app.buttons["track-8"].tap()
        let toggle = app.buttons["togglePlayback"]
        expectation(for: NSPredicate(format: "label == 'Pause' AND enabled == true"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        app.sliders["playbackPosition"].adjust(toNormalizedSliderPosition: 0.95)
        expectation(for: NSPredicate(format: "label == 'Play' AND enabled == true"), evaluatedWith: toggle)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.navigationBars["Lesson 1"].exists)
        XCTAssertEqual(app.buttons["track-8"].value as? String, "Listened")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["lesson-1"].waitForExistence(timeout: 10))
        app.buttons["lesson-1"].tap()
        XCTAssertTrue(app.buttons["track-8"].waitForExistence(timeout: 5))
        for id in [6, 7, 8] {
            XCTAssertEqual(app.buttons["track-\(id)"].value as? String, "Listened")
        }
        app.buttons["track-8"].swipeLeft()
        app.buttons["Mark unlistened"].tap()
        XCTAssertEqual(app.buttons["track-8"].value as? String, "Unlistened")
        XCTAssertEqual(app.buttons["track-6"].value as? String, "Listened")
        XCTAssertEqual(app.buttons["track-7"].value as? String, "Listened")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["lesson-1"].waitForExistence(timeout: 5))
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
