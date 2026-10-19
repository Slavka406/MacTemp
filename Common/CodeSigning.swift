import Foundation
import Security

enum CodeSigning {
    /// The team this binary was signed with. The app group and the XPC trust
    /// checks are derived from it, so whoever builds the project only has to
    /// pick their own team in Xcode.
    static let teamID: String = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
        else { return "" }
        return team
    }()
}
