import SwiftUI
import AppKit
import ImagePlayground
import UniformTypeIdentifiers

struct BannerView: View {
    let bannerLibrary: BannerLibrary
    @StateObject private var access = ProxyAccess()
    @AppStorage("customBannerName") private var customBannerName = ""
    @State private var renameDraft = ""
    @State private var isRenamingBanner = false
    @State private var deletionTarget: GalleryItem?
    @State private var renameTarget: URL?
    @State private var uploadedBanners: [URL] = []
    @AppStorage("bannerNames") private var bannerNames = Data()

    private struct GalleryItem: Hashable {
        let preset: BannerPreset
        var file: URL? = nil
        var community: CommunityBanner? = nil
    }

    private var names: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: bannerNames)) ?? [:]
    }

    private func title(for item: GalleryItem) -> String {
        if let community = item.community { return community.title }
        guard let file = item.file else { return item.preset.title }
        let stem = file.deletingPathExtension().lastPathComponent
        if let name = names[file.lastPathComponent] { return name }
        if stem.hasPrefix("Playground-") { return "생성한 배너" }
        if stem.count > 37, UUID(uuidString: String(stem.prefix(36))) != nil {
            return String(stem.dropFirst(37))
        }
        return stem
    }

    @AppStorage("bannerImagePath") private var imagePath = ""
    @AppStorage("bannerPreset") private var preset: BannerPreset = .blank
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @State private var generatingImage = false
    @State private var pendingCrop: GeneratedBanner?
    @State private var crop: GeneratedBanner?
    @State private var choosingImage = false
    @State private var importError: String?
    @State private var showsSetup = false
    @State private var didOfferSetup = false
    @State private var hasCertificateTrust = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var certificateStatus = ""
    @State private var certificateBusy = false

    private enum Destination: Hashable {
        case gallery, presets, uploads, community, network
    }

    @State private var communityBanners: [CommunityBanner]?
    @State private var communityError: String?
    @State private var communityFiles: [CommunityBanner: URL] = [:]
    @State private var failedCommunityImages: Set<CommunityBanner> = []

    @State private var destination: Destination? = .gallery

    private var builtInItems: [GalleryItem] {
        BannerPreset.builtIn.map { GalleryItem(preset: $0) }
    }

    private var uploadedItems: [GalleryItem] {
        uploadedBanners.map { GalleryItem(preset: .custom, file: $0) }
    }

    private var isPreviewOnly: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-only")
        #else
        false
        #endif
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section("보관함") {
                    Label("전체 배너", systemImage: "square.grid.2x2").tag(Destination.gallery)
                    Label("기본 프리셋", systemImage: "sparkles").tag(Destination.presets)
                    Label("내 업로드", systemImage: "photo.on.rectangle").tag(Destination.uploads)
                    Label("커뮤니티", systemImage: "person.2").tag(Destination.community)
                }
                if !isPreviewOnly {
                    Section("설정") {
                        Label("네트워크 및 인증서", systemImage: "lock.shield").tag(Destination.network)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 208, max: 260)
        } detail: {
            if destination == .network {
                ScrollView {
                    Form {
                        Section("네트워크 및 인증서") {
                            Button("설치 가이드 열기") {
                                refreshSetup()
                                showsSetup = true
                            }
                            Button("CA 신뢰 제거") { manageCertificate(install: false) }
                                .disabled(certificateBusy)
                            if !certificateStatus.isEmpty {
                                Text(certificateStatus).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
                .frame(minWidth: 828, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                gallery
            }
        }
        .onOpenURL { url in
            guard url.absoluteString == "kakaobanner://gallery" else { return }
            destination = .gallery
        }
        .onAppear {
            refreshSetup()
            if !imagePath.isEmpty, !customBannerName.isEmpty {
                var updated = names
                let key = URL(fileURLWithPath: imagePath).lastPathComponent
                if updated[key] == nil { updated[key] = customBannerName }
                if let data = try? JSONEncoder().encode(updated) {
                    bannerNames = data
                    customBannerName = ""
                }
            }
            reloadBanners()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshSetup() }
        }
        .onChange(of: needsSetup, initial: true) { _, needsSetup in
            guard needsSetup, !didOfferSetup else { return }
            didOfferSetup = true
            showsSetup = true
        }
        .sheet(isPresented: $showsSetup) {
            setupGuide
                .interactiveDismissDisabled(access.isConfigured != true || !hasCertificateTrust)
        }
        .fileImporter(isPresented: $choosingImage, allowedContentTypes: [.png, .jpeg, .gif]) { result in
            do {
                let url = try result.get()
                crop = try bannerLibrary.loadImage(url)
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
        .imagePlaygroundSheet(isPresented: $generatingImage, concepts: [], sourceImage: nil,
                              onCompletion: receiveGeneratedImage)
        .imagePlaygroundOptions(playgroundOptions)
        .onChange(of: generatingImage) { _, presenting in
            guard !presenting else { return }
            if let pendingCrop {
                crop = pendingCrop
                self.pendingCrop = nil
            }
        }
        .sheet(item: $crop) { generated in
            BannerCropView(generated: generated) { x, y, zoom in
                selectBanner(try bannerLibrary.saveGenerated(generated, x: x, y: y, zoom: zoom))
                showsPreview = true
            }
        }
    }

    private var playgroundOptions: ImagePlaygroundOptions {
        var options = ImagePlaygroundOptions()
        options.sizeSpecification = .closest(to: CGSize(width: 1024, height: 576))
        return options
    }

    private func receiveGeneratedImage(_ url: URL) {
        guard let generated = try? bannerLibrary.loadImage(url, name: "생성한 배너") else {
            importError = "생성된 이미지를 열 수 없습니다."
            return
        }
        if generatingImage {
            pendingCrop = generated
        } else {
            crop = generated
        }
    }

    private func selectBanner(_ url: URL) {
        imagePath = url.path
        preset = .custom
        destination = .uploads
        importError = nil
        reloadBanners()
    }

    private func reloadBanners() {
        do {
            uploadedBanners = try bannerLibrary.files()
        } catch {
            importError = error.localizedDescription
        }
    }

    @State private var showsPreview = true

    private var workspaceBackground: Color { Color(nsColor: .textBackgroundColor) }

    private func deleteBanner(_ file: URL) {
        do {
            try bannerLibrary.delete(file)
            uploadedBanners.removeAll { $0 == file }
            if imagePath == file.path {
                imagePath = ""
                if preset == .custom { preset = .blank }
            }
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func bannerSection(_ heading: String, items: [GalleryItem], showEmptyHint: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            if items.isEmpty && showEmptyHint {
                Label("상단 툴바에서 이미지를 추가하거나 생성하세요.", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 24, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(items, id: \.self) { item in
                        let option = item.preset
                        let file = item.community.flatMap { communityFiles[$0] } ?? item.file
                        let selected = preset == option && (option != .custom || file?.path == imagePath)
                        Button {
                            preset = option
                            if let file { imagePath = file.path }
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                Color.clear
                                    .aspectRatio(KakaoPreview.bannerAspectRatio, contentMode: .fit)
                                    .overlay {
                                        GeometryReader { geometry in
                                            Group {
                                                if let community = item.community, file == nil {
                                                    Rectangle().fill(.quaternary)
                                                        .overlay {
                                                            if failedCommunityImages.contains(community) {
                                                                Image(systemName: "photo.badge.exclamationmark")
                                                            } else {
                                                                ProgressView().controlSize(.small)
                                                            }
                                                        }
                                                } else {
                                                    BannerArtwork(preset: option, imagePath: file?.path ?? "", showsTransparencyGrid: true)
                                                }
                                            }
                                                .frame(width: geometry.size.width, height: geometry.size.height)
                                        }
                                    }
                                    .clipShape(.rect(bottomLeadingRadius: KakaoPreview.windowCornerRadius,
                                                     bottomTrailingRadius: KakaoPreview.windowCornerRadius))
                                    .accessibilityHidden(true)
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(title(for: item)).font(.subheadline.weight(.semibold))
                                        if let community = item.community {
                                            Text(community.author).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .lineLimit(1)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(item.community != nil && file == nil)
                        .task(id: item.community) {
                            if let community = item.community { await loadCommunityImage(community) }
                        }
                        .contextMenu {
                            if let file = item.file {
                                Button("이름 변경…") {
                                    renameTarget = file
                                    renameDraft = title(for: item)
                                    isRenamingBanner = true
                                }
                                Button("삭제…", role: .destructive) {
                                    deletionTarget = item
                                }
                            }
                        }
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            bannerSection("커뮤니티", items: (communityBanners ?? []).map {
                GalleryItem(preset: .custom, community: $0)
            }, showEmptyHint: false)
            if let communityError {
                Text(communityError).foregroundStyle(.secondary)
                Button("다시 불러오기") { Task { await loadCommunity() } }
            } else if communityBanners == nil {
                ProgressView("배너 불러오는 중")
            } else if communityBanners?.isEmpty == true {
                Text("등록된 배너가 없습니다.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await loadCommunity() }
    }

    private func loadCommunity() async {
        communityError = nil
        if communityBanners == nil { communityBanners = CommunityBanner.cachedList() }
        do {
            communityBanners = try await CommunityBanner.load()
        } catch {
            if !Task.isCancelled && communityBanners == nil {
                communityError = "커뮤니티 목록을 불러오지 못했습니다."
            }
        }
    }

    private func loadCommunityImage(_ item: CommunityBanner) async {
        if let cached = item.cachedFile() { communityFiles[item] = cached }
        failedCommunityImages.remove(item)
        do {
            communityFiles[item] = try await item.download()
        } catch {
            if !Task.isCancelled && communityFiles[item] == nil { failedCommunityImages.insert(item) }
        }
    }

    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                if isPreviewOnly {
                    Label("미리보기 테스트 모드", systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let importError {
                    Text(importError).font(.caption).foregroundStyle(.red)
                }

                switch destination {
                case .presets:
                    bannerSection("기본 프리셋", items: builtInItems)
                case .uploads:
                    bannerSection("내 배너", items: uploadedItems)
                case .community:
                    communitySection
                default:
                    bannerSection("기본 프리셋", items: builtInItems)
                    bannerSection("내 배너", items: uploadedItems)
                    communitySection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 380, idealWidth: 420, maxWidth: .infinity)
        .background(workspaceBackground)
        .alert("배너 이름 변경", isPresented: $isRenamingBanner) {
            TextField("이름", text: $renameDraft)
            Button("취소", role: .cancel) {}
            Button("저장") {
                guard let renameTarget else { return }
                var updated = names
                updated[renameTarget.lastPathComponent] = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = try? JSONEncoder().encode(updated) { bannerNames = data }
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("배너를 삭제할까요?", isPresented: Binding(
            get: { deletionTarget != nil },
            set: { if !$0 { deletionTarget = nil } }
        ), presenting: deletionTarget) { item in
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                if let file = item.file { deleteBanner(file) }
            }
        } message: { item in
            Text("‘\(title(for: item))’ 배너가 삭제됩니다. 이 작업은 되돌릴 수 없습니다.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { choosingImage = true } label: {
                    Label("이미지 추가", systemImage: "photo.badge.plus")
                }
                .help("파일에서 이미지 추가")

                Button {
                    generatingImage = true
                } label: {
                    Label("Apple Image Playground", systemImage: "apple.image.playground")
                }
                .disabled(!supportsImagePlayground)
                .help(supportsImagePlayground ? "Apple Image Playground에서 이미지 생성" :
                      "이 Mac에서 Apple 이미지 생성을 사용할 수 없습니다.")
            }
            if !showsPreview {
                ToolbarItem(placement: .primaryAction) {
                    previewToggle
                }
            }
        }
        .inspector(isPresented: $showsPreview) {
            ScrollView {
                KakaoPreview(preset: preset, imagePath: imagePath, restart: isPreviewOnly ? nil : restartKakaoTalk, isRestarting: isRestarting)
                    .padding(24)
                    .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    previewToggle
                }
            }
            .alert("카카오톡을 다시 열 수 없습니다", isPresented: Binding(
                get: { restartError != nil },
                set: { if !$0 { restartError = nil } }
            )) {
                Button("확인", role: .cancel) { restartError = nil }
            } message: {
                Text(restartError ?? "")
            }
            .background(workspaceBackground)
            .inspectorColumnWidth(min: 448, ideal: 448, max: 480)
        }
    }

    @State private var isRestarting = false
    @State private var restartError: String?

    private func restartKakaoTalk() {
        guard !isRestarting else { return }
        isRestarting = true
        Task { @MainActor in
            defer { isRestarting = false }
            do {
                if preset == .custom {
                    try await access.startBannerSession(imagePath: imagePath)
                } else if preset == .blank || preset == .seamless {
                    try await access.startBannerSession(imagePath: nil, seamless: preset == .seamless)
                }
                try await KakaoTalkLauncher.restart()
            } catch {
                restartError = error.localizedDescription
            }
        }
    }

    private var previewToggle: some View {
        let title = showsPreview ? "카카오톡 미리보기 닫기" : "카카오톡 미리보기 열기"
        return Button {
            showsPreview.toggle()
        } label: {
            Label(title, systemImage: "sidebar.right")
        }
        .help(title)
    }

    private var needsSetup: Bool {
        guard !isPreviewOnly, !access.busy, !certificateBusy,
              let configured = access.isConfigured else { return false }
        return !configured || !hasCertificateTrust
    }

    private func refreshSetup() {
        guard !isPreviewOnly else { return }
        if !certificateBusy { hasCertificateTrust = LocalCA.hasBannerTrust() }
        access.refreshConfiguration()
    }

    private var setupGuide: some View {
        let networkReady = access.isConfigured == true
        let checking = access.isConfigured == nil
        let complete = networkReady && hasCertificateTrust
        let busy = checking || access.busy || certificateBusy

        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                setupStep("네트워크 확장", number: 1, done: networkReady, current: !networkReady)
                Rectangle().fill(.quaternary).frame(width: 32, height: 1)
                setupStep("로컬 인증서", number: 2, done: hasCertificateTrust, current: networkReady && !complete)
            }
            .padding(.top, 28)

            VStack(spacing: 12) {
                Image(systemName: complete ? "checkmark.circle.fill" : networkReady ? "lock.shield" : "network")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(complete ? Color.green : Color.accentColor)
                    .frame(width: 64, height: 64)
                    .background(.quaternary, in: .rect(cornerRadius: 18))
                    .accessibilityHidden(true)

                Text(complete ? "설정 완료" : networkReady ? "로컬 인증서 설정" : "네트워크 확장 설정")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)

                Text(complete ? "네트워크 확장과 로컬 인증서 설정을 마쳤습니다." :
                     networkReady ? "이 Mac에서 배너 CDN 연결에 사용할 로컬 인증서를 설정합니다." :
                     "macOS에서 네트워크 확장을 허용하면 다음 단계로 넘어갑니다.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if busy {
                    ProgressView().controlSize(.small)
                }
                if !complete {
                    Text(checking ? "설치 상태 확인 중…" : networkReady ? certificateStatus : access.status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 236)
            .padding(.horizontal, 36)
            .padding(.vertical, 16)

            Divider()

            HStack(spacing: 10) {
                if !complete {
                    Button("다시 확인", action: refreshSetup)
                        .disabled(busy)
                }
                Spacer()
                Button(complete ? "완료" : networkReady ? "인증서 설정" : "확장 설정 시작") {
                    if complete { showsSetup = false }
                    else if networkReady { manageCertificate(install: true) }
                    else { access.requestActivation() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(busy || (!networkReady && !access.hasInstallationEntitlements))
            }
            .padding(20)
        }
        .frame(width: 500)
    }

    private func setupStep(_ title: String, number: Int, done: Bool, current: Bool) -> some View {
        HStack(spacing: 7) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text(number.formatted())
                        .font(.caption.weight(.semibold))
                        .frame(width: 20, height: 20)
                        .background(.quaternary, in: Circle())
                }
            }
            .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(current ? .semibold : .regular))
        }
        .foregroundStyle(current ? .primary : .secondary)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "완료" : current ? "현재 단계" : "대기")
    }

    private func manageCertificate(install: Bool) {
        certificateBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let message: String
            do {
                if install {
                    try LocalCA.installTrust(LocalCA.createIfNeeded())
                    message = "광고 CDN용 로컬 CA 신뢰 설정을 등록했습니다."
                } else {
                    try LocalCA.removeTrust()
                    message = "로컬 CA의 신뢰 설정과 키체인 항목을 제거했습니다."
                }
            } catch {
                message = error.localizedDescription
            }
            DispatchQueue.main.async {
                certificateStatus = message
                hasCertificateTrust = LocalCA.hasBannerTrust()
                certificateBusy = false
            }
        }
    }
}
