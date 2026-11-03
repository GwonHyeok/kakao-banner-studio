import NetworkExtension
import Network
import Security
import os

final class BannerProxyProvider: NETransparentProxyProvider {
    private let queue = DispatchQueue(label: "com.koreaaitel.kakaobannerstudio.proxy")
    private let host = "t1.kakaocdn.net"
    private let adHost = "serv.ds.kakao.com"
    private let kakao = "com.kakao.KakaoTalkMac"
    private let logger = Logger(subsystem: "com.koreaaitel.kakaobannerstudio.proxy", category: "banner")
    private var listener: NWListener?
    private var port: Network.NWEndpoint.Port?
    private var bridges: [UUID: () -> Void] = [:]

    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        let seamless = options?["seamlessBanner"] as? Bool == true
        let banner: BannerResponse?
        if options?["blankBanner"] as? Bool == true {
            banner = nil
        } else if let body = options?["bannerImage"] as? Data, !body.isEmpty, body.count <= 8 * 1024 * 1024,
                  let mime = options?["bannerContentType"] as? String,
                  ["image/png", "image/jpeg", "image/gif"].contains(mime) {
            banner = BannerResponse(body: body, contentType: mime)
        } else {
            completionHandler(CocoaError(.fileReadCorruptFile))
            return
        }
        guard let p12 = options?["bannerTLSIdentity"] as? Data,
              let password = options?["bannerTLSIdentityPassword"] as? String else {
            completionHandler(CocoaError(.fileReadCorruptFile))
            return
        }
        var items: CFArray?
        let result = SecPKCS12Import(p12 as CFData, [
            kSecImportExportPassphrase as String: password,
            kSecImportToMemoryOnly as String: true
        ] as CFDictionary, &items)
        guard result == errSecSuccess,
              let item = (items as? [[String: Any]])?.first?[kSecImportItemIdentity as String],
              CFGetTypeID(item as CFTypeRef) == SecIdentityGetTypeID(),
              let identity = sec_identity_create(item as! SecIdentity) else {
            completionHandler(NSError(domain: NSOSStatusErrorDomain, code: Int(result == 0 ? errSecDecode : result)))
            return
        }

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, identity)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        let parameters = NWParameters(tls: tls)
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        do {
            let listener = try NWListener(using: parameters)
            queue.async {
                self.listener = listener
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection, banner: banner, seamless: seamless)
                }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, let listener else { return }
                    switch state {
                    case .ready:
                        listener.stateUpdateHandler = nil
                        self.port = listener.port
                        let settings = NETransparentProxyNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
                        settings.includedNetworkRules = [self.host, self.adHost].map {
                            NENetworkRule(destinationHost: NWHostEndpoint(hostname: $0, port: "443"), protocol: .TCP)
                        }
                        self.setTunnelNetworkSettings(settings, completionHandler: completionHandler)
                    case .failed(let error):
                        listener.stateUpdateHandler = nil
                        listener.cancel()
                        completionHandler(error)
                    default: break
                    }
                }
                listener.start(queue: self.queue)
            }
        } catch {
            completionHandler(error)
        }
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        queue.async {
            self.port = nil
            self.listener?.cancel()
            self.listener = nil
            let close = Array(self.bridges.values)
            self.bridges.removeAll()
            close.forEach { $0() }
            completionHandler()
        }
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        guard flow.metaData.sourceAppSigningIdentifier == kakao,
              let tcp = flow as? NEAppProxyTCPFlow,
              case .hostPort(_, let remotePort) = tcp.remoteFlowEndpoint,
              remotePort == .https else { return false }
        return queue.sync {
            guard let port else { return false }
            tcp.open(withLocalFlowEndpoint: nil) { error in
                self.queue.async {
                    guard error == nil else {
                        tcp.closeReadWithError(error)
                        tcp.closeWriteWithError(error)
                        return
                    }
                    self.route(tcp, port: port, buffer: Data())
                }
            }
            return true
        }
    }

    private func route(_ flow: NEAppProxyTCPFlow, port: Network.NWEndpoint.Port, buffer: Data) {
        flow.readData { data, error in
            self.queue.async {
                guard error == nil, let data, !data.isEmpty, self.port == port else {
                    flow.closeReadWithError(error)
                    flow.closeWriteWithError(error)
                    return
                }
                let received = buffer + data
                if received.count < 5 || (received[0] == 22 && received.count < 5 + Int(received[3]) * 256 + Int(received[4])) {
                    self.route(flow, port: port, buffer: received)
                    return
                }
                let endpoint: Network.NWEndpoint = Self.serverName(received).map { [self.host, self.adHost].contains($0) } == true
                    ? .hostPort(host: "127.0.0.1", port: port)
                    : flow.remoteFlowEndpoint
                self.bridge(flow, to: endpoint, initial: received)
            }
        }
    }

    private static func serverName(_ data: Data) -> String? {
        let bytes = Array(data.prefix(65540))
        guard bytes.count >= 44, bytes[0] == 22, bytes[5] == 1 else { return nil }
        let recordEnd = min(bytes.count, 5 + Int(bytes[3]) * 256 + Int(bytes[4]))
        let helloEnd = min(recordEnd, 9 + Int(bytes[6]) * 65536 + Int(bytes[7]) * 256 + Int(bytes[8]))
        var offset = 43
        func field(lengthBytes: Int, limit: Int) -> Range<Int>? {
            guard offset + lengthBytes <= limit else { return nil }
            var count = 0
            for _ in 0..<lengthBytes {
                count = count * 256 + Int(bytes[offset])
                offset += 1
            }
            guard offset + count <= limit else { return nil }
            let range = offset..<(offset + count)
            offset = range.upperBound
            return range
        }
        guard field(lengthBytes: 1, limit: helloEnd) != nil,
              field(lengthBytes: 2, limit: helloEnd) != nil,
              field(lengthBytes: 1, limit: helloEnd) != nil,
              let extensions = field(lengthBytes: 2, limit: helloEnd) else { return nil }
        offset = extensions.lowerBound
        while offset + 4 <= extensions.upperBound {
            let type = Int(bytes[offset]) * 256 + Int(bytes[offset + 1])
            offset += 2
            guard let payload = field(lengthBytes: 2, limit: extensions.upperBound) else { return nil }
            if type == 0 {
                offset = payload.lowerBound
                guard let names = field(lengthBytes: 2, limit: payload.upperBound),
                      !names.isEmpty, bytes[names.lowerBound] == 0 else { return nil }
                offset = names.lowerBound + 1
                guard let name = field(lengthBytes: 2, limit: names.upperBound) else { return nil }
                return String(bytes: bytes[name], encoding: .ascii)?.lowercased()
            }
        }
        return nil
    }

    private func bridge(_ flow: NEAppProxyTCPFlow, to endpoint: Network.NWEndpoint, initial: Data) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let id = UUID()
        let close = {
            connection.cancel()
            flow.closeReadWithError(nil)
            flow.closeWriteWithError(nil)
            self.bridges.removeValue(forKey: id)
        }
        bridges[id] = close
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: initial, completion: .contentProcessed { error in
                    guard error == nil else { close(); return }
                    self.sendToListener(flow, connection, close: close)
                    self.sendToApp(connection, flow, close: close)
                })
            case .failed: close()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func sendToListener(_ flow: NEAppProxyTCPFlow, _ connection: NWConnection, close: @escaping () -> Void) {
        flow.readData { data, error in
            self.queue.async {
                guard error == nil, let data, !data.isEmpty else { close(); return }
                connection.send(content: data, completion: .contentProcessed { error in
                    guard error == nil else { close(); return }
                    self.sendToListener(flow, connection, close: close)
                })
            }
        }
    }

    private func sendToApp(_ connection: NWConnection, _ flow: NEAppProxyTCPFlow, close: @escaping () -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, error in
            guard let data, !data.isEmpty else { close(); return }
            flow.write(data) { writeError in
                self.queue.async {
                    guard error == nil, writeError == nil, !done else { close(); return }
                    self.sendToApp(connection, flow, close: close)
                }
            }
        }
    }

    private func accept(_ connection: NWConnection, banner: BannerResponse?, seamless: Bool) {
        let id = UUID()
        let close = {
            connection.cancel()
            self.bridges.removeValue(forKey: id)
        }
        bridges[id] = close
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: self.readRequest(connection, buffer: Data(), banner: banner, seamless: seamless, close: close)
            case .failed: close()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func readRequest(_ connection: NWConnection, buffer: Data, banner: BannerResponse?, seamless: Bool, close: @escaping () -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, error in
            guard error == nil, let data, !data.isEmpty else { close(); return }
            let received = buffer + data
            guard let separator = received.range(of: Data("\r\n\r\n".utf8)) else {
                guard received.count < 65536 else { close(); return }
                self.readRequest(connection, buffer: received, banner: banner, seamless: seamless, close: close)
                return
            }
            guard separator.lowerBound < 65536,
                  let head = String(data: received[..<separator.lowerBound], encoding: .utf8) else { close(); return }
            let lines = head.components(separatedBy: "\r\n")
            let requestLine = lines[0].split(separator: " ")
            let hosts = lines.dropFirst().filter { $0.lowercased().hasPrefix("host:") }
            guard requestLine.count == 3, requestLine[1].hasPrefix("/"), hosts.count == 1 else { close(); return }
            let authority = hosts[0].dropFirst(5).trimmingCharacters(in: .whitespaces).lowercased()
            guard let requestHost = [self.host, self.adHost].first(where: { authority == $0 || authority == $0 + ":443" }),
                  let url = URL(string: "https://" + requestHost + requestLine[1]) else { close(); return }
            if requestHost == self.adHost {
                self.logger.notice("Ad API request \(requestLine[0], privacy: .public) \(url.path, privacy: .public)")
            }
            var request = URLRequest(url: url)
            request.httpMethod = String(requestLine[0])
            let badge = BannerResponse(body: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=")!, contentType: "image/png")
            if let banner, let replacement = BannerResponse.replacement(sourceAppIdentifier: self.kakao, request: request, banner: banner, transparentBadge: badge) {
                let headers = "HTTP/1.1 200 OK\r\nContent-Type: \(replacement.contentType)\r\nContent-Length: \(replacement.body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                self.logger.info("Served replacement banner (\(replacement.body.count) bytes)")
                connection.send(content: Data(headers.utf8) + replacement.body, isComplete: true, completion: .contentProcessed { _ in close() })
                return
            }
            if requestHost == self.adHost, request.httpMethod == "GET", url.path == "/sdk/banner" {
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let name = String(line[..<colon])
                    guard !["host", "connection", "accept-encoding", "content-length"].contains(name.lowercased()) else { continue }
                    request.addValue(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces), forHTTPHeaderField: name)
                }
                self.forwardBannerDocument(request, to: connection, blank: banner == nil, seamless: seamless, close: close)
                return
            }
            var headers = lines.filter { !$0.lowercased().hasPrefix("connection:") }
            headers.append("Connection: close")
            let initial = Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8) + received[separator.upperBound...]
            self.forward(connection, host: requestHost, initial: initial, close: close)
        }
    }

    private func forwardBannerDocument(_ request: URLRequest, to client: NWConnection, blank: Bool, seamless: Bool, close: @escaping () -> Void) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        session.dataTask(with: request) { data, response, _ in
            self.queue.async {
                defer { session.finishTasksAndInvalidate() }
                guard let data, let response = response as? HTTPURLResponse else { close(); return }
                let body = response.statusCode == 200 ? self.rewriteBannerDocument(data, blank: blank, seamless: seamless) : data
                let mime = response.mimeType ?? "application/octet-stream"
                let head = "HTTP/1.1 \(response.statusCode) Response\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                client.send(content: Data(head.utf8) + body, isComplete: true, completion: .contentProcessed { _ in close() })
            }
        }.resume()
    }

    private func rewriteBannerDocument(_ body: Data, blank: Bool, seamless: Bool) -> Data {
        guard body.count <= 2 * 1024 * 1024,
              let root = try? JSONSerialization.jsonObject(with: body) else { return body }
        let background = seamless
            ? "linear-gradient(to right, #f2f2f2 0 19.25%, #e8e8e8 19.25% 19.5%, #fff 19.5% 100%)"
            : "#f3f3f3"
        var changed = false
        func visit(_ node: Any) -> Any {
            if let array = node as? [Any] { return array.map(visit) }
            guard var fields = node as? [String: Any] else { return node }
            if let html = fields["content"] as? String,
               let creative = html.range(of: #"https://t1\.kakaocdn\.net/b2/creative/[0-9]+/[a-fA-F0-9]{32}\.png"#, options: .regularExpression) {
                fields["content"] = blank ? """
                <!doctype html><html lang="ko"><meta charset="utf-8">
                <style>
                html, body { margin: 0; height: 100%; background: \(background); }
                a { display: block; width: 100%; height: 100%; }
                </style>
                <body><a href="kakaobanner://gallery" target="_blank" aria-label="카카오톡 배너 스튜디오 갤러리"></a></body></html>
                """ : """
                <!doctype html><html lang="ko"><meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; }
                a, img { display: block; width: 100%; height: 100%; }
                img { object-fit: contain; }
                </style>
                <a href="kakaobanner://gallery" target="_blank"><img src="\(html[creative])" alt="카카오톡 배너 스튜디오 갤러리"></a>
                </html>
                """
                changed = true
                return fields
            }
            return fields.mapValues(visit)
        }
        let rewritten = visit(root)
        logger.notice("Ad API document banner HTML matched=\(changed) blank=\(blank)")
        guard changed, let encoded = try? JSONSerialization.data(withJSONObject: rewritten) else { return body }
        return encoded
    }

    private func forward(_ client: NWConnection, host: String, initial: Data, close: @escaping () -> Void) {
        let upstream = NWConnection(host: Network.NWEndpoint.Host(host), port: .https, using: .tls)
        let id = UUID()
        let finish = {
            upstream.cancel()
            self.bridges.removeValue(forKey: id)
            close()
        }
        bridges[id] = finish
        upstream.stateUpdateHandler = { state in
            switch state {
            case .ready:
                upstream.send(content: initial, completion: .contentProcessed { error in
                    guard error == nil else { finish(); return }
                    self.pipe(client, to: upstream, close: finish)
                    self.pipe(upstream, to: client, observeHeaders: host == self.adHost ? Data() : nil, close: finish)
                })
            case .failed: finish()
            default: break
            }
        }
        upstream.start(queue: queue)
    }

    private func pipe(_ source: NWConnection, to destination: NWConnection, observeHeaders: Data? = nil, close: @escaping () -> Void) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, error in
            guard error == nil else { close(); return }
            var remainingHeaders: Data?
            if let observeHeaders, let data {
                let prefix = observeHeaders + data
                if let boundary = prefix.range(of: Data("\r\n\r\n".utf8)), boundary.lowerBound < 16384,
                   let header = String(data: prefix[..<boundary.lowerBound], encoding: .utf8) {
                    let lines = header.components(separatedBy: "\r\n")
                    let status = lines.first?.split(separator: " ").dropFirst().first.flatMap { Int($0) } ?? 0
                    let mime = lines.dropFirst().first {
                        $0.lowercased().hasPrefix("content-type:")
                    }?.dropFirst(13).split(separator: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""
                    self.logger.notice("Ad API response status=\(status) mime=\(mime, privacy: .public)")
                } else if prefix.count < 16384 {
                    remainingHeaders = prefix
                }
            }
            destination.send(content: data, isComplete: done, completion: .contentProcessed { sendError in
                guard sendError == nil, !done else { close(); return }
                self.pipe(source, to: destination, observeHeaders: remainingHeaders, close: close)
            })
        }
    }
}

NEProvider.startSystemExtensionMode()
dispatchMain()
