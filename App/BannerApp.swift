import SwiftUI

@main
struct BannerApp: App {
    var body: some Scene {
        Window("카카오톡 배너 스튜디오", id: "banner") { BannerView(bannerLibrary: BannerLibrary(storage: LocalBannerStorage())) }
            .handlesExternalEvents(matching: ["gallery"])
            .windowResizability(.contentMinSize)
            .windowToolbarStyle(.unified(showsTitle: false))
    }
}
