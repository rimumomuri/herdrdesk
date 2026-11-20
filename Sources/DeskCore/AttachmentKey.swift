import CryptoKit
import Foundation

/// Storage key for a terminal's draft attachments. A role key is used only while exactly one live terminal holds
/// that role; otherwise the key is bound to the terminal's address and session, so twins never share attachments.
public enum AttachmentKey {
    public static func make(for term: Term, among terms: [Term]) -> String? {
        if let role = term.role {
            guard role != ".", role != "..", role.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil else { return nil }
            if terms.filter({ $0.role == role && $0.state == "live" }).count <= 1 { return role }
        }
        let digest = SHA256.hash(data: Data((term.address + ":" + term.session).utf8))
        return "session-" + digest.prefix(20).map { String(format: "%02x", $0) }.joined()
    }
}
