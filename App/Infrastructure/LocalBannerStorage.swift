import Foundation

struct LocalBannerStorage: BannerStorage {
    func save(_ data: Data, filename: String) throws -> URL {
        let directory = try directory()
        let file = directory.appendingPathComponent(filename)
        try data.write(to: file, options: .atomic)
        return file
    }

    func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory(),
            includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            .filter { ["png", "jpg", "jpeg", "gif"].contains($0.pathExtension.lowercased()) }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return lhs == rhs ? $0.path < $1.path : lhs > rhs
            }
    }

    func remove(_ file: URL) throws {
        guard try files().contains(where: { $0.standardizedFileURL == file.standardizedFileURL }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.removeItem(at: file)
    }

    private func directory() throws -> URL {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("KakaoBanner/Preview", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
