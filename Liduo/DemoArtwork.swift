import Foundation
import ImageIO

@MainActor enum DemoArtwork {
    private static let cachedImage: Result<CGImage, Error> = Result {
        guard let url = Bundle.main.url(forResource: "PreviewDesktop", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0,
                  [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw NSError(domain: "Liduo", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Не удалось загрузить изображение для предпросмотра."
            ])
        }
        return image
    }

    static func image() throws -> CGImage {
        try cachedImage.get()
    }
}
