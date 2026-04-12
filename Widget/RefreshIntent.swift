import AppIntents
import WidgetKit

/// Wired to the refresh button rendered inside the widget (macOS 14+).
/// Fetches fresh data using the token the host app cached, writes the
/// snapshot, then asks WidgetKit to reload — all from the widget extension.
@available(macOS 14.0, *)
struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Claude Usage"
    static var description = IntentDescription("Fetches fresh usage data.")

    func perform() async throws -> some IntentResult {
        let store = SharedStore()
        guard let token = store.readToken() else { return .result() }
        let service = UsageService()
        if let snap = try? await service.fetch(token: token) {
            store.write(snap)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ClaudeUsageWidget")
        return .result()
    }
}
