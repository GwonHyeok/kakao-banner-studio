import Foundation
import Security

enum LocalCA {
    static func certificateURL() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appendingPathComponent("KakaoBanner/CA/root.der")
    }

    private static let bannerHost = "t1.kakaocdn.net"
    private static let adHost = "serv.ds.kakao.com"

    static func hasBannerTrust() -> Bool {
        guard let url = try? certificateURL(),
              FileManager.default.isReadableFile(atPath: url.deletingLastPathComponent()
                .appendingPathComponent("root.key").path),
              let certificate = try? readCertificate(at: url) else { return false }

        var settings: CFArray?
        guard SecTrustSettingsCopyTrustSettings(certificate, .user, &settings) == errSecSuccess,
              let entries = settings as? [[String: Any]] else { return false }
        return [bannerHost, adHost].allSatisfy { host in
            entries.contains {
                $0[kSecTrustSettingsPolicyString as String] as? String == host &&
                ($0[kSecTrustSettingsResult as String] as? NSNumber)?.uint32Value == SecTrustSettingsResult.trustRoot.rawValue
            }
        }
    }

    static func createIfNeeded() throws -> SecCertificate {
        let url = try certificateURL()
        let directory = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) {
            return try readCertificate(at: url)
        }

        let parent = directory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let staging = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }

        let configuration = """
        [req]
        distinguished_name = subject
        prompt = no
        x509_extensions = ca
        [subject]
        CN = Kakao Banner Local CA
        [ca]
        basicConstraints = critical,CA:TRUE,pathlen:0
        keyUsage = critical,keyCertSign,cRLSign
        subjectKeyIdentifier = hash
        """
        try configuration.write(to: staging.appendingPathComponent("ca.cnf"), atomically: true, encoding: .utf8)
        let generator = Process()
        generator.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        generator.currentDirectoryURL = staging
        generator.arguments = ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256",
                               "-days", "365", "-config", "ca.cnf", "-outform", "DER",
                               "-keyout", "root.key", "-out", "root.der"]
        generator.standardError = FileHandle.nullDevice
        try generator.run()
        generator.waitUntilExit()
        guard generator.terminationStatus == 0 else {
            throw Failure.generation
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: staging.appendingPathComponent("root.key").path)
        let certificate = try readCertificate(at: staging.appendingPathComponent("root.der"))
        try FileManager.default.moveItem(at: staging, to: directory)
        return certificate
    }

    static func bannerTLSIdentity() throws -> (data: Data, password: String) {
        let root = try certificateURL()
        let rootKey = root.deletingLastPathComponent().appendingPathComponent("root.key")
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }

        let extensions = """
        basicConstraints=critical,CA:FALSE
        keyUsage=critical,digitalSignature,keyEncipherment
        extendedKeyUsage=serverAuth
        subjectAltName=DNS:\(bannerHost),DNS:\(adHost)
        """
        try extensions.write(to: staging.appendingPathComponent("leaf.cnf"), atomically: true, encoding: .utf8)

        func run(_ arguments: [String], password: String? = nil) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.currentDirectoryURL = staging
            process.arguments = arguments
            if let password { process.environment = ["BANNER_P12_PASSWORD": password] }
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw Failure.leafGeneration }
        }

        try run(["req", "-new", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=\(bannerHost)",
                 "-keyout", "leaf.key", "-out", "leaf.csr"])
        try run(["x509", "-req", "-in", "leaf.csr", "-CA", root.path, "-CAform", "DER",
                 "-CAkey", rootKey.path, "-set_serial", "0x" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                 "-days", "1", "-sha256", "-extfile", "leaf.cnf", "-out", "leaf.pem"])
        let password = UUID().uuidString
        try run(["pkcs12", "-export", "-inkey", "leaf.key", "-in", "leaf.pem",
                 "-out", "leaf.p12", "-passout", "env:BANNER_P12_PASSWORD"], password: password)
        return (try Data(contentsOf: staging.appendingPathComponent("leaf.p12")), password)
    }

    static func installTrust(_ certificate: SecCertificate) throws {
        let item = [kSecClass: kSecClassCertificate, kSecValueRef: certificate] as CFDictionary
        let added = SecItemAdd(item, nil)
        guard added == errSecSuccess || added == errSecDuplicateItem else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(added))
        }
        let settings = [bannerHost, adHost].map { host in
            [
                kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(true, host as CFString),
                kSecTrustSettingsPolicyString as String: host,
                kSecTrustSettingsResult as String: NSNumber(value: SecTrustSettingsResult.trustRoot.rawValue)
            ] as CFDictionary
        } as CFArray
        let status = SecTrustSettingsSetTrustSettings(certificate, .user, settings)
        if status != errSecSuccess {
            if added == errSecSuccess { SecItemDelete(item) }
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func removeTrust() throws {
        let certificate = try readCertificate(at: certificateURL())
        let status = SecTrustSettingsRemoveTrustSettings(certificate, .user)
        guard status == errSecSuccess || status == errSecItemNotFound || status == errSecNoTrustSettings else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        let item = [kSecClass: kSecClassCertificate, kSecValueRef: certificate] as CFDictionary
        let deleted = SecItemDelete(item)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(deleted))
        }
    }

    private static func readCertificate(at url: URL) throws -> SecCertificate {
        let data = try Data(contentsOf: url)
        guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
            throw Failure.invalidCertificate
        }
        return certificate
    }

    enum Failure: LocalizedError {
        case generation, invalidCertificate, leafGeneration

        var errorDescription: String? {
            switch self {
            case .generation: "로컬 CA를 생성하지 못했습니다."
            case .leafGeneration: "배너 CDN의 TLS 인증서를 만들 수 없습니다."
            case .invalidCertificate: "로컬 CA 파일을 읽을 수 없습니다."
            }
        }
    }
}
