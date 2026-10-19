import Foundation

/// XPC interface of MacTempHelper, the root daemon that can write to the SMC.
@objc protocol HelperProtocol {
    /// Replies with an error message, or nil on success.
    func setFullSpeed(_ enabled: Bool, reply: @escaping (String?) -> Void)
}

enum HelperConstants {
    static let machService = "com.shamreliuk.MacTemp.Helper"
    static let plistName = "com.shamreliuk.MacTemp.Helper.plist"

    /// Only our signed app may talk to the helper, and only our helper is trusted by the app.
    static let appRequirement = requirement("com.shamreliuk.MacTemp")
    static let helperRequirement = requirement("com.shamreliuk.MacTemp.Helper")

    private static func requirement(_ identifier: String) -> String {
        "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(CodeSigning.teamID)\""
    }
}
