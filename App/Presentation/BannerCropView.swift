import SwiftUI

struct BannerCropView: View {
    let generated: GeneratedBanner
    let save: (Double, Double, Double) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var x = 0.5
    @State private var y = 0.5
    @State private var zoom = 1.0
    @GestureState private var magnification = 1.0
    @GestureState private var drag: DragGesture.Value?
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("배너 자르기").font(.title2.bold())
            Text("선택 상자를 옮기거나 모서리를 드래그해 4:1 배너 영역을 조절하세요.")
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let image = generated.image
                let editorWidth = geometry.size.width - 240
                let scale = min((editorWidth - 32) / CGFloat(image.width),
                                (geometry.size.height - 32) / CGFloat(image.height))
                let width = CGFloat(image.width) * scale
                let height = CGFloat(image.height) * scale
                let origin = CGPoint(x: (editorWidth - width) / 2,
                                     y: (geometry.size.height - height) / 2)
                let base = selection(x: x, y: y, zoom: zoom, scale: scale, origin: origin)
                let adjustment = cropAdjustment(drag, box: base, scale: scale)
                let frame = selection(x: adjustment.x, y: adjustment.y,
                                      zoom: drag == nil ? effectiveZoom : adjustment.zoom,
                                      scale: scale, origin: origin)

                let liveCrop = generated.cropRect(x: adjustment.x, y: adjustment.y,
                                                  zoom: drag == nil ? effectiveZoom : adjustment.zoom)
                HStack(spacing: 20) {
                    ZStack(alignment: .topLeading) {
                        Color(nsColor: .controlBackgroundColor)
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: width, height: height)
                            .position(x: origin.x + width / 2, y: origin.y + height / 2)
                        Canvas { context, _ in
                            var mask = Path(CGRect(origin: origin, size: CGSize(width: width, height: height)))
                            mask.addRect(frame)
                            context.fill(mask, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
                            context.stroke(Path(frame), with: .color(.white), lineWidth: 1)
                            for corner in corners(of: frame) {
                                let handle = CGRect(x: corner.x - 3, y: corner.y - 3, width: 6, height: 6)
                                context.fill(Path(roundedRect: handle, cornerRadius: 1), with: .color(.white))
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 10))
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 2)
                        .updating($drag) { value, state, _ in state = value }
                        .onEnded { value in
                            let result = cropAdjustment(value, box: base, scale: scale)
                            x = result.x
                            y = result.y
                            zoom = result.zoom
                        })
                    .simultaneousGesture(MagnifyGesture()
                        .updating($magnification) { value, state, _ in state = value.magnification }
                        .onEnded { value in zoom = clampedZoom(zoom * value.magnification) })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("4대 1 배너 자르기 영역")
                    .accessibilityAction(named: Text("선택 상자를 위로 이동")) { y = max(0, y - 0.05) }
                    .accessibilityAction(named: Text("선택 상자를 아래로 이동")) { y = min(1, y + 0.05) }
                    .accessibilityAction(named: Text("선택 상자를 왼쪽으로 이동")) { x = max(0, x - 0.05) }
                    .accessibilityAction(named: Text("선택 상자를 오른쪽으로 이동")) { x = min(1, x + 0.05) }
                    .frame(width: editorWidth, height: geometry.size.height)

                    KakaoPreview(preset: .custom, imagePath: "", croppedImage: image.cropping(to: liveCrop))
                        .scaleEffect(0.55)
                        .frame(width: 220, height: 352)
                        .accessibilityLabel("현재 선택 영역의 카카오톡 미리보기")
                }
            }
            .frame(height: 352)

            if let saveError {
                Text(saveError).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("배너 저장") {
                    do {
                        try save(x, y, zoom)
                        dismiss()
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 780)
    }
    private func selection(x: Double, y: Double, zoom: Double, scale: CGFloat, origin: CGPoint) -> CGRect {
        generated.cropRect(x: x, y: y, zoom: zoom)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: origin.x, dy: origin.y)
    }

    private func corners(of box: CGRect) -> [CGPoint] {
        [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
         CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
    }

    private func cropAdjustment(_ drag: DragGesture.Value?, box: CGRect, scale: CGFloat)
        -> (x: Double, y: Double, zoom: Double) {
        guard let drag else { return (x, y, zoom) }
        let delta = drag.translation
        if let corner = corners(of: box).first(where: {
            abs($0.x - drag.startLocation.x) <= 12 && abs($0.y - drag.startLocation.y) <= 12
        }) {
            let dx = delta.width * (corner.x < box.midX ? -1 : 1)
            let dy = delta.height * (corner.y < box.midY ? -1 : 1)
            let ratio = CGFloat(BannerFormat.aspectRatio)
            let widthChange = (dx + dy / ratio) / (1 + 1 / (ratio * ratio))
            let current = generated.cropRect(x: x, y: y, zoom: zoom)
            let left = corner.x < box.midX
            let top = corner.y < box.midY
            let anchorX = left ? current.maxX : current.minX
            let anchorY = top ? current.maxY : current.minY
            let availableWidth = left ? anchorX : CGFloat(generated.image.width) - anchorX
            let availableHeight = top ? anchorY : CGFloat(generated.image.height) - anchorY
            let maximumWidth = min(availableWidth, availableHeight * ratio)
            let requestedWidth = min(maximumWidth, max(ratio, (box.width + widthChange) / scale))
            let newZoom = clampedZoom(Double(generated.cropHeight) * Double(ratio / requestedWidth))
            let size = generated.cropRect(x: 0, y: 0, zoom: newZoom).size
            let travelX = CGFloat(generated.image.width) - size.width
            let travelY = CGFloat(generated.image.height) - size.height
            let newX = left ? anchorX - size.width : anchorX
            let newY = top ? anchorY - size.height : anchorY
            return (travelX > 0 ? min(1, max(0, newX / travelX)) : x,
                    travelY > 0 ? min(1, max(0, newY / travelY)) : y,
                    newZoom)
        }
        guard box.contains(drag.startLocation) else { return (x, y, zoom) }
        let travelX = CGFloat(generated.image.width) * scale - box.width
        let travelY = CGFloat(generated.image.height) * scale - box.height
        return (travelX > 0 ? min(1, max(0, x + delta.width / travelX)) : x,
                travelY > 0 ? min(1, max(0, y + delta.height / travelY)) : y,
                zoom)
    }

    private var effectiveZoom: Double { clampedZoom(zoom * magnification) }

    private func clampedZoom(_ value: Double) -> Double {
        min(4, max(1, value))
    }
}
