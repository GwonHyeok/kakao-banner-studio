import AppKit

enum KakaoTalkLauncher {
    @MainActor
    static func restart() async throws {
        let identifier = "com.kakao.KakaoTalkMac"
        let workspace = NSWorkspace.shared
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        guard let url = running.first?.bundleURL ?? workspace.urlForApplication(withBundleIdentifier: identifier) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "카카오톡 앱을 찾을 수 없습니다."])
        }

        for app in running where !app.isTerminated {
            _ = app.terminate()
        }
        let deadline = ContinuousClock.now + .seconds(8)
        while running.contains(where: { !$0.isTerminated }) {
            guard ContinuousClock.now < deadline else {
                throw CocoaError(.userCancelled, userInfo: [NSLocalizedDescriptionKey: "카카오톡이 종료되지 않았습니다. 열려 있는 대화나 확인 창을 확인해 주세요."])
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        _ = try await workspace.openApplication(at: url, configuration: .init())
    }
}
