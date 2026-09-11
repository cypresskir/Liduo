import AppKit
import CoreGraphics
import Darwin

@MainActor final class CursorVisibility {
    private let hide: () -> Bool
    private let show: () -> Bool
    private(set) var hiddenByLiduo = false

    init(hide: @escaping () -> Bool, show: @escaping () -> Bool) {
        self.hide = hide
        self.show = show
    }

    func update(effectFrame: NSRect?, mouseLocation: NSPoint) {
        let shouldHide = effectFrame?.contains(mouseLocation) == true
        guard shouldHide != hiddenByLiduo else { return }
        if shouldHide {
            if hide() { hiddenByLiduo = true }
        } else {
            restore()
        }
    }

    func restore() {
        guard hiddenByLiduo else { return }
        if show() { hiddenByLiduo = false }
    }
}

@MainActor final class EffectCursor {
    private let backgroundAccess = BackgroundCursorAccess()
    private lazy var visibility = CursorVisibility(
        hide: { [backgroundAccess] in
            backgroundAccess.setEnabled(true)
            guard CGDisplayHideCursor(CGMainDisplayID()) == .success else {
                backgroundAccess.setEnabled(false)
                return false
            }
            return true
        },
        show: { [backgroundAccess] in
            guard CGDisplayShowCursor(CGMainDisplayID()) == .success else { return false }
            backgroundAccess.setEnabled(false)
            return true
        }
    )
    private var effectFrame: NSRect?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    var hiddenByLiduo: Bool { visibility.hiddenByLiduo }

    func start(on screenFrame: NSRect) {
        effectFrame = screenFrame
        update()
        guard activationObserver == nil else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.update() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.visibility.restore()
                self.update()
            }
        }
    }

    func stop() {
        effectFrame = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        localMonitor = nil
        globalMonitor = nil
        activationObserver = nil
        visibility.restore()
    }

    private func update() {
        visibility.update(effectFrame: effectFrame, mouseLocation: NSEvent.mouseLocation)
    }
}

// Public cursor hiding alone is foreground-only. Resolve this connection-scoped
// compatibility hook optionally; do not change focus or persist system settings.
@MainActor private final class BackgroundCursorAccess {
    private typealias Connection = @convention(c) () -> UInt32
    private typealias SetProperty = @convention(c) (UInt32, UInt32, CFString, CFTypeRef) -> Int32
    private let connection: Connection?
    private let setProperty: SetProperty?
    private var enabled = false

    init() {
        let handle = dlopen(nil, RTLD_LAZY)
        connection = dlsym(handle, "CGSMainConnectionID").map { unsafeBitCast($0, to: Connection.self) }
        setProperty = dlsym(handle, "CGSSetConnectionProperty").map { unsafeBitCast($0, to: SetProperty.self) }
        if let handle { dlclose(handle) }
    }

    func setEnabled(_ value: Bool) {
        guard value != enabled, let connection, let setProperty else { return }
        let id = connection()
        if setProperty(id, id, "SetsCursorInBackground" as CFString, value ? kCFBooleanTrue! : kCFBooleanFalse!) == 0 {
            enabled = value
        }
    }
}
