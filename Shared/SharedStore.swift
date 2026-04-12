import Foundation
import os

/// Reads/writes the snapshot and cached token to every location that either
/// the host app or the sandboxed widget extension can reach.
///
/// Three write targets (best-effort, all attempted on every write):
///
///  1. `~/Library/Application Support/ClaudeUsageWidget/`          ← host-app primary
///     Accessed via getpwuid so the real home is used even inside a sandbox.
///
///  2. `~/Library/Group Containers/<group-id>/`                    ← App Group
///     The host app constructs this path manually (non-sandboxed processes
///     get nil from containerURL). The widget uses containerURL normally.
///     Requires the App Group to be provisioned (paid developer account).
///
///  3. `~/Library/Containers/<widget-bundle-id>/Data/Library/Application Support/ClaudeUsageWidget/`
///     The widget extension's *own* container. The non-sandboxed host app can
///     write there freely. Inside the widget sandbox, Application Support maps
///     to exactly this path — no App Group provisioning needed.
///
/// Read order tries #2 and #3 first (the widget-accessible paths), then #1.
public final class SharedStore {

    // MARK: - Constants

    public  static let appGroupIdentifier  = "group.com.robert.claude-usage-widget"
    private static let widgetBundleID      = "com.robert.ClaudeUsageWidget.WidgetExtension"
    private static let snapshotFile        = "snapshot.json"
    private static let tokenFile           = "token.json"

    private let log = Logger(subsystem: "com.robert.claude-usage-widget", category: "SharedStore")

    // MARK: - Init

    public init() {
        for dir in writeDirs { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    }

    // MARK: - Directory resolution

    /// Real `~/Library/Application Support/ClaudeUsageWidget/` (host app).
    public var primaryDir: URL {
        realHome().appendingPathComponent("Library/Application Support/ClaudeUsageWidget", isDirectory: true)
    }

    /// App Group container — sandboxed widget uses `containerURL`; host app
    /// constructs the path by hand since `containerURL` returns nil when unsandboxed.
    private var appGroupDir: URL? {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            return url
        }
        let candidate = realHome().appendingPathComponent("Library/Group Containers/\(Self.appGroupIdentifier)", isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Widget extension's own Application Support, inside its sandbox container.
    /// The host app (non-sandboxed) can always write here directly.
    private var widgetContainerDir: URL {
        realHome().appendingPathComponent(
            "Library/Containers/\(Self.widgetBundleID)/Data/Library/Application Support/ClaudeUsageWidget",
            isDirectory: true)
    }

    /// Inside the widget sandbox `FileManager.urls(for: .applicationSupport)`
    /// transparently resolves to the container path — no getpwuid needed.
    private var sandboxedAppSupportDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first.map { $0.appendingPathComponent("ClaudeUsageWidget", isDirectory: true) }
    }

    public static func realHome() -> URL {
        if let pw = getpwuid(getuid()), let cstr = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: cstr))
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }
    private func realHome() -> URL { Self.realHome() }

    /// All directories the current process should write to.
    private var writeDirs: [URL] {
        var dirs: [URL] = [primaryDir, widgetContainerDir]
        if let ag = appGroupDir { dirs.append(ag) }
        return dirs
    }

    /// All candidate file URLs to try when reading, most-widget-accessible first.
    private func candidateURLs(_ fileName: String) -> [URL] {
        var urls: [URL] = []
        // Sandbox-transparent path (works perfectly inside the widget extension).
        if let d = sandboxedAppSupportDir { urls.append(d.appendingPathComponent(fileName)) }
        // App Group (if provisioned).
        if let d = appGroupDir            { urls.append(d.appendingPathComponent(fileName)) }
        // Widget container & host-app primary.
        urls.append(widgetContainerDir.appendingPathComponent(fileName))
        urls.append(primaryDir.appendingPathComponent(fileName))
        return urls
    }

    // MARK: - Snapshot

    public func write(_ snapshot: UsageSnapshot) {
        guard let data = try? UsageSnapshot.jsonEncoder.encode(snapshot) else { return }
        for dir in writeDirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(Self.snapshotFile)
            do {
                try data.write(to: url, options: [.atomic])
                log.debug("snapshot → \(url.path, privacy: .public)")
            } catch {
                log.error("snapshot write \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func read() -> UsageSnapshot? {
        for url in candidateURLs(Self.snapshotFile) {
            if let snap = decode(from: url) { return snap }
        }
        return nil
    }

    private func decode(from url: URL) -> UsageSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try UsageSnapshot.jsonDecoder.decode(UsageSnapshot.self, from: data)
        } catch {
            log.error("decode \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Token cache

    public func writeToken(_ token: String) {
        let dict = ["access_token": token, "cached_at": ISO8601DateFormatter().string(from: Date())]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        for dir in writeDirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: dir.appendingPathComponent(Self.tokenFile), options: [.atomic])
        }
    }

    public func readToken() -> String? {
        for url in candidateURLs(Self.tokenFile) {
            if let data = try? Data(contentsOf: url),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                return dict["access_token"]
            }
        }
        return nil
    }
}
