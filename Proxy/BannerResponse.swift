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

    func httpResponse(for url: URL) -> HTTPURLResponse? {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": contentType,
            "Content-Length": String(body.count),
            "Cache-Control": "no-store"
        ])
    }
}
