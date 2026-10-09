import XCTest

@MainActor
final class IntroEditorUITests: XCTestCase {
    private func choose(_ path: String, using button: String, in app: XCUIApplication) {
        app.buttons[button].click()
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(path)
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
    }

    func testMarkingPlaybackWaveformAndPersistence() throws {
        continueAfterFailure = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IntroEditorUITest-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let metadata = folder.appendingPathComponent("TrackMapping.json")
        try Data("""
        {"schemaVersion":1,"tracks":[
          {"id":2,"lesson":1,"section":4,"subsection":"a","group":"lesson",
           "title":"Synthetic section title","needsReview":false},
          {"id":3,"lesson":1,"section":null,"subsection":null,"group":"lesson",
           "title":"Synthetic conversation","needsReview":false}
        ]}
        """.utf8).write(to: metadata)
        let audio = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "synthetic", withExtension: "mp3"))
        for id in [2, 3] {
            try FileManager.default.copyItem(
                at: audio, to: folder.appendingPathComponent(String(format: "123_%03d.mp3", id))
            )
        }
        let app = XCUIApplication()
        let preferencesSuite = "IntroEditorUITests-\(UUID().uuidString)"
        app.launchEnvironment["INTRO_EDITOR_TEST_PREFERENCES_SUITE"] = preferencesSuite
        defer { UserDefaults(suiteName: preferencesSuite)?.removePersistentDomain(forName: preferencesSuite) }
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["openIntroMetadata"].waitForExistence(timeout: 10))
        choose(metadata.path, using: "openIntroMetadata", in: app)
        XCTAssertTrue(app.staticTexts["introTrackTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["introTrackTitle"].value as? String, "Synthetic section title")
        choose(folder.path, using: "openIntroAudio", in: app)
        let waveform = app.descendants(matching: .any)["audioWaveform"].firstMatch
        XCTAssertTrue(waveform.waitForExistence(timeout: 10))
        let play = app.buttons["introPlayPause"]
        XCTAssertTrue(play.isEnabled)
        XCTAssertLessThan(waveform.frame.maxY, play.frame.minY)
        app.buttons["introForwardSecond"].click()
        app.buttons["introForwardFine"].click()
        XCTAssertEqual(app.staticTexts["introPlayheadTime"].value as? String, "00:01.100")
        app.buttons["introBackFine"].click()
        XCTAssertEqual(app.staticTexts["introPlayheadTime"].value as? String, "00:01.000")
        app.buttons["introForwardFine"].click()
        app.buttons["markIntroEnd"].click()
        XCTAssertTrue(
            (app.staticTexts["introStatus"].value as? String)?.contains("Saved track 2") == true,
            app.debugDescription
        )
        let data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        let rows = try XCTUnwrap(data["tracks"] as? [[String: Any]])
        XCTAssertEqual(try XCTUnwrap(rows[0]["introEndSeconds"] as? Double), 1.1, accuracy: 0.001)
        let position = app.staticTexts["introPlayheadTime"]
        let before = position.value as? String
        play.click()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (position.value as? String) != before }, object: position
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed)
        play.click()
        waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertNotEqual(position.value as? String, before)
        app.buttons["nextIntroRecording"].click()
        XCTAssertEqual(app.staticTexts["introTrackTitle"].value as? String, "Synthetic conversation")
        app.buttons["markNoIntro"].click()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["savedIntroMark"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.staticTexts["savedIntroMark"].value as? String)?.contains("00:01.100") == true)
        XCTAssertTrue(waveform.waitForExistence(timeout: 10))
        XCTAssertTrue(play.isEnabled)
        XCTAssertEqual(play.label, "Play", "Restoring locations must not start playback.")
        app.buttons["clearIntroMark"].click()
        let cleared = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        let clearedRows = try XCTUnwrap(cleared["tracks"] as? [[String: Any]])
        XCTAssertNil(clearedRows[0]["introEndSeconds"])
        XCTAssertEqual(clearedRows[1]["introEndSeconds"] as? Double, 0)
    }
}
