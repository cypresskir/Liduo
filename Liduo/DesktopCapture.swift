import AppKit
import ScreenCaptureKit
import CoreVideo

final class FrameMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var pixelBuffer: CVPixelBuffer?
    private var serial: UInt64 = 0
    private var onFrame: (@Sendable () -> Void)?
    func setFrameHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock(); defer { lock.unlock() }
        onFrame = handler
    }
    func put(_ buffer: CVPixelBuffer) {
        lock.lock()
        pixelBuffer = buffer; serial &+= 1
        let handler = onFrame
        lock.unlock()
        handler?()
    }
    func latest() -> (CVPixelBuffer, UInt64)? {
        lock.lock(); defer { lock.unlock() }
        guard let pixelBuffer else { return nil }
        return (pixelBuffer, serial)
    }
    func clear() {
        lock.lock(); defer { lock.unlock() }
        pixelBuffer = nil
    }
}

private final class StreamSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let mailbox: FrameMailbox
    let onError: @MainActor @Sendable (String) -> Void
    init(mailbox: FrameMailbox, onError: @escaping @MainActor @Sendable (String) -> Void) {
        self.mailbox = mailbox; self.onError = onError
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        mailbox.put(buffer)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in onError(message) }
    }
}

@MainActor final class DesktopCapture {
    let mailbox = FrameMailbox()
    private var stream: SCStream?
    private var sink: StreamSink?
    private let queue = DispatchQueue(label: "local.laplapaw.Liduo.capture", qos: .userInteractive)

    static var builtInScreen: NSScreen? {
        NSScreen.screens.first {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0
        }
    }

    func start(including windows: [NSWindow], onError: @escaping @MainActor @Sendable (String) -> Void) async throws {
        guard stream == nil else { return }
        let includedWindowIDs = Self.windowIDs(for: windows.map(\.windowNumber))
        guard let screen = Self.builtInScreen,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            throw CaptureError.noDisplay
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == id }) else { throw CaptureError.noDisplay }
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        guard !ownApp.isEmpty else { throw CaptureError.noFilter }
        let includedWindows = content.windows.filter { includedWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: includedWindows)
        filter.includeMenuBar = true
        let config = SCStreamConfiguration()
        let nativeWidth = screen.frame.width * screen.backingScaleFactor
        let scale = min(1, 2560 / nativeWidth)
        config.width = Int(nativeWidth * scale)
        config.height = Int(screen.frame.height * screen.backingScaleFactor * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.captureDynamicRange = .SDR
        config.showsCursor = false
        config.capturesAudio = false
        config.captureMicrophone = false
        let sink = StreamSink(mailbox: mailbox, onError: onError)
        let stream = SCStream(filter: filter, configuration: config, delegate: sink)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: queue)
        self.sink = sink; self.stream = stream
        do {
            try await stream.startCapture()
            try Task.checkCancellation()
        } catch {
            try? await stream.stopCapture()
            self.stream = nil; self.sink = nil; mailbox.clear()
            throw error
        }
    }

    func stop() async {
        if let stream { try? await stream.stopCapture() }
        stream = nil; sink = nil; mailbox.clear()
    }

    static func windowIDs(for numbers: [Int]) -> Set<CGWindowID> {
        Set(numbers.compactMap { $0 > 0 ? CGWindowID(exactly: $0) : nil })
    }
}

enum CaptureError: LocalizedError {
    case noDisplay, noFilter, noFrame
    var errorDescription: String? {
        switch self {
        case .noDisplay: "Встроенный экран сейчас недоступен."
        case .noFilter: "Не удалось исключить Liduo из захвата экрана."
        case .noFrame: "macOS не передала изображение экрана. Проверьте разрешение и повторите."
        }
    }
}
