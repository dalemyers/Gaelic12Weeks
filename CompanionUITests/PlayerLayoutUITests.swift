import XCTest

final class PlayerLayoutUITests: XCTestCase {
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
        revealAbovePlayer(reading, scrolling: libraryList, in: app)
        reading.tap()
        let groupList = app.collectionViews["groupList"]
        revealAbovePlayer(app.buttons["track-151"], scrolling: groupList, in: app)
        goBack(in: app)

        let lesson = app.buttons["lesson-6"]
        revealAbovePlayer(lesson, scrolling: libraryList, in: app, upward: false)
        lesson.tap()
        revealAbovePlayer(app.buttons["track-85"], scrolling: groupList, in: app)
        goBack(in: app)

        let precedingLesson = app.buttons["lesson-5"]
        revealAbovePlayer(precedingLesson, scrolling: libraryList, in: app, upward: false)
        precedingLesson.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let lastTrack = app.buttons["track-66"]
        revealAbovePlayer(lastTrack, scrolling: groupList, in: app)
        lastTrack.tap()
        let toggle = app.buttons["togglePlayback"]
        expectation(for: NSPredicate(format: "label == 'Pause' AND enabled == true"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
        toggle.tap()
        XCTAssertEqual(toggle.label, "Play")
        XCTAssertTrue(app.navigationBars["Lesson 5"].exists)
        revealAbovePlayer(lastTrack, scrolling: groupList, in: app)

        goBack(in: app)
        XCUIDevice.shared.orientation = .portrait
        assertAboutBottomIsReachable(in: app)
    }

    /// Checks actual geometry rather than isHittable alone, which can report controls hidden beneath overlays.
    @MainActor
    private func revealAbovePlayer(
        _ element: XCUIElement, scrolling scrollView: XCUIElement, in app: XCUIApplication, upward: Bool = true
    ) {
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            let players = app.otherElements.matching(identifier: "miniPlayer").allElementsBoundByIndex
            guard let player = players.last else {
                XCTFail("The persistent player is missing.")
                return
            }
            let navigationBar = app.navigationBars.allElementsBoundByIndex.last
            let top = max(scrollView.frame.minY, navigationBar?.frame.maxY ?? scrollView.frame.minY)
            let bottom = min(scrollView.frame.maxY, player.frame.minY)
            if element.exists {
                let frame = element.frame
                if element.isHittable && frame.minY >= top && frame.maxY <= bottom {
                    XCTAssertLessThanOrEqual(frame.maxY, player.frame.minY)
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
        XCTFail("Bottom content cannot scroll fully above the player: \(element.debugDescription)")
    }

    /// Uses the active navigation stack's back button without changing the shared player.
    @MainActor
    private func goBack(in app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["togglePlayback"].isHittable)
    }

    /// Measures the last About action without activating its destructive confirmation.
    @MainActor
    private func assertAboutBottomIsReachable(in app: XCUIApplication) {
        app.buttons["aboutAudio"].tap()
        XCTAssertTrue(app.navigationBars["About & download"].waitForExistence(timeout: 5))
        revealAbovePlayer(
            app.buttons["Reset all listening progress"], scrolling: app.scrollViews["aboutScroll"], in: app
        )
        app.buttons["Done"].tap()
    }
}
