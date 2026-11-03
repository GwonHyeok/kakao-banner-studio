import Foundation
import Combine
import SystemExtensions
import NetworkExtension
import Security

final class ProxyAccess: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    private let identifier = "com.koreaaitel.kakaobannerstudio.proxy"
    @Published var status = "네트워크 권한 설정을 시작할 수 있습니다."
    @Published var busy = false

    @Published private(set) var isConfigured: Bool?
    @Published private(set) var isChecking = false
    private var inspection: OSSystemExtensionRequest?

    var hasInstallationEntitlements: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let install = SecTaskCopyValueForEntitlement(task, "com.apple.developer.system-extension.install" as CFString, nil) as? Bool
        let network = SecTaskCopyValueForEntitlement(task, "com.apple.developer.networking.networkextension" as CFString, nil) as? [String]
        return install == true && (network?.contains("app-proxy-provider") == true ||
                                   network?.contains("app-proxy-provider-systemextension") == true)
    }

    @MainActor
    func startBannerSession(imagePath: String?, seamless: Bool = false) async throws {
        var options = try imagePath.map { try BannerPayload.selectedImage(at: $0) } ?? ["blankBanner": true]
        options["seamlessBanner"] = seamless
        let identity = try await Task.detached(priority: .userInitiated) {
            try LocalCA.bannerTLSIdentity()
        }.value
        options["bannerTLSIdentity"] = identity.data
        options["bannerTLSIdentityPassword"] = identity.password
        let managers = try await NETransparentProxyManager.loadAllFromPreferences()
        guard let manager = managers.first(where: {
            $0.isEnabled &&
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == identifier
        }), let session = manager.connection as? NETunnelProviderSession else {
            throw CocoaError(.featureUnsupported, userInfo: [
                NSLocalizedDescriptionKey: "활성화된 배너 네트워크 확장 설정을 찾을 수 없습니다."
            ])
        }
        if session.status != .disconnected {
            session.stopTunnel()
            try await waitForSession(session, expected: .disconnected)
        }
        try session.startTunnel(options: options)
        try await waitForSession(session, expected: .connected)
    }

    @MainActor
    private func waitForSession(_ session: NETunnelProviderSession, expected: NEVPNStatus) async throws {
        for _ in 0..<100 {
            if session.status == expected { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CocoaError(.featureUnsupported, userInfo: [
            NSLocalizedDescriptionKey: "배너 네트워크 확장이 제한 시간 안에 상태를 변경하지 못했습니다."
        ])
    }

    func refreshConfiguration() {
        guard inspection == nil, !busy else { return }
        guard hasInstallationEntitlements else {
            status = "현재 빌드에 네트워크 확장 설치 권한이 서명되어 있지 않습니다. 해당 권한으로 서명된 앱을 /Applications에서 실행하세요."
            isConfigured = false
            return
        }
        let request = OSSystemExtensionRequest.propertiesRequest(forExtensionWithIdentifier: identifier, queue: .main)
        isChecking = true
        inspection = request
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func request(_ request: OSSystemExtensionRequest, foundProperties properties: [OSSystemExtensionProperties]) {
        guard request === inspection else { return }
        let extensionURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions")
            .appendingPathComponent(identifier + ".systemextension")
        let installed = properties.first { $0.isEnabled }
        let bundledVersion = Bundle(url: extensionURL)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let enabled = installed != nil
        let needsUpdate = installed.flatMap { active in
            bundledVersion.map { $0.compare(active.bundleVersion, options: .numeric) == .orderedDescending }
        } ?? false
        Task { @MainActor in
            if needsUpdate {
                inspection = nil
                isChecking = false
                isConfigured = nil
                requestActivation()
                return
            }
            defer {
                inspection = nil
                isChecking = false
            }
            guard enabled else {
                isConfigured = false
                return
            }
            do {
                let managers = try await NETransparentProxyManager.loadAllFromPreferences()
                isConfigured = managers.contains {
                    $0.isEnabled &&
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == identifier
                }
            } catch {
                isConfigured = false
                status = error.localizedDescription
            }
        }
    }

    func requestActivation() {
        guard hasInstallationEntitlements, !busy, inspection == nil else { return }
        busy = true
        status = "네트워크 확장과 프록시 설정을 등록하는 중입니다."
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: identifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        status = "시스템 설정에서 카카오톡 배너 스튜디오 네트워크 확장을 허용하세요."
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        if request === inspection {
            inspection = nil
            isChecking = false
            isConfigured = false
            status = error.localizedDescription
            return
        }
        isConfigured = false
        busy = false
        status = error.localizedDescription
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        guard request !== inspection else { return }
        guard result == .completed else {
            isConfigured = false
            busy = false
            status = "Mac을 재시작한 뒤 권한 설정을 다시 실행하세요."
            return
        }
        Task { @MainActor in
            defer { busy = false }
            do {
                let managers = try await NETransparentProxyManager.loadAllFromPreferences()
                let manager = managers.first {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == identifier
                } ?? NETransparentProxyManager()
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = identifier
                configuration.serverAddress = "Kakao Banner"
                manager.protocolConfiguration = configuration
                manager.localizedDescription = "카카오톡 배너 스튜디오"
                manager.isEnabled = true
                try await manager.saveToPreferences()
                isConfigured = true
                status = "네트워크 확장과 프록시 설정을 등록했습니다."
            } catch {
                isConfigured = false
                status = error.localizedDescription
            }
        }
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension replacement: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }
}
