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
        app.buttons["aboutAudio"].tap()
        XCTAssertTrue(app.navigationBars["About & download"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[
            "Unofficial Companion to 'Scottish Gaelic In 12 Weeks'"
        ].exists)
        app.buttons["Done"].tap()
        app.buttons["importAudio"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["welcomeImport"].exists)
    }
}
