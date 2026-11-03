import SwiftUI
import AppKit

extension BannerPreset {
    var title: String {
        switch self {
        case .blank: "빈 배너"
        case .seamless: "카카오톡 일체형"
        case .custom: "내 이미지"
        }
    }
    var icon: String {
        switch self {
        case .blank: "rectangle"
        case .seamless: "sidebar.left"
        case .custom: "photo"
        }
    }
}

struct KakaoPreview: View {
    static let windowCornerRadius: CGFloat = 17
    static let bannerWidth: CGFloat = 400
    static let bannerHeight: CGFloat = 100
    static let bannerAspectRatio = CGFloat(BannerFormat.aspectRatio)
    let preset: BannerPreset
    let imagePath: String
    var croppedImage: CGImage? = nil
    var restart: (() -> Void)? = nil
    var isRestarting = false

    @Environment(\.colorScheme) private var colorScheme

    private let sampleNames = ["나와의 채팅", "디자인 팀", "친구들", "주말 모임", "프로젝트"]
    private let sampleMessages = ["메모를 남겨두세요", "시안을 확인해 주세요", "좋아요!", "주말에 만나요", "작업 내용을 공유했어요"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 26) {
                    ForEach(["person.fill", "bubble.left.fill", "ellipsis"], id: \.self) {
                        Image(systemName: $0).font(.system(size: 22))
                    }
                    Spacer()
                    Image(systemName: "bell")
                    Image(systemName: "gearshape")
                }
                .padding(.top, 66).padding(.bottom, 24)
                .frame(width: 77)
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: colorScheme == .light ? NSColor(srgbRed: 242/255, green: 242/255, blue: 242/255, alpha: 1) : .controlBackgroundColor))
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("채팅").font(.title2.bold())
                        Spacer()
                        Image(systemName: "magnifyingglass")
                        Image(systemName: "bubble.left.badge.plus")
                    }
                    HStack {
                        Text("전체").foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(.black, in: Capsule())
                        Text("안읽음").foregroundStyle(.secondary)
                    }.font(.caption)
                    if let restart {
                        Button(action: restart) {
                            chatRow("카카오톡 재시작", message: isRestarting ? "카카오톡을 다시 여는 중…" : "눌러서 카카오톡을 다시 열기", icon: "person.fill")
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(isRestarting)

                    }
                    ForEach(sampleNames.indices, id: \.self) { index in
                        chatRow(sampleNames[index], message: sampleMessages[index],
                                icon: index == 0 ? "person.fill" : "person.2.fill")
                    }
                    Spacer()
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: preset == .seamless ? 540 : 539)
            if preset != .seamless { Divider() }
            Group {
                if let croppedImage {
                    Image(decorative: croppedImage, scale: 1).resizable()
                } else {
                    BannerArtwork(preset: preset, imagePath: imagePath)
                }
            }
                .frame(width: Self.bannerWidth, height: Self.bannerHeight)
                .clipped()
        }
        .frame(width: 400, height: 640)
        .background(colorScheme == .light ? Color.white : Color(nsColor: .windowBackgroundColor))
        .clipShape(.rect(cornerRadius: Self.windowCornerRadius))
        .overlay { RoundedRectangle(cornerRadius: Self.windowCornerRadius).strokeBorder(.quaternary) }
        .accessibilityElement(children: restart != nil ? .contain : .ignore)
        .accessibilityLabel("카카오톡 예시 창, 배너 미리보기: \(preset.title)")
    }

    private func chatRow(_ title: String, message: String, icon: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 13)
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 42, height: 42)
                .overlay(Image(systemName: icon))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold()).lineLimit(1)
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

}

struct BannerArtwork: View {
    let preset: BannerPreset
    let imagePath: String
    var showsTransparencyGrid = false

    var body: some View {
        switch preset {
        case .blank:
            if showsTransparencyGrid {
                Canvas { context, size in
                    let tile: CGFloat = 8
                    let columns = Int(ceil(size.width / tile))
                    let rows = Int(ceil(size.height / tile))
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))

                    var checks = Path()
                    for row in 0..<rows {
                        for column in stride(from: row % 2, to: columns, by: 2) {
                            checks.addRect(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile,
                                                  width: tile, height: tile))
                        }
                    }
                    context.fill(checks, with: .color(Color(white: 0.8)))
                }
            } else {
                Color(nsColor: .controlBackgroundColor)
            }
        case .seamless:
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Color(white: 242 / 255)
                        .frame(width: geometry.size.width * 77 / 400)
                    Color(white: 232 / 255)
                        .frame(width: geometry.size.width / 400)
                    Color.white
                }
            }
        case .custom:
            AnimatedImage(path: imagePath)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

private struct AnimatedImage: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.image = NSImage(contentsOfFile: path)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
