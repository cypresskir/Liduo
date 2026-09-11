import AppKit
import MetalKit

@MainActor enum StyleArtwork {
    private static var cache: [FoldStyle: NSImage] = [:]

    static func image(for style: FoldStyle) -> NSImage? {
        if let image = cache[style] { return image }
        let resources = RenderResources.shared
        guard let device = resources.device, let queue = resources.queue,
              let source = resources.demoTexture else { return nil }
        let width = 320, height = 200
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = .renderTarget
        guard let target = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let params = RenderParameters(progress: 0.32, preferences: Preferences().applying(style), overlay: false,
            reducedMotion: false)
        let renderer = FoldRenderer { params }
        guard renderer.encode(texture: source, pass: pass, command: command, params: params,
            progress: params.progress, size: CGSize(width: width, height: height)) else { return nil }
        command.commit()
        command.waitUntilCompleted()
        guard command.error == nil else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes {
            target.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        cache[style] = image
        return image
    }
}
