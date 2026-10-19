import Foundation
import os

let log = Logger(subsystem: "com.shamreliuk.MacTemp.Helper", category: "fans")

// MacTempHelper: a launchd daemon (registered by the app via SMAppService)
// that exposes HelperProtocol over XPC to the signed MacTemp app only.

final class HelperService: NSObject, HelperProtocol {
    private let fans: FanControl

    init(fans: FanControl) {
        self.fans = fans
    }

    func setFullSpeed(_ enabled: Bool, reply: @escaping (String?) -> Void) {
        log.info("Full speed \(enabled ? "on" : "off", privacy: .public) requested")
        let error = fans.setFullSpeed(enabled)
        if let error { log.error("\(error, privacy: .public)") }
        reply(error)
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let fans = FanControl()
    private var clients = 0 // main queue only

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = HelperService(fans: fans)
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.clientLeft() }
        }
        DispatchQueue.main.async { self.clients += 1 }
        connection.resume()
        return true
    }

    // If MacTemp quits or crashes, don't leave the fans roaring. Exiting also
    // lets launchd start a freshly installed helper on the next request.
    private func clientLeft() {
        clients -= 1
        guard clients <= 0 else { return }
        _ = fans.setFullSpeed(false)
        log.info("Last client left; fans back to automatic")
        exit(0)
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machService)
listener.setConnectionCodeSigningRequirement(HelperConstants.appRequirement)
listener.delegate = delegate
listener.resume()
dispatchMain()
