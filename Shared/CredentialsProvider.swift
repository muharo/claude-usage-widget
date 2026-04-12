import Foundation

/// Locates the Claude Code OAuth access token from one of two well-known
/// places, in order of preference:
///
/// 1. macOS Keychain entry `Claude Code-credentials` (what `claude /login`
///    writes on macOS).
/// 2. The plaintext fallback at `~/.claude/.credentials.json` (older versions
///    and CI environments).
///
/// We never write credentials — we only read them.
public enum CredentialsProvider {

    public struct AccessToken {
        public let value: String
        public let expiresAt: Date?
        public let source: Source

        public enum Source: String {
            case keychain
            case credentialsFile
        }
    }

    public enum CredentialsError: Error, LocalizedError {
        case notFound
        case malformed(String)

        public var errorDescription: String? {
            switch self {
            case .notFound:
                return "Could not find Claude Code credentials. Install Claude Code and run `claude /login`."
            case .malformed(let detail):
                return "Claude Code credentials are present but malformed: \(detail)"
            }
        }
    }

    /// On-disk shape of `.credentials.json`. We only need a couple of fields.
    private struct CredentialsFile: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Int?     // milliseconds since epoch
        }
        let claudeAiOauth: OAuth
    }

    public static func currentAccessToken() throws -> AccessToken {
        // 1. Try Keychain first.
        if let token = try? readFromKeychain() {
            return token
        }
        // 2. Fall back to ~/.claude/.credentials.json
        if let token = try? readFromCredentialsFile() {
            return token
        }
        throw CredentialsError.notFound
    }

    // MARK: - Keychain path

    private static func readFromKeychain() throws -> AccessToken {
        let blob = try KeychainHelper.readClaudeCodeCredentialsBlob()
        let decoded: CredentialsFile
        do {
            decoded = try JSONDecoder.snake.decode(CredentialsFile.self, from: blob)
        } catch {
            throw CredentialsError.malformed("keychain JSON: \(error.localizedDescription)")
        }
        let expiresAt = decoded.claudeAiOauth.expiresAt.map {
            Date(timeIntervalSince1970: TimeInterval($0) / 1000.0)
        }
        return AccessToken(
            value: decoded.claudeAiOauth.accessToken,
            expiresAt: expiresAt,
            source: .keychain
        )
    }

    // MARK: - Filesystem fallback

    private static func readFromCredentialsFile() throws -> AccessToken {
        let url = realHomeDirectory()
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent(".credentials.json", isDirectory: false)

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CredentialsError.notFound
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CredentialsError.malformed("read \(url.path): \(error.localizedDescription)")
        }
        let decoded: CredentialsFile
        do {
            decoded = try JSONDecoder.snake.decode(CredentialsFile.self, from: data)
        } catch {
            throw CredentialsError.malformed("decode \(url.lastPathComponent): \(error.localizedDescription)")
        }
        let expiresAt = decoded.claudeAiOauth.expiresAt.map {
            Date(timeIntervalSince1970: TimeInterval($0) / 1000.0)
        }
        return AccessToken(
            value: decoded.claudeAiOauth.accessToken,
            expiresAt: expiresAt,
            source: .credentialsFile
        )
    }

    /// Returns the user's REAL home directory, bypassing the App Sandbox
    /// rewrite. Inside a sandboxed widget extension `NSHomeDirectory()` would
    /// return the per-extension container; `getpwuid` reaches the actual
    /// `/Users/<name>` path so we can read `~/.claude/`.
    public static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let cstr = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: cstr))
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }
}

private extension JSONDecoder {
    static let snake: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
