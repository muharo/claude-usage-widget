import SwiftUI

@main
struct ClaudeUsageWidgetApp: App {
    @StateObject private var poller = Poller()

    var body: some Scene {
        // Menu bar only — the host app has no main window. The widget itself
        // lives on the desktop, and this MenuBarExtra is the discrete control
        // surface for refresh / quit / status.
        MenuBarExtra("Claude Usage", systemImage: "gauge.with.dots.needle.bottom.50percent") {
            MenuBarView()
                .environmentObject(poller)
        }
        .menuBarExtraStyle(.window)
        .commands {
            // Suppress unwanted default menus when there's no main window.
            CommandGroup(replacing: .newItem, addition: {})
        }
    }

    // The poller is kicked off in MenuBarView.onAppear — that's the
    // first @MainActor-safe place after @StateObject is initialised.
}
