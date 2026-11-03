import Foundation
import ImageIO
import UniformTypeIdentifiers

enum BannerPayload {
    static func selectedImage(at path: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier),
              [.png, .jpeg, .gif].contains(type),
              let mime = type.preferredMIMEType else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [
                NSLocalizedDescriptionKey: "8MB 이하의 PNG, JPEG, GIF 배너를 선택해 주세요."
            ])
        }
        return ["bannerImage": bytes, "bannerContentType": mime]
    }
}


struct CommunityBanner: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    let image: String

    private static let base = URL(string: "https://raw.githubusercontent.com/GwonHyeok/kakao-banner-studio/refs/heads/main/community/")!

    static func cachedList() -> [Self]? {
        guard let file = try? directory().appendingPathComponent("banners.json"),
              let data = try? Data(contentsOf: file) else { return nil }
        return try? decodeList(data)
    }

    static func load() async throws -> [Self] {
        let file = try directory().appendingPathComponent("banners.json")
        let data = try await fetch(base.appendingPathComponent("banners.json"), limit: 256 * 1024)
        let banners = try decodeList(data)
        try data.write(to: file, options: .atomic)
        return banners
    }

    private static func decodeList(_ data: Data) throws -> [Self] {
        let banners = try JSONDecoder().decode([Self].self, from: data)
        guard Set(banners.map(\.id)).count == banners.count else { throw CocoaError(.fileReadCorruptFile) }
        return banners
    }

    func cachedFile() -> URL? {
        guard let file = try? localFile(), FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    func download() async throws -> URL {
        let file = try localFile()
        if Self.isFresh(file) { return file }
        let data = try await Self.fetch(Self.base.appendingPathComponent(image), limit: 8 * 1024 * 1024)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier), [.png, .jpeg, .gif].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              height > 0, width <= 8192, height <= 2048, width == height * 4 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try data.write(to: file, options: .atomic)
        return file
    }

    private func localFile() throws -> URL {
        guard image.range(of: #"^images/[A-Za-z0-9_-]+\.(png|jpe?g|gif)$"#, options: .regularExpression) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try Self.directory().appendingPathComponent(URL(fileURLWithPath: image).lastPathComponent)
    }

    private static func directory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("KakaoBanner/Community", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func isFresh(_ file: URL) -> Bool {
        guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return false }
        return Date().timeIntervalSince(date) < 3600
    }

    private static func fetch(_ url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == url,
              http.expectedContentLength <= Int64(limit) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}
