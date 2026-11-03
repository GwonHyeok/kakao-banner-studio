import Foundation
import CoreGraphics

struct GeneratedBanner: Identifiable {
    let id = UUID()
    let image: CGImage
    let name: String
    let animatedGIF: Data?

    var cropHeight: Int {
        min(image.height, image.width / BannerFormat.aspectRatio)
    }

    func cropRect(x: Double, y: Double, zoom: Double) -> CGRect {
        let height = max(1, Int(Double(cropHeight) / zoom))
        let width = height * BannerFormat.aspectRatio
        return CGRect(x: Int((Double(image.width - width) * x).rounded()),
                      y: Int((Double(image.height - height) * y).rounded()),
                      width: width, height: height)
    }

}
