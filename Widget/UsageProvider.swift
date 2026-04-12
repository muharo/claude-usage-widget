import WidgetKit
import Foundation
import os

/// Reads the snapshot the host app writes to the shared store.
///
/// The widget extension is sandboxed and must NEVER touch the macOS Keychain
/// or CredentialsProvider directly — that triggers repeated permission dialogs.
/// Token access is handled exclusively by the host app (ClaudeUsageWidget.app),
/// which caches both the snapshot and the raw token string to the shared store.
struct UsageProvider: TimelineProvider {
    private let store = SharedStore()
    private let service = UsageService()
    private let log = Logger(subsystem: "com.robert.claude-usage-widget", category: "UsageProvider")

    func placeholder(in context: Context) -> UsageEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snap = store.read()
        let stale = snap.map { Date().timeIntervalSince($0.fetchedAt) > 5 * 60 } ?? true
        completion(UsageEntry(date: Date(), snapshot: snap ?? .placeholder, isStale: stale))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let entry = await buildEntry()
            // 5-minute safety-net reload. Host app normally drives reloads via
            // WidgetCenter.reloadTimelines after each successful fetch.
            let next = Date().addingTimeInterval(5 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    // MARK: - Entry building

    private func buildEntry() async -> UsageEntry {
        // 1. Prefer the cached snapshot — fast, no network, no auth dialogs.
        if let snap = store.read() {
            let stale = Date().timeIntervalSince(snap.fetchedAt) > 5 * 60
            log.info("using cached snapshot (stale=\(stale))")
            return UsageEntry(date: Date(), snapshot: snap, isStale: stale)
        }

        // 2. No cached snapshot yet — try a direct API fetch using ONLY the
        //    token the host app cached. Never touch CredentialsProvider or
        //    the Keychain from inside the widget extension.
        log.info("no cached snapshot, attempting direct fetch via host-cached token")
        return await directFetchWithCachedToken()
    }

    private func directFetchWithCachedToken() async -> UsageEntry {
        guard let token = store.readToken() else {
            // Host app hasn't run yet — prompt the user to open it.
            log.warning("no cached token — host app not launched")
            return UsageEntry(date: Date(), snapshot: nil, isStale: false)
        }

        do {
            let snap = try await service.fetch(token: token)
            store.write(snap)
            log.info("direct fetch succeeded")
            return UsageEntry(date: Date(), snapshot: snap, isStale: false)
        } catch {
            log.error("direct fetch failed: \(error.localizedDescription, privacy: .public)")
            return UsageEntry(date: Date(), snapshot: nil, isStale: false)
        }
    }
}
