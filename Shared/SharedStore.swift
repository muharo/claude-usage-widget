import Foundation
import os

/// Handoff between the unsandboxed host app and the sandboxed widget
/// extension, in an environment with **no App Group** (free personal team
/// signing cannot provision App Groups, and temp-exception file entitlements
/// are silently stripped from the signed bundle — verified via
/// `codesign -d --entitlements -`).
///
/// With those two options off the table, the only path that actually works
/// is to have the host write into the widget extension's own sandbox
/// container at
/// `~/Library/Containers/<widget-bundle>/Data/Library/Application Support/…`.
/// From inside the widget that's just its own Application Support directory
/// (free read/write). From the unsandboxed host it's "another app's
/// container", which on macOS 14+ triggers the TCC dialog
/// "ClaudeUsageWidget would like to access data from other apps" **once**.
/// After the user clicks Allow, macOS remembers the decision keyed on the
/// app's code signature, so subsequent launches don't re-prompt — as long
/// as the signature stays stable across rebuilds (set a stable
/// `DEVELOPMENT_TEAM` in `project.yml`).
///
/// The host *also* writes to `~/.claudeusagewidget/` as a no-TCC safety
/// fallback. That path is readable by the host itself and by external
/// tools (useful for debugging), but the widget sandbox cannot read it
/// without the stripped entitlement, so it's only a secondary cache.
///
/// The host never *reads* from `widgetContainerDir` — even a `fileExists`
/// check from the unsandboxed side would retrigger TCC. It only writes.
/// The widget reads primarily from `widgetContainerDir` (its own home).
public final class SharedStore {

    // MARK: - Constants

    public  static let appGroupIdentifier  = "group.com.robert.claude-usage-widget"
    private static let widgetBundleID      = "com.robert.ClaudeUsageWidget.WidgetExtension"
    private static let sharedDirName       = ".claudeusagewidget"
    private static let snapshotFile        = "snapshot.json"
    private static let tokenFile           = "token.json"

    private let log = Logger(subsystem: "com.robert.claude-usage-widget", category: "SharedStore")

    // MARK: - Init

    public init() {
        for dir in writeDirs { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    }

    // MARK: - Directory resolution

    /// Canonical host↔widget handoff directory: `~/.claudeusagewidget/`.
    /// Resolved via `getpwuid` so the widget sandbox sees the real home path
    /// instead of its per-extension container.
    private var sharedDataDir: URL {
        realHome().appendingPathComponent(Self.sharedDirName, isDirectory: true)
    }

    /// Legacy path: `~/Library/Application Support/ClaudeUsageWidget/`.
    /// Kept for READ fallback when upgrading from older builds that wrote
    /// there. Not written to anymore — the widget sandbox can't read it.
    public var primaryDir: URL {
        realHome().appendingPathComponent("Library/Application Support/ClaudeUsageWidget", isDirectory: true)
    }

    /// App Group container. Only queried from the sandboxed widget — the
    /// unsandboxed host has no App Group entitlement (and provisioning one
    /// requires a paid developer account), so from the host side
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` would either
    /// return nil or probe into `~/Library/Group Containers/` and trigger
    /// the "access data from other apps" TCC dialog. We skip the entire
    /// call on the host to stay silent.
    private var appGroupDir: URL? {
        guard isSandboxed else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
    }

    /// Widget extension's own Application Support, inside its sandbox
    /// container. Only written to from inside the widget process itself.
    /// The host app never reads or writes here — on macOS Sonoma+, accessing
    /// another app's `~/Library/Containers/…` triggers the TCC prompt.
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

    /// True when the current process runs inside an App Sandbox container.
    /// Non-sandboxed processes see `NSHomeDirectory()` resolve to the real
    /// user home; sandboxed ones see it rewritten to the per-process
    /// container root.
    private var isSandboxed: Bool {
        NSHomeDirectory() != Self.realHome().path
    }

    /// All directories the current process should write to.
    ///
    /// **Host (unsandboxed):** writes to `widgetContainerDir` (the widget's
    /// own sandbox container — the primary handoff path, gated by a one-time
    /// TCC Allow) AND to `sharedDataDir` (a no-TCC safety cache in the user's
    /// real home dot-directory, useful for debugging and external tools).
    ///
    /// **Widget (sandboxed):** writes to `widgetContainerDir` (its own
    /// Application Support, free). Also writes to `sharedDataDir` — though
    /// the temp-exception entitlement that was meant to allow this gets
    /// stripped during personal-team signing, so these writes silently fail.
    /// Harmless. `sharedDataDir` ends up populated only by the host.
    private var writeDirs: [URL] {
        var dirs: [URL] = [widgetContainerDir, sharedDataDir]
        if let ag = appGroupDir { dirs.append(ag) }
        return dirs
    }

    /// All candidate file URLs to try when reading, most-preferred first.
    ///
    /// Conditional on sandbox state. The unsandboxed host MUST NOT probe
    /// `widgetContainerDir` — even a `fileExists` check retriggers the TCC
    /// "access data from other apps" prompt. The widget reads from its own
    /// container first (the path that actually holds data).
    private func candidateURLs(_ fileName: String) -> [URL] {
        var urls: [URL] = []

        if isSandboxed {
            // Widget extension: read from its own container first. This is
            // where the host writes after clearing the one-time TCC prompt,
            // and where the widget's own RefreshIntent writes.
            if let d = sandboxedAppSupportDir {
                urls.append(d.appendingPathComponent(fileName))
            }
            urls.append(widgetContainerDir.appendingPathComponent(fileName))
        }

        // Shared dot-directory. Populated by the host as a no-TCC safety
        // cache; the widget can't actually read it (temp-exception
        // entitlement stripped by personal-team signing) but the host
        // reads it back when running locally.
        urls.append(sharedDataDir.appendingPathComponent(fileName))

        // App Group — only if provisioned (paid developer account).
        if let d = appGroupDir {
            urls.append(d.appendingPathComponent(fileName))
        }

        // Legacy Application Support read fallback from older builds.
        // Host-only — the widget sandbox can't read ~/Library/Application Support/.
        if !isSandboxed {
            urls.append(primaryDir.appendingPathComponent(fileName))
        }

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
        log.info("read snapshot: sandboxed=\(self.isSandboxed, privacy: .public)")
        for url in candidateURLs(Self.snapshotFile) {
            let exists = FileManager.default.fileExists(atPath: url.path)
            log.info("  try \(url.path, privacy: .public) exists=\(exists, privacy: .public)")
            if !exists { continue }
            do {
                let data = try Data(contentsOf: url)
                let snap = try UsageSnapshot.jsonDecoder.decode(UsageSnapshot.self, from: data)
                log.info("  ✓ decoded \(url.path, privacy: .public)")
                return snap
            } catch {
                log.error("  ✗ \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        log.warning("read snapshot: no candidate produced data")
        return nil
    }

    // MARK: - Token cache

    public func writeToken(_ token: String) {
        let dict = ["access_token": token, "cached_at": ISO8601DateFormatter().string(from: Date())]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        for dir in writeDirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(Self.tokenFile)
            do {
                try data.write(to: url, options: [.atomic])
                log.debug("token → \(url.path, privacy: .public)")
            } catch {
                log.error("token write \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func readToken() -> String? {
        log.info("read token: sandboxed=\(self.isSandboxed, privacy: .public)")
        for url in candidateURLs(Self.tokenFile) {
            let exists = FileManager.default.fileExists(atPath: url.path)
            log.info("  try \(url.path, privacy: .public) exists=\(exists, privacy: .public)")
            if !exists { continue }
            do {
                let data = try Data(contentsOf: url)
                if let dict = try JSONSerialization.jsonObject(with: data) as? [String: String],
                   let tok = dict["access_token"] {
                    log.info("  ✓ token from \(url.path, privacy: .public)")
                    return tok
                }
            } catch {
                log.error("  ✗ \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        log.warning("read token: no candidate produced data")
        return nil
    }
}
