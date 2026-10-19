import Foundation
import ServiceManagement

/// Talks to MacTempHelper. The helper is registered lazily, the first time
/// the user asks for full speed, and macOS then asks them to approve it in
/// System Settings → General → Login Items.
@MainActor
final class FanController: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    /// The state the user asked for until the SMC confirms it. macOS takes
    /// ~5 s to hand fan control over, so the switch must not snap back.
    @Published private(set) var pending: Bool?
    @Published private(set) var error: String?
    /// The XPC call itself failed, e.g. the helper was replaced by a reinstall
    /// while still running; re-enabling it in Login Items restarts it.
    @Published private(set) var helperUnreachable = false
    private var pendingSince: Date?

    private let service = SMAppService.daemon(plistName: HelperConstants.plistName)
    private var connection: NSXPCConnection?

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        status = service.status
    }

    func setFullSpeed(_ enabled: Bool) {
        error = nil
        helperUnreachable = false
        guard ensureRegistered() else { return }

        pending = enabled
        pendingSince = Date()
        let proxy = helperConnection().remoteObjectProxyWithErrorHandler { [weak self] _ in
            DispatchQueue.main.async {
                self?.helperUnreachable = true
                self?.fail("The fan helper isn't responding. Turn MacTemp off and on in Login Items, or restart your Mac.")
            }
        } as? HelperProtocol
        proxy?.setFullSpeed(enabled) { [weak self] message in
            guard let message else { return }
            DispatchQueue.main.async { self?.fail(message) }
        }
    }

    func reconcile(with snapshot: Snapshot) {
        guard let pending, let pendingSince else { return }
        if snapshot.fansForced == pending {
            self.pending = nil
        } else if Date().timeIntervalSince(pendingSince) > 20 {
            fail("The fans didn't respond")
        }
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func ensureRegistered() -> Bool {
        refreshStatus()
        if status == .enabled { return true }
        do {
            try service.register()
        } catch {
            refreshStatus()
            if status != .requiresApproval { self.error = error.localizedDescription }
        }
        refreshStatus()
        if status == .requiresApproval { openLoginItems() }
        return status == .enabled
    }

    private func fail(_ message: String) {
        pending = nil
        error = message
    }

    private func helperConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: HelperConstants.machService, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.setCodeSigningRequirement(HelperConstants.helperRequirement)
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}
