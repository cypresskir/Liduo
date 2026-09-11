import AppKit
import MetalKit
import Carbon
import ServiceManagement
import AVFoundation

@MainActor final class AppController {
    static let shared = AppController()
    let model = AppModel()
    let updater = AppUpdater()
    let sensor = LidSensor()
    let capture = DesktopCapture()
    private var overlay: NSPanel?
    private var metalView: MTKView?
    private var renderer: FoldRenderer?
    private let effectCursor = EffectCursor()
    private var captureTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var overlayHideTask: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var permissionTimer: Timer?
    private var diagnosticsTimer: Timer?
    private var diagnosticsURL: URL?
    private var hotKey: GlobalHotKey?
    private var observers: [NSObjectProtocol] = []
    private var cycle = OpenCycle()
    private var demoProgress = 0.0
    private var demoRestoreEnabled: Bool?
    private var systemAsleep = false
    private var screenAsleep = false
    private var screenLocked = false
    private var started = false
    private var generation = 0
    private var failedCapture = false
    private var stoppingCapture = false
    private var lastMovementTime = 0.0
    private var idleTask: Task<Void, Never>?
    private var soundPlayer: AVAudioPlayer?

    var effectProgress: Double {
        if model.demoActive { return demoProgress }
        guard model.preferences.enabled, !model.suspended,
              let angle = model.lidMotion.angle(at: CACurrentMediaTime()) else { return 0 }
        return FoldMath.progress(angle: angle, clearAngle: model.preferences.clearAngle)
    }

    private var measuredProgress: Double {
        if model.demoActive { return demoProgress }
        guard model.preferences.enabled, !model.suspended, let angle = model.angle else { return 0 }
        return FoldMath.progress(angle: angle, clearAngle: model.preferences.clearAngle)
    }

    func start() {
        guard !started, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        started = true
        updater.start()
        model.permissionGranted = CGPreflightScreenCaptureAccess()
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        if let renderError = RenderResources.shared.error { model.error = renderError }
        sensor.onSample = { [weak self] sample in
            guard let self else { return }
            self.model.lidMotion.update(sample)
            self.model.angle = sample.degrees
            self.lastMovementTime = sample.timestamp
            self.idleTask?.cancel()
            self.idleTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                self?.reconcile()
            }
            let progress = self.measuredProgress
            let opened = self.cycle.update(progress: progress)
            if opened, self.model.preferences.sound, self.model.preferences.enabled,
               self.model.overlayVisible, !self.model.demoActive { self.playOpenSound() }
            self.reconcile()
        }
        sensor.onStatus = { [weak self] available, detail in
            guard let self else { return }
            self.model.sensorAvailable = available
            self.model.sensorDetail = detail
            if !available { self.model.angle = nil; self.model.lidMotion = LidMotion(); self.reconcile() }
        }
        model.onPreferencesChanged = { [weak self] in
            guard let self else { return }
            if !self.model.preferences.enabled {
                self.stopDemo(restore: false)
                self.sensor.stop()
                self.model.lidMotion = LidMotion()
                self.cycle.reset()
                self.stopCapture()
            } else if !self.model.suspended { self.sensor.start() }
            self.reconcile()
        }
        if model.preferences.enabled { sensor.start() }
        hotKey = GlobalHotKey { [weak self] in self?.toggleEnabled() }
        model.hotKeyError = hotKey?.error
        observeLifecycle()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermission() }
        }
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--diagnostics"), args.indices.contains(index + 1) {
            diagnosticsURL = URL(fileURLWithPath: args[index + 1])
            diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.writeDiagnostics() }
            }
        }
        reconcile()
    }

    func toggleEnabled() {
        if model.demoActive { stopDemo(); return }
        model.preferences.enabled.toggle()
    }

    func retry() {
        model.error = RenderResources.shared.error
        failedCapture = false
        sensor.stop()
        model.lidMotion = LidMotion()
        if model.preferences.enabled, !model.suspended { sensor.start() }
        refreshPermission()
        reconcile()
    }

    func requestScreenPermission() {
        if !CGRequestScreenCaptureAccess() { openPrivacySettings() }
        refreshPermission()
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            model.launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled, SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { model.error = "Не удалось изменить автозапуск: \(error.localizedDescription)" }
    }

    func startDemo() {
        guard model.permissionGranted, !model.suspended, !model.demoActive else { return }
        model.error = nil; failedCapture = false
        demoRestoreEnabled = model.preferences.enabled
        if !model.preferences.enabled { model.preferences.enabled = true }
        model.demoActive = true; demoProgress = 0
        reconcile()
        demoTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<100 {
                if self.model.capturing { break }
                try? await Task.sleep(for: .milliseconds(30))
                if Task.isCancelled { return }
            }
            guard self.model.capturing else { self.stopDemo(); return }
            let start = CACurrentMediaTime()
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - start
                if elapsed >= 5.0 { break }
                self.demoProgress = pow(sin(elapsed / 5 * .pi), 2) * 0.83
                self.reconcile()
                try? await Task.sleep(for: .milliseconds(16))
            }
            if !Task.isCancelled { self.stopDemo() }
        }
    }

    func stopDemo(restore: Bool = true) {
        demoTask?.cancel(); demoTask = nil
        guard model.demoActive else { return }
        let enabled = demoRestoreEnabled
        demoRestoreEnabled = nil
        model.demoActive = false; demoProgress = 0
        cycle.reset()
        hideOverlay()
        if restore, let enabled, enabled != model.preferences.enabled { model.preferences.enabled = enabled }
        reconcile()
    }

    private func refreshPermission() {
        let permission = CGPreflightScreenCaptureAccess()
        guard model.permissionGranted != permission else { return }
        model.permissionGranted = permission
        if permission { model.error = nil; failedCapture = false }
        else { stopDemo(); stopCapture() }
        reconcile()
    }

    private func reconcile() {
        guard started else { return }
        let progress = measuredProgress
        let recentlyMoved = CACurrentMediaTime() - lastMovementTime < 0.85
        let shouldCapture = (progress > 0 || model.demoActive || recentlyMoved) && FoldMath.shouldCapture(angle: model.angle, clearAngle: model.preferences.clearAngle,
            enabled: model.preferences.enabled, permitted: model.permissionGranted,
            suspended: model.suspended || DesktopCapture.builtInScreen == nil, demo: model.demoActive)
        guard shouldCapture, !failedCapture, RenderResources.shared.error == nil else {
            if model.capturing || captureTask != nil {
                if !model.preferences.enabled || !model.permissionGranted || model.suspended || (model.angle ?? 123) <= 5 || failedCapture {
                    stopCapture()
                } else if settleTask == nil {
                    settleTask = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled, let self else { return }
                        self.stopCapture()
                        self.settleTask = nil
                    }
                }
            }
            return
        }
        settleTask?.cancel(); settleTask = nil
        if !model.capturing, captureTask == nil { startCapture() }
        if model.capturing, progress > 0.001, capture.mailbox.latest() != nil {
            overlayHideTask?.cancel(); overlayHideTask = nil
            showOverlay()
            renderer?.invalidate()
        } else if model.capturing, progress <= 0.001, model.overlayVisible, overlayHideTask == nil {
            overlayHideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.overlayHideTask = nil
                if self.measuredProgress <= 0.001 { self.hideOverlay() }
            }
        }
    }

    private func startCapture() {
        generation += 1
        let token = generation
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.capture.start { [weak self] message in
                    guard let self, self.generation == token else { return }
                    self.captureFailed(message)
                }
                for _ in 0..<100 {
                    try Task.checkCancellation()
                    if self.capture.mailbox.latest() != nil { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                try Task.checkCancellation()
                guard self.generation == token else { return }
                guard self.capture.mailbox.latest() != nil else { throw CaptureError.noFrame }
                self.model.capturing = true
                self.captureTask = nil
                self.reconcile()
            } catch is CancellationError {
                return
            } catch {
                guard self.generation == token else { return }
                self.captureTask = nil
                self.captureFailed(error.localizedDescription)
            }
        }
    }

    private func captureFailed(_ message: String) {
        failedCapture = true
        model.error = "Не удалось показать рабочий стол: \(message)"
        stopDemo()
        stopCapture()
    }

    private func stopCapture() {
        guard !stoppingCapture else { return }
        stoppingCapture = true
        generation += 1
        settleTask?.cancel(); settleTask = nil
        let pending = captureTask
        pending?.cancel()
        hideOverlay()
        model.capturing = false
        captureTask = Task { [weak self] in
            await pending?.value
            guard let self else { return }
            await self.capture.stop()
            self.renderer?.reset()
            self.captureTask = nil
            self.stoppingCapture = false
            self.reconcile()
        }
    }

    private func showOverlay() {
        guard let screen = DesktopCapture.builtInScreen else { return }
        if overlay == nil {
            let renderer = FoldRenderer(mailbox: capture.mailbox) { [weak self] in
                guard let self else { return RenderParameters(progress: 0, preferences: Preferences(), overlay: true, reducedMotion: false) }
                return RenderParameters(progress: self.effectProgress, preferences: self.model.preferences,
                    overlay: true, reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
            let view = renderer.makeView()
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.contentView = view
            panel.isReleasedWhenClosed = false
            panel.title = "Liduo Effect"
            self.renderer = renderer; self.metalView = view; self.overlay = panel
        }
        if overlay?.frame != screen.frame { overlay?.setFrame(screen.frame, display: true) }
        if !model.overlayVisible {
            effectCursor.start(on: screen.frame)
            metalView?.isPaused = false
            overlay?.orderFrontRegardless()
            model.overlayVisible = true
        }
    }

    private func hideOverlay() {
        overlayHideTask?.cancel(); overlayHideTask = nil
        overlay?.orderOut(nil)
        metalView?.isPaused = true
        model.overlayVisible = false
        effectCursor.stop()
    }

    private func observeLifecycle() {
        func watch(_ center: NotificationCenter, _ name: Notification.Name,
                   _ action: @escaping @MainActor @Sendable () -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { action() }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        watch(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.systemAsleep = true; self?.updateSuspension() }
        watch(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.systemAsleep = false; self?.updateSuspension() }
        watch(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.screenAsleep = true; self?.updateSuspension() }
        watch(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.screenAsleep = false; self?.updateSuspension() }
        watch(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.screenLocked = true; self?.updateSuspension()
        }
        watch(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.screenLocked = false; self?.updateSuspension()
        }
        watch(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            guard let self else { return }
            self.stopCapture()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.reconcile()
            }
        }
        watch(.default, NSApplication.didBecomeActiveNotification) { [weak self] in self?.refreshPermission() }
        watch(.default, NSApplication.willTerminateNotification) { [weak self] in self?.hideOverlay() }
    }

    private func updateSuspension() {
        model.suspended = systemAsleep || screenAsleep || screenLocked
        if model.suspended {
            stopDemo(); stopCapture(); sensor.stop(); cycle.reset()
            model.lidMotion = LidMotion()
        } else {
            model.error = nil; failedCapture = false
            if model.preferences.enabled { sensor.start() }
            refreshPermission(); reconcile()
        }
    }

    private func playOpenSound() {
        let sampleRate = 22050.0
        let count = Int(sampleRate * 0.09)
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let envelope = min(1, t / 0.003) * exp(-t * 70)
            let wave = sin(2 * .pi * 1450 * t) + 0.25 * sin(2 * .pi * 2350 * t)
            samples[i] = Int16(wave * envelope * 1900)
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); append(UInt32(36 + count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8); append(UInt32(count * 2))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        soundPlayer = try? AVAudioPlayer(data: data)
        soundPlayer?.play()
    }

    private func writeDiagnostics() {
        guard let diagnosticsURL else { return }
        let dictionary: [String: Any] = ["angle": model.angle ?? -1, "sensor": model.sensorAvailable,
            "modelIdentifier": sensor.modelIdentifier,
            "macOSVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "sensorMode": model.sensorDetail, "permission": model.permissionGranted,
            "capturing": model.capturing, "overlayVisible": model.overlayVisible,
            "cursorHiddenByLiduo": effectCursor.hiddenByLiduo,
            "framesDrawn": renderer?.framesDrawn ?? 0,
            "captureSerial": capture.mailbox.latest()?.1 ?? 0,
            "status": model.status, "error": model.error ?? "", "hotKeyError": model.hotKeyError ?? "",
            "enabled": model.preferences.enabled, "demo": model.demoActive,
            "metalReady": RenderResources.shared.error == nil]
        if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: diagnosticsURL, options: .atomic)
        }
    }
}

@MainActor private final class GlobalHotKey {
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private(set) var error: String?
    init(action: @escaping () -> Void) {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &event, context, &handler)
        guard installed == noErr else { error = "Не удалось подключить сочетание клавиш."; return }
        let id = EventHotKeyID(signature: OSType(0x4C494455), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(cmdKey | optionKey), id,
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &key)
        if status != noErr { error = "⌘⌥B занято другой программой. Используйте меню Liduo." }
    }
}
