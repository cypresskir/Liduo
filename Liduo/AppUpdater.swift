import AppKit
import Observation
import Sparkle

@MainActor @Observable final class AppUpdater {
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    func start() {
        guard updater == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let driver = LiduoUpdateUserDriver(hostBundle: .main, delegate: nil)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        self.updater = updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates }
            }
        ]
        do { try updater.start() }
        catch { NSApp.presentError(error) }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        updater?.checkForUpdates()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }
}

@MainActor final class LiduoUpdateUserDriver: SPUStandardUserDriver {
    override func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        super.showUpdateNotFoundWithError(Self.localizedNotice(error), acknowledgement: acknowledgement)
    }

    static func localizedNotice(_ error: Error, bundle: Bundle = .main) -> Error {
        let original = error as NSError
        guard let reason = original.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber else { return error }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let message: String
        switch reason.intValue {
        case Int(SPUNoUpdateFoundReason.onLatestVersion.rawValue):
            message = "У вас последняя версия Liduo — \(version)."
        case Int(SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue):
            message = "Установлена Liduo \(version). Эта сборка новее последнего опубликованного выпуска."
        default:
            return error
        }
        var info = original.userInfo
        info[NSLocalizedDescriptionKey] = "Обновлений нет"
        info[NSLocalizedRecoverySuggestionErrorKey] = message
        info[NSLocalizedRecoveryOptionsErrorKey] = ["Закрыть"]
        return NSError(domain: original.domain, code: original.code, userInfo: info)
    }
}
