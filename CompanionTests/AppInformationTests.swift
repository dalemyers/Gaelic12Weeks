import XCTest
@testable import GaelicCompanion

final class AppInformationTests: XCTestCase {
    func testReleaseIdentityAndBundledDocuments() throws {
        XCTAssertLessThanOrEqual(AppInformation.shortName.count, 30)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                       AppInformation.shortName)
        XCTAssertEqual(AppInformation.supportURL.absoluteString, "https://app.myers.io/gaelic_companion")
        XCTAssertEqual(AppInformation.privacyURL.absoluteString, "https://app.myers.io/gaelic_companion/privacy")
        for document in AppDocument.allCases {
            XCTAssertFalse(try document.contents().isEmpty)
        }
        let notices = try AppDocument.acknowledgements.contents()
        XCTAssertTrue(notices.contains("Copyright (c) 2017-2025 Thomas Zoechling"))
        XCTAssertTrue(notices.contains("THE SOFTWARE IS PROVIDED \"AS IS\""))
        let privacy = try AppDocument.privacy.contents()
        XCTAssertTrue(privacy.contains("Preferences and listening progress may be included in backups"))
    }

    func testAppPrivacyManifestDeclaresOnlyLocalUse() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        )
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [String])?.count, 0)
        let APIs = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let defaults = try XCTUnwrap(APIs.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        })
        XCTAssertEqual(defaults["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }
}
