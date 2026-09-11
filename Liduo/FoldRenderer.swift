import AppKit
import MetalKit
import SwiftUI
import QuartzCore

struct RenderParameters: Equatable {
    var progress: Double
    var preferences: Preferences
    var overlay: Bool
    var reducedMotion: Bool
}

private struct ShaderUniforms {
    var effect: SIMD4<Float>
    var mode: SIMD4<Float>
}

@MainActor final class RenderResources {
    static let shared = RenderResources()
    let device: MTLDevice?
    let queue: MTLCommandQueue?
    let backgroundPipeline: MTLRenderPipelineState?
    let foldPipeline: MTLRenderPipelineState?
    let demoTexture: MTLTexture?
    let error: String?

    private init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        queue = device?.makeCommandQueue()
        var background: MTLRenderPipelineState?
        var fold: MTLRenderPipelineState?
        var texture: MTLTexture?
        var problem: String?
        if let device {
            do {
                guard let url = Bundle.main.url(forResource: "FoldShaders", withExtension: "metal.txt") else {
                    throw NSError(domain: "Liduo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не найден шейдер Liduo."])
                }
                let source = try String(contentsOf: url, encoding: .utf8)
                let library = try device.makeLibrary(source: source, options: nil)
                func pipeline(vertex: String, fragment: String) throws -> MTLRenderPipelineState {
                    let descriptor = MTLRenderPipelineDescriptor()
                    descriptor.vertexFunction = library.makeFunction(name: vertex)
                    descriptor.fragmentFunction = library.makeFunction(name: fragment)
                    let color = descriptor.colorAttachments[0]!
                    color.pixelFormat = .bgra8Unorm_srgb
                    color.isBlendingEnabled = true
                    color.sourceRGBBlendFactor = .one
                    color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                    color.sourceAlphaBlendFactor = .one
                    color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                    return try device.makeRenderPipelineState(descriptor: descriptor)
                }
                background = try pipeline(vertex: "backgroundVertex", fragment: "backgroundFragment")
                fold = try pipeline(vertex: "foldVertex", fragment: "foldFragment")
                texture = try MTKTextureLoader(device: device).newTexture(cgImage: DemoArtwork.image(),
                    options: [.SRGB: true, .textureUsage: MTLTextureUsage.shaderRead.rawValue])
            } catch { problem = error.localizedDescription }
        } else { problem = "Metal недоступен на этом Mac." }
        backgroundPipeline = background; foldPipeline = fold; demoTexture = texture; error = problem
    }
}

private final class GPUFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
    let reference: CVMetalTexture
    let texture: MTLTexture
    init(buffer: CVPixelBuffer, reference: CVMetalTexture, texture: MTLTexture) {
        self.buffer = buffer; self.reference = reference; self.texture = texture
    }
}

final class FramePresentationHistory: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Double] = []
    private var nextIndex = 0
    private var totalFrames = 0

    func add(_ time: Double) {
        guard time.isFinite, time > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        if times.count < 1024 { times.append(time) }
        else { times[nextIndex] = time }
        nextIndex = (nextIndex + 1) % 1024
        totalFrames += 1
    }

    func summary() -> [String: Double] {
        lock.lock()
        let samples = Array(Set(times)).sorted()
        let count = totalFrames
        lock.unlock()
        var result = ["frames": Double(count), "samples": Double(samples.count)]
        guard samples.count > 1, let first = samples.first, let last = samples.last, last > first else { return result }
        let gaps = zip(samples, samples.dropFirst()).map { ($1 - $0) * 1000 }.sorted()
        result["seconds"] = last - first
        result["fps"] = Double(samples.count - 1) / (last - first)
        result["gapP95MS"] = gaps[Int(Double(gaps.count - 1) * 0.95)]
        result["gapMaxMS"] = gaps.last
        return result
    }
}

@MainActor final class FoldRenderer: NSObject, MTKViewDelegate {
    var parameters: () -> RenderParameters
    var presentationHistory: FramePresentationHistory?
    private let resources = RenderResources.shared
    private let mailbox: FrameMailbox?
    private var blur: FrameBlur?
    private var glassBlur: FrameBlur?
    private var textureCache: CVMetalTextureCache?
    private var frame: GPUFrame?
    private var serial: UInt64 = 0
    private var motion = FoldMotion()
    private var lastPreview: RenderParameters?
    private var lastPreviewSize = CGSize.zero
    private var lastRenderedSerial: UInt64?
    private var lastVisualChange = 0.0
    private let inflight = DispatchSemaphore(value: 3)
    private(set) var framesDrawn = 0
    private weak var view: MTKView?

    init(mailbox: FrameMailbox? = nil, parameters: @escaping () -> RenderParameters) {
        self.mailbox = mailbox; self.parameters = parameters
        super.init()
        if let device = resources.device {
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
            blur = FrameBlur(device: device)
            glassBlur = FrameBlur(device: device, downsampleFactor: 4)
        }
        mailbox?.setFrameHandler { [weak self] in
            Task { @MainActor [weak self] in self?.invalidate() }
        }
    }

    func makeView() -> MTKView {
        let view = VisibilityMetalView(frame: .zero, device: resources.device)
        self.view = view
        view.isPaused = true
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = min(120, DesktopCapture.builtInScreen?.maximumFramesPerSecond ?? 60)
        view.autoResizeDrawable = true
        view.layer?.isOpaque = false
        view.delegate = self
        view.onBecameVisible = { [weak self] in self?.lastPreview = nil; self?.invalidate() }
        return view
    }

    func invalidate() {
        guard let view, view.isPaused, let window = view.window,
              window.isVisible, mailbox == nil || window.occlusionState.contains(.visible) else { return }
        view.isPaused = false
    }

    func reset() {
        motion = FoldMotion()
        lastPreview = nil
        lastRenderedSerial = nil
        frame = nil; serial = 0
        blur?.reset()
        glassBlur?.reset()
        if let textureCache { CVMetalTextureCacheFlush(textureCache, 0) }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        lastPreview = nil
        invalidate()
    }

    func draw(in view: MTKView) {
        if mailbox == nil, view.window?.isVisible != true { view.isPaused = true; return }
        guard inflight.wait(timeout: .now()) == .success else { return }
        guard let queue = resources.queue else { inflight.signal(); return }
        let params = parameters()
        let now = CACurrentMediaTime()
        let currentProgress = motion.update(target: params.progress, at: now)
        var preview = params
        preview.progress = Double(Float(currentProgress))
        if let (buffer, nextSerial) = mailbox?.latest(), nextSerial != serial, let textureCache {
            var reference: CVMetalTexture?
            let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, buffer, nil,
                .bgra8Unorm_srgb, CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &reference)
            if result == kCVReturnSuccess, let reference, let texture = CVMetalTextureGetTexture(reference) {
                frame = GPUFrame(buffer: buffer, reference: reference, texture: texture)
                serial = nextSerial
            }
        }
        if lastPreview == preview, lastPreviewSize == view.drawableSize, lastRenderedSerial == serial {
            if now - lastVisualChange >= 0.15 { view.isPaused = true }
            inflight.signal(); return
        }
        guard let texture = mailbox == nil ? resources.demoTexture : frame?.texture,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer()
        else { inflight.signal(); return }
        guard encode(texture: texture, pass: pass, command: command, params: params,
                     progress: currentProgress, size: view.drawableSize, sourceVersion: serial) else {
            blur?.invalidateCache(); glassBlur?.invalidateCache()
            inflight.signal(); return
        }
        let retainedFrame = frame
        let semaphore = inflight
        command.addCompletedHandler { _ in
            withExtendedLifetime(retainedFrame) {}
            semaphore.signal()
        }
        if let presentationHistory {
            drawable.addPresentedHandler { presentationHistory.add($0.presentedTime) }
        }
        command.commit()
        drawable.present()
        lastPreview = preview; lastPreviewSize = view.drawableSize; lastRenderedSerial = serial
        lastVisualChange = now
        framesDrawn += 1
    }

    func encode(texture: MTLTexture, pass: MTLRenderPassDescriptor, command: MTLCommandBuffer,
                params: RenderParameters, progress: Double, size: CGSize, sourceVersion: UInt64? = nil) -> Bool {
        guard let backgroundPipeline = resources.backgroundPipeline,
              let foldPipeline = resources.foldPipeline else { return false }
        let blurAmount = Float(progress * params.preferences.blur) * Float(texture.width) / 1600
        let sigma = blurAmount * 8
        let glassSigma = blurAmount * (params.preferences.style == .frost ? 72 : 54)
        guard let blurred = blur?.encode(source: texture, sigma: sigma, command: command, sourceVersion: sourceVersion),
              let frosted = glassBlur?.encode(source: texture, sigma: glassSigma, command: command, sourceVersion: sourceVersion),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
        let opacity: Float = params.overlay ? Float(min(1, progress / 0.015)) : 1
        var uniforms = ShaderUniforms(
            effect: SIMD4(Float(progress), Float(params.preferences.perspective), Float(params.preferences.blur), Float(params.preferences.shadow)),
            mode: SIMD4(params.preferences.style.index, opacity, params.reducedMotion ? 1 : 0, Float(size.width / max(1, size.height))))
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(blurred, index: 1)
        encoder.setFragmentTexture(frosted, index: 2)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.setRenderPipelineState(foldPipeline)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36 * 36 * 6)
        encoder.endEncoding()
        return true
    }
}

struct FoldPreview: NSViewRepresentable {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeCoordinator() -> FoldRenderer {
        FoldRenderer { [model] in RenderParameters(progress: model.previewProgress,
            preferences: model.preferences, overlay: false,
            reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
    }
    func makeNSView(context: Context) -> MTKView { context.coordinator.makeView() }
    func updateNSView(_ view: MTKView, context: Context) {
        let preferences = model.preferences
        let followsLid = model.previewFollowsLid
        let measuredAngle = model.angle
        let previewAngle = model.previewAngle
        let reducedMotion = reduceMotion
        context.coordinator.parameters = { [model] in
            let angle = followsLid ? (model.lidMotion.angle(at: CACurrentMediaTime()) ?? measuredAngle ?? 123) : previewAngle
            return RenderParameters(progress: FoldMath.progress(angle: angle, clearAngle: preferences.clearAngle),
                preferences: preferences, overlay: false, reducedMotion: reducedMotion)
        }
        context.coordinator.invalidate()
    }
    static func dismantleNSView(_ view: MTKView, coordinator: FoldRenderer) {
        view.isPaused = true; view.delegate = nil; coordinator.reset()
    }
}

@MainActor private final class VisibilityMetalView: MTKView, @preconcurrency CAMetalDisplayLinkDelegate {
    var onBecameVisible: (() -> Void)?
    private var linkDrawable: CAMetalDrawable?
    nonisolated(unsafe) private var renderLink: CAMetalDisplayLink?
    private var renderingPaused = false
    nonisolated(unsafe) private var visibilityObserver: NSObjectProtocol?

    override var isPaused: Bool {
        get { renderingPaused }
        set {
            renderingPaused = newValue
            // Keep MetalKit's timer stopped; the Metal display link supplies each drawable.
            super.isPaused = true
            renderLink?.isPaused = newValue
        }
    }

    override var preferredFramesPerSecond: Int {
        didSet { updateFrameRate() }
    }

    private func updateFrameRate() {
        let fps = Float(min(preferredFramesPerSecond, window?.screen?.maximumFramesPerSecond ?? 60))
        renderLink?.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
    }

    override var currentDrawable: CAMetalDrawable? { linkDrawable }

    override var currentRenderPassDescriptor: MTLRenderPassDescriptor? {
        guard let linkDrawable else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = linkDrawable.texture
        pass.colorAttachments[0].clearColor = clearColor
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        return pass
    }

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        guard !isPaused else { return }
        linkDrawable = update.drawable
        delegate?.draw(in: self)
        linkDrawable = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderLink?.invalidate(); renderLink = nil
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        guard let window else { isPaused = true; return }
        guard let layer = layer as? CAMetalLayer else { isPaused = true; return }
        renderLink = CAMetalDisplayLink(metalLayer: layer)
        renderLink?.delegate = self
        renderLink?.preferredFrameLatency = 2
        updateFrameRate()
        renderLink?.add(to: .main, forMode: .common)
        isPaused = !window.isVisible || !window.occlusionState.contains(.visible)
        onBecameVisible?()
        visibilityObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
            object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let ordered = self.window?.isVisible == true
                    self.isPaused = !ordered || !(self.window?.occlusionState.contains(.visible) ?? false)
                    if ordered { self.onBecameVisible?() }
                }
            }
    }
    deinit {
        renderLink?.invalidate()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }
}
