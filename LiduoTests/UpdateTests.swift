import XCTest
import CryptoKit
@testable import Liduo

final class UpdateTests: XCTestCase {
    func testUpdateTrustConfiguration() throws {
        let bundle = Bundle.main
        let key = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
        let bytes = try XCTUnwrap(Data(base64Encoded: key))
        XCTAssertEqual(bytes.count, 32)
        XCTAssertNoThrow(try Curve25519.Signing.PublicKey(rawRepresentation: bytes))
        let feed = try XCTUnwrap(URL(string: try XCTUnwrap(bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)))
        XCTAssertEqual(feed.scheme, "https")
        XCTAssertEqual(feed.host, "raw.githubusercontent.com")
        XCTAssertEqual(feed.path, "/cypresskir/Liduo/main/updates/appcast.xml")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool, true)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool, true)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUSignedFeedFailureExpirationInterval") as? Int, 0)
    }

    func testUpdatesRequireUserChoiceByDefault() {
        let bundle = Bundle.main
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool, false)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUAllowsAutomaticUpdates") as? Bool, false)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUEnableSystemProfiling") as? Bool, false)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "SUScheduledCheckInterval") as? Int, 86400)
    }

    @MainActor func testUpdaterDoesNotStartNetworkingOrPromptsInTestHost() {
        let updater = AppUpdater()
        updater.start()
        updater.checkForUpdates()
        updater.setAutomaticChecks(true)
        XCTAssertFalse(updater.canCheckForUpdates)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
    }
}
