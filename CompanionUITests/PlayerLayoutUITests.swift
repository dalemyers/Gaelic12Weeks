import XCTest

final class PlayerLayoutUITests: XCTestCase {
    /// The player spans library navigation, while About has no player in either orientation.
    @MainActor
    func testPlayerUsesFullWidthBelowNavigation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launch()
        let lesson = app.buttons["lesson-1"]
        guard lesson.waitForExistence(timeout: 10) else {
            throw XCTSkip("Requires an imported lesson-1 fixture on a dedicated simulator.")
        }
        let window = app.windows.firstMatch
        assertPlayerSpansWidth(of: window, in: app)
        let about = app.buttons["aboutAudio"]
        XCTAssertTrue(about.isHittable)
        XCTAssertLessThanOrEqual(about.frame.maxY, app.otherElements["miniPlayer"].frame.minY)

        lesson.tap()
        XCTAssertTrue(app.buttons["track-2"].waitForExistence(timeout: 5))
        assertPlayerSpansWidth(of: window, in: app)
        goBack(in: app)

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            assertAboutBottomIsReachable(in: app)
        }
    }

    /// Checks player bounds and symmetric slider padding so an expanded background alone cannot pass.
    @MainActor
    private func assertPlayerSpansWidth(of container: XCUIElement, in app: XCUIApplication) {
        let players = app.otherElements.matching(identifier: "miniPlayer")
        XCTAssertTrue(players.firstMatch.waitForExistence(timeout: 5))
        guard let player = players.allElementsBoundByIndex.last else {
            XCTFail("The persistent player is missing.")
            return
        }
        XCTAssertEqual(player.frame.minX, container.frame.minX, accuracy: 1)
        XCTAssertEqual(player.frame.maxX, container.frame.maxX, accuracy: 1)
        XCTAssertLessThanOrEqual(player.frame.maxY, app.windows.firstMatch.frame.maxY)
        guard let slider = app.sliders.matching(identifier: "playbackPosition").allElementsBoundByIndex.last else {
            XCTFail("The playback slider is missing.")
            return
        }
        XCTAssertEqual(
            slider.frame.minX - container.frame.minX,
            container.frame.maxX - slider.frame.maxX,
            accuracy: 1
        )
    }

    /// Last rows must be reachable above the persistent player, including pushed lists and a taller playing title.
    @MainActor
    func testBottomRowsStayAbovePlayer() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launch()
        guard app.buttons["lesson-1"].waitForExistence(timeout: 10) else {
            throw XCTSkip("Requires the complete synthetic library on a dedicated simulator.")
        }

        let libraryList = app.collectionViews["libraryList"]
        let reading = app.buttons["reading"]
        revealInVisibleContent(reading, scrolling: libraryList, in: app)
        reading.tap()
        let groupList = app.collectionViews["groupList"]
        revealInVisibleContent(app.buttons["track-151"], scrolling: groupList, in: app)
        goBack(in: app)

        let lesson = app.buttons["lesson-6"]
        revealInVisibleContent(lesson, scrolling: libraryList, in: app, upward: false)
        lesson.tap()
        revealInVisibleContent(app.buttons["track-85"], scrolling: groupList, in: app)
        goBack(in: app)

        let precedingLesson = app.buttons["lesson-5"]
        revealInVisibleContent(precedingLesson, scrolling: libraryList, in: app, upward: false)
        precedingLesson.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let lastTrack = app.buttons["track-66"]
        revealInVisibleContent(lastTrack, scrolling: groupList, in: app)
        lastTrack.tap()
        let toggle = app.buttons["togglePlayback"]
        expectation(for: NSPredicate(format: "label == 'Pause' AND enabled == true"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        toggle.tap()
        XCTAssertEqual(toggle.label, "Play")
        XCTAssertTrue(app.navigationBars["Lesson 5"].exists)
        revealInVisibleContent(lastTrack, scrolling: groupList, in: app)

        goBack(in: app)
        XCUIDevice.shared.orientation = .portrait
        assertAboutBottomIsReachable(in: app)
    }

    /// Checks actual geometry rather than isHittable alone, which can report controls hidden beneath overlays.
    @MainActor
    private func revealInVisibleContent(
        _ element: XCUIElement, scrolling scrollView: XCUIElement, in app: XCUIApplication,
        upward: Bool = true, abovePlayer: Bool = true
    ) {
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            var bottom = scrollView.frame.maxY
            if abovePlayer {
                let players = app.otherElements.matching(identifier: "miniPlayer").allElementsBoundByIndex
                guard let player = players.last else {
                    XCTFail("The persistent player is missing.")
                    return
                }
                bottom = min(bottom, player.frame.minY)
            }
            let navigationBar = app.navigationBars.allElementsBoundByIndex.last
            let top = max(scrollView.frame.minY, navigationBar?.frame.maxY ?? scrollView.frame.minY)
            if element.exists {
                let frame = element.frame
                if element.isHittable && frame.minY >= top && frame.maxY <= bottom {
                    XCTAssertLessThanOrEqual(frame.maxY, bottom)
                    return
                }
                if frame.minY < top {
                    scrollView.swipeDown(velocity: .slow)
                } else {
                    scrollView.swipeUp(velocity: .slow)
                }
                continue
            }
            if upward { scrollView.swipeUp() } else { scrollView.swipeDown() }
        }
        XCTFail("Bottom content cannot scroll fully into view: \(element.debugDescription)")
    }

    /// Uses the active navigation stack's back button without changing the shared player.
    @MainActor
    private func goBack(in app: XCUIApplication) {
        let back = app.descendants(matching: .any).matching(identifier: "BackButton").firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.buttons["togglePlayback"].isHittable)
    }

    /// Measures the last About action without activating its destructive confirmation.
    @MainActor
    private func assertAboutBottomIsReachable(in app: XCUIApplication) {
        app.buttons["aboutAudio"].tap()
        XCTAssertTrue(app.navigationBars["About & download"].waitForExistence(timeout: 5))
        let aboutContent = app.otherElements["aboutContent"]
        XCTAssertTrue(aboutContent.waitForExistence(timeout: 5))
        XCTAssertFalse(aboutContent.descendants(matching: .any).matching(identifier: "miniPlayer").firstMatch.exists)
        XCTAssertFalse(aboutContent.buttons["togglePlayback"].exists)
        XCTAssertFalse(aboutContent.sliders["playbackPosition"].exists)
        revealInVisibleContent(
            app.buttons["Reset all listening progress"], scrolling: app.scrollViews["aboutScroll"], in: app,
            abovePlayer: false
        )
        app.scrollViews["aboutScroll"].swipeDown(velocity: .slow)
        let done = app.descendants(matching: .any).matching(identifier: "Done").firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.otherElements["miniPlayer"].waitForExistence(timeout: 5))
    }
}
