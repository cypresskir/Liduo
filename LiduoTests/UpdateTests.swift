import XCTest
import CryptoKit
import Sparkle
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

    @MainActor func testCopyChangePreservesOtherUpdateExplanations() {
        for reason in [SPUNoUpdateFoundReason.unknown, .onNewerThanLatestVersion,
                       .systemIsTooOld, .systemIsTooNew, .hardwareDoesNotSupportARM64] {
            let original = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue), userInfo: [
                SPUNoUpdateFoundReasonKey: NSNumber(value: reason.rawValue),
                NSLocalizedDescriptionKey: "Обновление недоступно",
                NSLocalizedRecoverySuggestionErrorKey: "Установите совместимую версию macOS."
            ])
            XCTAssertTrue(LiduoUpdateUserDriver.localizedNotice(original) as NSError === original)
        }
    }
}
