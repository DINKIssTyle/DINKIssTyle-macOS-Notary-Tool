import AppKit
import Foundation

enum ICNSConverter {
    enum ConversionError: LocalizedError {
        case unreadableImage
        case renderingFailed(Int)

        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                return "The selected PNG could not be decoded."
            case let .renderingFailed(size):
                return "The \(size)px icon representation could not be rendered."
            }
        }
    }

    private static let representations: [(type: String, size: Int)] = [
        ("icp4", 16), ("icp5", 32), ("icp6", 64),
        ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
        ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)
    ]

    static func convertPNG(at sourceURL: URL, to destinationURL: URL) throws {
        guard let image = NSImage(contentsOf: sourceURL), image.isValid else {
            throw ConversionError.unreadableImage
        }

        var chunks = Data()
        for representation in representations {
            guard let pngData = pngRepresentation(of: image, size: representation.size) else {
                throw ConversionError.renderingFailed(representation.size)
            }
            chunks.append(fourCharacterCode(representation.type))
            chunks.append(bigEndian: UInt32(pngData.count + 8))
            chunks.append(pngData)
        }

        var container = Data()
        container.append(fourCharacterCode("icns"))
        container.append(bigEndian: UInt32(chunks.count + 8))
        container.append(chunks)
        try container.write(to: destinationURL, options: .atomic)
    }

    private static func pngRepresentation(of image: NSImage, size: Int) -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        bitmap.size = NSSize(width: size, height: size)
        let sourceSize = image.size
        let scale = min(CGFloat(size) / max(sourceSize.width, 1), CGFloat(size) / max(sourceSize.height, 1))
        let targetSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let targetRect = NSRect(
            x: (CGFloat(size) - targetSize.width) / 2,
            y: (CGFloat(size) - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: targetRect,
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func fourCharacterCode(_ value: String) -> Data {
        Data(value.utf8.prefix(4))
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        var value = value.bigEndian
        Swift.withUnsafeBytes(of: &value) { buffer in
            append(contentsOf: buffer)
        }
    }
}
