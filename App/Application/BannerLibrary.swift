import Foundation
import ImageIO
import UniformTypeIdentifiers

protocol BannerStorage {
    func files() throws -> [URL]
    func remove(_ file: URL) throws
    func save(_ data: Data, filename: String) throws -> URL
}

struct BannerLibrary {
    let storage: any BannerStorage

    func files() throws -> [URL] { try storage.files() }

    func delete(_ file: URL) throws { try storage.remove(file) }

    func loadImage(_ url: URL, name: String? = nil) throws -> GeneratedBanner {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = frame(source, at: 0), image.width >= BannerFormat.aspectRatio else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let animatedGIF = CGImageSourceGetType(source) as String? == UTType.gif.identifier
            && CGImageSourceGetCount(source) > 1 ? data : nil
        return GeneratedBanner(image: image, name: name ?? url.deletingPathExtension().lastPathComponent,
                               animatedGIF: animatedGIF)
    }

    private func frame(_ source: CGImageSource, at index: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096
        ] as CFDictionary)
    }

    func saveGenerated(_ banner: GeneratedBanner, x: Double, y: Double, zoom: Double) throws -> URL {
        let data = NSMutableData()
        let rect = banner.cropRect(x: x, y: y, zoom: zoom)
        let gif = banner.animatedGIF.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        let type: UTType = gif == nil ? .png : .gif
        let count = gif.map { CGImageSourceGetCount($0) } ?? 1
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if let gif {
            if let properties = CGImageSourceCopyProperties(gif, nil) as? [CFString: Any],
               let gifProperties = properties[kCGImagePropertyGIFDictionary] {
                CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: gifProperties] as CFDictionary)
            }
            for index in 0..<count {
                guard let cropped = frame(gif, at: index)?.cropping(to: rect) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let properties = CGImageSourceCopyPropertiesAtIndex(gif, index, nil) as? [CFString: Any]
                let timing = properties?[kCGImagePropertyGIFDictionary].map {
                    [kCGImagePropertyGIFDictionary: $0] as CFDictionary
                }
                CGImageDestinationAddImage(destination, cropped, timing)
            }
        } else {
            guard let cropped = banner.image.cropping(to: rect) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(destination, cropped, nil)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        let name = String(banner.name.prefix(50))
        return try storage.save(data as Data, filename: "\(banner.id.uuidString)-\(name).\(type == .gif ? "gif" : "png")")
    }
}
