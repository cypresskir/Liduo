import AppKit
import MetalKit
import SwiftUI
import XCTest
@testable import Liduo

@MainActor final class RenderingTests: XCTestCase {
    private var width = 512
    private var height = 320

    func testStyleThumbnailsAreVisibleDistinctAndCached() throws {
        var results = [Data]()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LiduoStyleTests")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for style in FoldStyle.allCases {
            let image = try XCTUnwrap(StyleArtwork.image(for: style))
            XCTAssertTrue(image === StyleArtwork.image(for: style))
            let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertEqual(cgImage.width, 320)
            XCTAssertEqual(cgImage.height, 200)
            let bytes = try XCTUnwrap(cgImage.dataProvider?.data) as Data
            XCTAssertGreaterThan(Set(bytes).count, 100)
            results.append(bytes)
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(style.rawValue).png"))
        }
        XCTAssertNotEqual(results[0], results[1])
        XCTAssertNotEqual(results[0], results[2])
        XCTAssertNotEqual(results[1], results[2])
    }

    func testPreviewStopsSubmittingIdenticalFramesAndResumesAfterAnEdit() async throws {
        var parameters = RenderParameters(progress: 0.32, preferences: Preferences(), overlay: false, reducedMotion: false)
        let renderer = FoldRenderer { parameters }
        let view = renderer.makeView()
        let window = NSWindow(contentRect: NSRect(x: 160, y: 160, width: 420, height: 263),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        window.contentView = view
        window.orderFrontRegardless()
        defer { view.isPaused = true; view.delegate = nil; window.close() }
        let deadline = CACurrentMediaTime() + 5
        while renderer.framesDrawn == 0, CACurrentMediaTime() < deadline {
            renderer.invalidate()
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(500))
        let settled = renderer.framesDrawn
        XCTAssertGreaterThan(settled, 0)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(renderer.framesDrawn, settled)
        XCTAssertTrue(view.isPaused, "An unchanged preview must stop the display link, not only skip GPU commands")
        parameters.preferences.blur = 0.95
        renderer.invalidate()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertGreaterThan(renderer.framesDrawn, settled)
    }

    func testSwiftUIPreviewUpdatesAfterAngleAndAppearanceChanges() async throws {
        let domain = "LiduoPreviewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = AppModel(defaults: defaults)
        model.preferences = Preferences().applying(.frost)
        model.preferences.clearAngle = 80
        model.previewAngle = 102
        let hosting = NSHostingView(rootView: SettingsView(model: model, controller: AppController.shared))
        let window = NSPanel(contentRect: NSRect(x: 160, y: 160, width: 860, height: 672),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }
        func metalView(in view: NSView) -> MTKView? {
            if let metal = view as? MTKView { return metal }
            return view.subviews.lazy.compactMap { metalView(in: $0) }.first
        }
        let deadline = CACurrentMediaTime() + 5
        while metalView(in: hosting) == nil, CACurrentMediaTime() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let view = try XCTUnwrap(metalView(in: hosting))
        let renderer = try XCTUnwrap(view.delegate as? FoldRenderer)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(renderer.parameters().progress, 0)
        XCTAssertGreaterThan(renderer.framesDrawn, 0)
        XCTAssertTrue(view.isPaused)

        let clearFrames = renderer.framesDrawn
        model.previewAngle = 59
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(renderer.parameters().progress, 21.0 / 65, accuracy: 0.0001,
            "The SwiftUI angle control must update the renderer after it has gone idle")
        XCTAssertGreaterThan(renderer.framesDrawn, clearFrames)

        let foldedFrames = renderer.framesDrawn
        model.preferences.blur = 0.1
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(renderer.parameters().preferences.blur, 0.1)
        XCTAssertGreaterThan(renderer.framesDrawn, foldedFrames)
        let idleDeadline = CACurrentMediaTime() + 1.5
        while !view.isPaused, CACurrentMediaTime() < idleDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(view.isPaused, "The updated preview must return to idle")

        window.orderOut(nil)
        try await Task.sleep(for: .milliseconds(200))
        model.previewAngle = 102
        let hiddenFrames = renderer.framesDrawn
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(renderer.framesDrawn, hiddenFrames)
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(renderer.parameters().progress, 0)
        XCTAssertGreaterThan(renderer.framesDrawn, hiddenFrames)
        let reopenedFrames = renderer.framesDrawn
        model.previewAngle = 55
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(renderer.parameters().progress, 25.0 / 65, accuracy: 0.0001)
        XCTAssertGreaterThan(renderer.framesDrawn, reopenedFrames)
    }

    func testBlurReusesPreparedFrameButInvalidatesForNewContentAndRadius() throws {
        let device = try XCTUnwrap(RenderResources.shared.device)
        let queue = try XCTUnwrap(RenderResources.shared.queue)
        let source = try texture { x, _ in UInt8(x % 256) }
        let blur = FrameBlur(device: device)
        func prepare(_ version: UInt64?, _ sigma: Float) throws -> MTLTexture {
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            let result = try XCTUnwrap(blur.encode(source: source, sigma: sigma, command: command, sourceVersion: version))
            command.commit(); command.waitUntilCompleted()
            XCTAssertNil(command.error)
            return result
        }
        let first = try prepare(1, 4)
        let reused = try prepare(1, 4.01)
        XCTAssertTrue(first === reused)
        XCTAssertEqual(blur.encodedFrames, 1, "An unchanged source and quantized radius should reuse the GPU result")
        _ = try prepare(2, 4)
        XCTAssertEqual(blur.encodedFrames, 2, "A new captured frame must refresh the blur even when the texture object is reused")
        _ = try prepare(2, 8)
        XCTAssertEqual(blur.encodedFrames, 3)
        blur.reset()
        _ = try prepare(2, 8)
        XCTAssertEqual(blur.encodedFrames, 4)
        _ = try prepare(nil, 8)
        _ = try prepare(nil, 8)
        XCTAssertEqual(blur.encodedFrames, 6, "Unversioned sources may be mutable; never cache them implicitly")
    }

    func testLiveFrameSleepsAndNewCaptureWakesItWithoutRenderingWhileHidden() async throws {
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 128, 80, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBuffer), kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixelBuffer)
        let mailbox = FrameMailbox()
        mailbox.put(buffer)
        let renderer = FoldRenderer(mailbox: mailbox) {
            RenderParameters(progress: 0.4, preferences: Preferences(), overlay: true, reducedMotion: false)
        }
        let view = renderer.makeView()
        let panel = NSPanel(contentRect: NSRect(x: 160, y: 160, width: 420, height: 263),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.contentView = view
        panel.orderFrontRegardless()
        defer { view.isPaused = true; view.delegate = nil; panel.close() }
        let deadline = CACurrentMediaTime() + 5
        while renderer.framesDrawn == 0, CACurrentMediaTime() < deadline {
            renderer.invalidate()
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertGreaterThan(renderer.framesDrawn, 0)
        XCTAssertTrue(view.isPaused)
        let settled = renderer.framesDrawn
        mailbox.put(buffer)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertGreaterThan(renderer.framesDrawn, settled, "A fresh capture must wake the display link")
        XCTAssertTrue(view.isPaused)
        panel.orderOut(nil)
        try await Task.sleep(for: .milliseconds(100))
        let hiddenCount = renderer.framesDrawn
        mailbox.put(buffer)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(view.isPaused)
        XCTAssertEqual(renderer.framesDrawn, hiddenCount)
    }

    func testFoldEdgesFadeWithoutAHardCut() throws {
        width = 1024; height = 640
        let source = try texture { _, _ in 255 }
        var preferences = Preferences()
        preferences.perspective = 1
        preferences.blur = 0.9
        preferences.shadow = 0.25
        for progress in [0.25, 0.5, 0.75] {
            let result = try render(source, preferences: preferences, progress: progress)
            for row in [height / 5, height / 2, height * 4 / 5] {
                for side in [0, 1] {
                    let values = (0..<width / 4).map { offset in
                        Int(result[(row * width + (side == 0 ? offset : width - 1 - offset)) * 4])
                    }
                    let jump = zip(values, values.dropFirst()).map { abs($1 - $0) }.max()!
                    let peak = values.max()!
                    XCTAssertLessThan(Double(jump), Double(peak) * 0.4,
                        "Hard edge at progress \(progress), row \(row), side \(side): jump \(jump), peak \(peak)")
                }
            }
            try save(result, name: "edge-white-\(Int(progress * 100))")
        }
    }

    func testClosingWhiteDesktopFadesToBlack() throws {
        let source = try texture { _, _ in 255 }
        for style in FoldStyle.allCases {
            var preferences = Preferences()
            preferences.style = style
            preferences.shadow = 0
            let result = try render(source, preferences: preferences, progress: 0.98)
            let brightest = stride(from: 0, to: result.count, by: 4).map { result[$0] }.max()!
            XCTAssertLessThanOrEqual(brightest, 8, "\(style) leaves a bright desktop near closure")
        }
    }

    func testGlassObscuresUpperDetailWhileHingeStaysReadable() throws {
        let source = try texture { x, _ in (x / 4).isMultiple(of: 2) ? 255 : 0 }
        var preferences = Preferences()
        preferences.perspective = 0
        let result = try render(source, preferences: preferences, progress: 0.45)
        func contrast(row: Int) -> Double {
            let values = (128..<384).map { Double(result[(row * width + $0) * 4]) }
            return (values.max()! - values.min()!) / max(1, values.max()! + values.min()!)
        }
        XCTAssertLessThan(contrast(row: 60), 0.12)
        XCTAssertGreaterThan(contrast(row: 305), 0.5)
        try save(result, name: "glass-detail")
    }

    func testFoldDoesNotLeaveAGrayVoidAboveTheDesktop() throws {
        let source = try texture { _, _ in 255 }
        let dark = try texture { _, _ in 0 }
        let actual = try render(source, preferences: Preferences(), progress: 0.5)
        let baseline = try render(dark, preferences: Preferences(), progress: 0.5)
        XCTAssertLessThanOrEqual(actual[(20 * width + 2) * 4], 2, "Uncovered border should be black")
        let center = (40 * width + width / 2) * 4
        XCTAssertGreaterThan(Int(actual[center]) - Int(baseline[center]), 20,
                             "The desktop should remain beneath the glass near the top")
    }

    func testDesktopFrameHasNoTransparentHolesAtCaptureResolution() throws {
        width = 2560; height = 1600
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 2.5, y: 2.5)
        context.draw(try DemoArtwork.image(), in: CGRect(x: 0, y: 0, width: 1024, height: 640))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (index, rect) in [CGRect(x: 45, y: 50, width: 455, height: 470),
                              CGRect(x: 540, y: 100, width: 430, height: 390)].enumerated() {
            NSColor(white: 0.96, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
            NSColor(white: 0.85, alpha: 1).setFill()
            NSBezierPath(rect: CGRect(x: rect.minX, y: rect.maxY - 48, width: rect.width, height: 1)).fill()
            let title = index == 0 ? "Локальные заметки" : "Настройки"
            (title as NSString).draw(at: CGPoint(x: rect.minX + 22, y: rect.maxY - 34),
                withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.black])
            for line in 0..<9 {
                ("\(line + 1). Четкий текст без повторов и шлейфов" as NSString).draw(
                    at: CGPoint(x: rect.minX + 22, y: rect.maxY - 86 - CGFloat(line * 28)),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.darkGray])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let device = try XCTUnwrap(RenderResources.shared.device)
        let source = try MTKTextureLoader(device: device).newTexture(cgImage: XCTUnwrap(context.makeImage()),
            options: [.SRGB: true, .textureUsage: MTLTextureUsage.shaderRead.rawValue])
        for progress in [0.25, 0.5, 0.75, 0.98] {
            let actual = try render(source, preferences: Preferences(), progress: progress)
            let transparentPixels = stride(from: 3, to: actual.count, by: 4).filter { actual[$0] != 255 }.count
            XCTAssertEqual(transparentPixels, 0)
            try save(actual, name: "desktop-fold-\(Int(progress * 100))")
        }
        var frost = Preferences()
        frost.style = .frost
        frost.perspective = 0.65; frost.blur = 0.9; frost.shadow = 0.25
        try save(render(source, preferences: frost, progress: 0.5), name: "desktop-frost-50")
    }

    func testBlurDoesNotCreateDetachedCopiesOfASharpLine() throws {
        let source = try texture { x, _ in abs(x - self.width / 2) <= 1 ? 255 : 0 }
        var preferences = Preferences()
        preferences.perspective = 0
        preferences.blur = 1
        preferences.shadow = 0
        let result = try render(source, preferences: preferences, progress: 0.5)
        let row = 55
        let profile = (0..<55).map { Int(result[(row * width + width / 2 + $0) * 4]) }
        let upwardJumps = zip(profile, profile.dropFirst()).filter { $1 > $0 + 3 }
        XCTAssertTrue(upwardJumps.isEmpty, "Blur has detached copies: \(profile)")
        XCTAssertGreaterThan(profile[0], 5)
        try save(result, name: "line-blur")
    }

    func testBackdropDoesNotStretchDesktopContentIntoUncoveredArea() throws {
        let dark = try texture { _, _ in 0 }
        let stripe = try texture { _, y in y > 280 && y < 309 ? 255 : 0 }
        var preferences = Preferences()
        preferences.perspective = 1
        preferences.blur = 0
        preferences.shadow = 0
        let baseline = try render(dark, preferences: preferences, progress: 0.9)
        let actual = try render(stripe, preferences: preferences, progress: 0.9)
        let difference = (10..<60).map { y in
            abs(Int(actual[(y * width + width / 2) * 4]) - Int(baseline[(y * width + width / 2) * 4]))
        }.max()!
        XCTAssertLessThanOrEqual(difference, 2, "Desktop content is stretched into the backdrop")
        for y in 0..<height {
            XCTAssertEqual(actual[(y * width + width / 2) * 4 + 3], 255)
        }
        try save(actual, name: "backdrop")
    }

    private func texture(pixel: (Int, Int) -> UInt8) throws -> MTLTexture {
        let device = try XCTUnwrap(RenderResources.shared.device)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = pixel(x, y)
                let offset = (y * width + x) * 4
                bytes[offset] = value; bytes[offset + 1] = value; bytes[offset + 2] = value
            }
        }
        bytes.withUnsafeBytes {
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: $0.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

    private func render(_ source: MTLTexture, preferences: Preferences, progress: Double) throws -> [UInt8] {
        let device = try XCTUnwrap(RenderResources.shared.device)
        let queue = try XCTUnwrap(RenderResources.shared.queue)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .renderTarget
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        let params = RenderParameters(progress: progress, preferences: preferences, overlay: true, reducedMotion: false)
        let renderer = FoldRenderer { params }
        var timings = [Double]()
        for _ in 0..<(width == 2560 ? 4 : 1) {
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            XCTAssertTrue(renderer.encode(texture: source, pass: pass, command: command, params: params,
                                          progress: progress, size: CGSize(width: width, height: height)))
            command.commit(); command.waitUntilCompleted()
            XCTAssertNil(command.error)
            timings.append((command.gpuEndTime - command.gpuStartTime) * 1000)
        }
        if width == 2560 {
            print("GPU render at \(width)x\(height), cold then warm: \(timings) ms")
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes {
            target.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return bytes
    }

    private func save(_ bytes: [UInt8], name: String) throws {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("LiduoRenderTests", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let url = destination.appendingPathComponent("\(name).png")
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: url)
        print("Render artifact: \(url.path)")
    }
}
