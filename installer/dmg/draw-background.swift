import AppKit

let size = NSSize(width: 680, height: 460)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1360, pixelsHigh: 920,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.97, green: 0.975, blue: 0.985, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

func text(_ value: String, top: CGFloat, height: CGFloat, pointSize: CGFloat,
          weight: NSFont.Weight, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (value as NSString).draw(in: NSRect(x: 24, y: size.height - top - height, width: 632, height: height),
        withAttributes: [.font: NSFont.systemFont(ofSize: pointSize, weight: weight),
                         .foregroundColor: color, .paragraphStyle: paragraph])
}

text("Установка Liduo", top: 42, height: 46, pointSize: 34, weight: .semibold,
     color: NSColor(calibratedWhite: 0.12, alpha: 1))
text("Перетащите приложение в «Программы»", top: 98, height: 28, pointSize: 17,
     weight: .regular, color: NSColor(calibratedWhite: 0.34, alpha: 1))

let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
let mid = size.height - 210
arrow.move(to: NSPoint(x: 309, y: mid))
arrow.line(to: NSPoint(x: 371, y: mid))
arrow.move(to: NSPoint(x: 358, y: mid + 13))
arrow.line(to: NSPoint(x: 371, y: mid))
arrow.line(to: NSPoint(x: 358, y: mid - 13))
NSColor(calibratedRed: 0.1, green: 0.4, blue: 0.8, alpha: 1).setStroke()
arrow.stroke()

text("Первый запуск и доступ к экрану — в инструкции ниже", top: 294, height: 24,
     pointSize: 14, weight: .regular, color: NSColor(calibratedWhite: 0.34, alpha: 1))
NSGraphicsContext.restoreGraphicsState()
try bitmap.tiffRepresentation(using: .lzw, factor: 1)!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
