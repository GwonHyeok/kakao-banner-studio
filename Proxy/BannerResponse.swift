import Foundation

struct BannerResponse {
    let body: Data
    let contentType: String

    private static let host = "t1.kakaocdn.net"
    private static let badgePath = "/biz/ui/ad/white_badge_ad_new.png"
    private static let creativePath = #/^\/b2\/creative\/[0-9]+\/[a-fA-F0-9]{32}\.png$/#

    static func replacement(
        sourceAppIdentifier: String,
        request: URLRequest,
        banner: BannerResponse,
        transparentBadge: BannerResponse
    ) -> BannerResponse? {
        guard sourceAppIdentifier == "com.kakao.KakaoTalkMac",
              request.httpMethod == "GET",
              let url = request.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == host,
              url.port == nil || url.port == 443,
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else {
            return nil
        }

        if path == badgePath { return transparentBadge }
        if path.wholeMatch(of: creativePath) != nil { return banner }
        return nil
    }

    static func rewriteDocument(_ body: Data, banner: BannerResponse?, seamless: Bool) -> Data? {
        guard body.count <= 2 * 1024 * 1024,
              let root = try? JSONSerialization.jsonObject(with: body) else { return nil }
        let background = seamless
            ? "linear-gradient(to right, #f2f2f2 0 19.25%, #e8e8e8 19.25% 19.5%, #fff 19.5% 100%)"
            : "transparent"
        let html: String
        if let banner {
            let image = "data:\(banner.contentType);base64,\(banner.body.base64EncodedString())"
            html = """
            <!doctype html><html lang="ko"><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
            html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; }
            a, img { display: block; width: 100%; height: 100%; }
            img { object-fit: contain; }
            </style>
            <a href="kakaobanner://gallery" target="_blank"><img src="\(image)" alt="카카오톡 배너 스튜디오 갤러리"></a>
            </html>
            """
        } else {
            html = """
            <!doctype html><html lang="ko"><meta charset="utf-8">
            <style>
            html, body { margin: 0; height: 100%; background: \(background); }
            a { display: block; width: 100%; height: 100%; }
            </style>
            <body><a href="kakaobanner://gallery" target="_blank" aria-label="카카오톡 배너 스튜디오 갤러리"></a></body></html>
            """
        }

        var changed = false
        func visit(_ node: Any) -> Any {
            if let array = node as? [Any] { return array.map(visit) }
            guard var fields = node as? [String: Any] else { return node }
            if fields["content"] is String {
                fields["content"] = html
                changed = true
            }
            return fields.mapValues(visit)
        }

        let rewritten = visit(root)
        guard changed else { return nil }
        return try? JSONSerialization.data(withJSONObject: rewritten)
    }

    func httpResponse(for url: URL) -> HTTPURLResponse? {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": contentType,
            "Content-Length": String(body.count),
            "Cache-Control": "no-store"
        ])
    }
}
