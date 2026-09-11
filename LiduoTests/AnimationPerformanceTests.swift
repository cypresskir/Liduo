import AppKit
import MetalKit
import XCTest
@testable import Liduo

@MainActor final class AnimationPerformanceTests: XCTestCase {
    func testPresentationCadence() async throws {
        try await measurePresentationCadence(fps: nil, updatesSource: false)
    }

    func testPresentationCadenceAt60FPSWithFreshFrames() async throws {
        try await measurePresentationCadence(fps: 60, updatesSource: true)
    }

    func testPresentationCadenceAt60FPS() async throws {
        try await measurePresentationCadence(fps: 60, updatesSource: false)
    }

    func testPresentationCadenceWithFreshFrames() async throws {
        try await measurePresentationCadence(fps: nil, updatesSource: true)
    }

    private func measurePresentationCadence(fps: Int?, updatesSource: Bool) async throws {
        let screen = try XCTUnwrap(DesktopCapture.builtInScreen)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 2560, 1662, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &buffer), kCVReturnSuccess)
        let source = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(source, [])
        let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(source), width: 2560, height: 1662,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(source),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        context.draw(try DemoArtwork.image(), in: CGRect(x: 0, y: 0, width: 2560, height: 1662))
        CVPixelBufferUnlockBaseAddress(source, [])
        let mailbox = FrameMailbox()
        mailbox.put(source)
        let sourceUpdates = Task { @MainActor in
            guard updatesSource else { return }
            while !Task.isCancelled {
                mailbox.put(source)
                try await Task.sleep(for: .seconds(1.0 / 60))
            }
        }
        defer { sourceUpdates.cancel() }
        var preferences = Preferences()
        preferences.style = .frost; preferences.blur = 0.9; preferences.perspective = 1
        let settings = preferences
        let start = CACurrentMediaTime()
        let renderer = FoldRenderer(mailbox: mailbox) {
            RenderParameters(progress: 0.1 + 0.8 * pow(sin((CACurrentMediaTime() - start) / 4 * .pi), 2),
                preferences: settings, overlay: true, reducedMotion: false)
        }
        let stats = PresentationStats()
        let probe = PresentationProbe(renderer: renderer, stats: stats)
        let view = renderer.makeView()
        if let fps { view.preferredFramesPerSecond = fps }
        view.delegate = probe
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.contentView = view
        panel.orderFrontRegardless()
        defer { view.isPaused = true; panel.orderOut(nil); view.delegate = nil }
        let readyDeadline = CACurrentMediaTime() + 10
        while stats.snapshot().count < 2, CACurrentMediaTime() < readyDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThanOrEqual(stats.snapshot().count, 2, "The test window never began presenting")
        let measurementStart = CACurrentMediaTime()
        try await Task.sleep(for: .seconds(8))
        let times = Array(Set(stats.snapshot().filter { $0 > measurementStart + 2 })).sorted()
        let draws = stats.drawSnapshot().filter { $0.start > measurementStart + 2 }.map(\.duration).sorted()
        print("PRESENTATION state paused=\(view.isPaused) visible=\(panel.occlusionState.contains(.visible)) rendered=\(renderer.framesDrawn) samples=\(times.count)")
        XCTAssertGreaterThan(times.count, 100)
        guard let first = times.first, let last = times.last, last > first else { return }
        XCTAssertGreaterThan(last - first, 5.5, "The presentation sample must cover the measurement interval")
        let gaps = zip(times, times.dropFirst()).map { ($1 - $0) * 1000 }.sorted()
        let fps = Double(times.count - 1) / (last - first)
        let drawP95 = try XCTUnwrap(draws.isEmpty ? nil : draws[Int(Double(draws.count - 1) * 0.95)])
        print("DRAW cpuP95=\(drawP95) cpuMax=\(draws.last!) requested=\(view.preferredFramesPerSecond)")
        XCTAssertLessThan(drawP95, 1000 / Double(view.preferredFramesPerSecond) * 0.5,
            "Waiting for a drawable blocks the main thread")
        print("PRESENTATION fresh=\(updatesSource) warmedUp=2s requested=\(view.preferredFramesPerSecond) fps=\(fps) gapP95=\(gaps[Int(Double(gaps.count - 1) * 0.95)]) gapMax=\(gaps.last!) over25ms=\(gaps.filter { $0 > 25 }.count)")
        XCTAssertGreaterThan(fps, Double(view.preferredFramesPerSecond) * 0.9)
        XCTAssertLessThan(gaps[Int(Double(gaps.count - 1) * 0.95)],
            1000 / Double(view.preferredFramesPerSecond) * 1.2, "Window presentation is stuttering")
        XCTAssertLessThan(gaps.last!, 50, "A long presentation pause is hidden by average FPS")
    }

    func testMovingGlassFitsFrameBudget() throws {
        let device = try XCTUnwrap(RenderResources.shared.device)
        let queue = try XCTUnwrap(RenderResources.shared.queue)
        let context = try XCTUnwrap(CGContext(data: nil, width: 2560, height: 1662,
            bitsPerComponent: 8, bytesPerRow: 2560 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(try DemoArtwork.image(), in: CGRect(x: 0, y: 0, width: 2560, height: 1662))
        let source = try MTKTextureLoader(device: device).newTexture(cgImage: XCTUnwrap(context.makeImage()),
            options: [.SRGB: true, .textureUsage: MTLTextureUsage.shaderRead.rawValue])
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: 3600, height: 2338, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = .renderTarget
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        var preferences = Preferences()
        preferences.style = .frost; preferences.blur = 0.9; preferences.shadow = 0.25
        for moving in [false, true] {
            let params = RenderParameters(progress: 0.5, preferences: preferences, overlay: true, reducedMotion: false)
            let renderer = FoldRenderer { params }
            var cpu: [Double] = [], gpu: [Double] = []
            for frame in 0..<240 {
                let progress = moving ? 0.05 + 0.9 * pow(sin(Double(frame) / 239 * .pi), 2) : 0.5
                let start = CACurrentMediaTime()
                let command = try XCTUnwrap(queue.makeCommandBuffer())
                XCTAssertTrue(renderer.encode(texture: source, pass: pass, command: command, params: params,
                    progress: progress, size: CGSize(width: 3600, height: 2338)))
                cpu.append((CACurrentMediaTime() - start) * 1000)
                command.commit(); command.waitUntilCompleted()
                XCTAssertNil(command.error)
                gpu.append((command.gpuEndTime - command.gpuStartTime) * 1000)
            }
            let orderedCPU = cpu.dropFirst().sorted(), orderedGPU = gpu.dropFirst().sorted()
            let p95 = Int(Double(orderedCPU.count - 1) * 0.95)
            print("ANIMATION moving=\(moving) cpuP50=\(orderedCPU[119]) cpuP95=\(orderedCPU[p95]) cpuMax=\(orderedCPU.last!) gpuP95=\(orderedGPU[p95]) gpuMax=\(orderedGPU.last!) over16ms=\(cpu.filter { $0 > 16.67 }.count)")
            XCTAssertLessThan(orderedCPU[p95], 8.0, "Preparing moving glass blocks the animation thread")
        }
    }
}

private final class PresentationStats: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Double] = []
    private var draws: [(start: Double, duration: Double)] = []
    func add(_ time: Double) { lock.lock(); times.append(time); lock.unlock() }
    func snapshot() -> [Double] { lock.lock(); defer { lock.unlock() }; return times }
    func addDraw(start: Double, duration: Double) { lock.lock(); draws.append((start, duration)); lock.unlock() }
    func drawSnapshot() -> [(start: Double, duration: Double)] { lock.lock(); defer { lock.unlock() }; return draws }
}

@MainActor private final class PresentationProbe: NSObject, MTKViewDelegate {
    let renderer: FoldRenderer
    let stats: PresentationStats
    init(renderer: FoldRenderer, stats: PresentationStats) { self.renderer = renderer; self.stats = stats }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        let start = CACurrentMediaTime()
        view.currentDrawable?.addPresentedHandler { [stats] drawable in
            if drawable.presentedTime > 0 { stats.add(drawable.presentedTime) }
        }
        renderer.draw(in: view)
        stats.addDraw(start: start, duration: (CACurrentMediaTime() - start) * 1000)
    }
}
