import Foundation
import Security

/// Reads OAuth credentials from the macOS Keychain entry that Claude Code
/// itself writes when you run `claude /login`.
///
/// The entry is a `kSecClassGenericPassword` with `kSecAttrService ==
/// "Claude Code-credentials"`. Its data is a JSON blob:
///
///   { "claudeAiOauth": { "accessToken": "sk-...", "refreshToken": "...",
///                        "expiresAt": 1740000000000 } }
///
/// We pass `kSecUseAuthenticationUISkip` so the user isn't prompted on every
/// poll. macOS will still prompt once on first use to grant the host app
/// access to the keychain item.
public enum KeychainHelper {
    public enum KeychainError: Error, LocalizedError {
        case itemNotFound
        case unexpectedData
        case osStatus(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Claude Code keychain entry not found. Run `claude /login` first."
            case .unexpectedData:
                return "Claude Code keychain entry has unexpected format."
            case .osStatus(let status):
                return "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
            }
        }
    }

    public static let serviceName = "Claude Code-credentials"

    /// Returns the raw JSON data stored in the keychain entry, or throws.
    public static func readClaudeCodeCredentialsBlob() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else { throw KeychainError.itemNotFound }
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
        guard let data = item as? Data else { throw KeychainError.unexpectedData }
        return data
    }
}
