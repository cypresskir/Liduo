import Metal
import MetalPerformanceShaders

@MainActor final class FrameBlur {
    private let device: MTLDevice
    private let downsampleFactor: Int
    private let scaler: MPSImageBilinearScale
    private var scaledSource: MTLTexture?
    private var destination: MTLTexture?
    private var kernel: MPSImageGaussianBlur?
    private var currentSigma: Float = -1
    private(set) var encodedFrames = 0
    private weak var cachedSource: MTLTexture?
    private var cachedVersion: UInt64?
    private var cachedCommand: MTLCommandBuffer?

    init(device: MTLDevice, downsampleFactor: Int = 1) {
        self.device = device
        self.downsampleFactor = downsampleFactor
        scaler = MPSImageBilinearScale(device: device)
    }

    func reset() {
        destination = nil
        scaledSource = nil
        kernel = nil
        currentSigma = -1
        invalidateCache()
    }

    func invalidateCache() {
        cachedSource = nil; cachedVersion = nil; cachedCommand = nil
    }

    func encode(source: MTLTexture, sigma: Float, command: MTLCommandBuffer, sourceVersion: UInt64? = nil) -> MTLTexture? {
        let sigma = sigma / Float(downsampleFactor)
        guard sigma >= 0.25 else { return source }
        if let sourceVersion, sourceVersion == cachedVersion, cachedSource === source,
           sigma == currentSigma, let cachedCommand,
           [.committed, .scheduled, .completed].contains(cachedCommand.status), let destination {
            return destination
        }
        let width = max(1, source.width / downsampleFactor)
        let height = max(1, source.height / downsampleFactor)
        if destination?.width != width || destination?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.shaderRead, .shaderWrite]
            destination = device.makeTexture(descriptor: descriptor)
            scaledSource = downsampleFactor > 1 ? device.makeTexture(descriptor: descriptor) : nil
        }
        guard let destination else { return nil }
        if sigma != currentSigma {
            let kernel = MPSImageGaussianBlur(device: device, sigma: sigma)
            kernel.edgeMode = .clamp
            self.kernel = kernel
            currentSigma = sigma
        }
        guard let kernel else { return nil }
        encodedFrames += 1
        if downsampleFactor > 1 {
            guard let scaledSource else { return nil }
            scaler.encode(commandBuffer: command, sourceTexture: source, destinationTexture: scaledSource)
            kernel.encode(commandBuffer: command, sourceTexture: scaledSource, destinationTexture: destination)
        } else {
            kernel.encode(commandBuffer: command, sourceTexture: source, destinationTexture: destination)
        }
        cachedSource = source; cachedVersion = sourceVersion; cachedCommand = command
        return destination
    }
}
