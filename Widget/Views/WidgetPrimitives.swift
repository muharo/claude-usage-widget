import SwiftUI
import WidgetKit

// MARK: - Refresh button (interactive widget, macOS 14+)

@available(macOS 14.0, *)
struct RefreshButton: View {
    var body: some View {
        Button(intent: RefreshIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(6)
                .background(Color.white.opacity(0.10))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stale badge

struct StaleBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Theme.ringWarn).frame(width: 6, height: 6)
            Text("stale")
                .font(.caption2)
                .foregroundStyle(Theme.ringWarn)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Theme.ringWarn.opacity(0.10))
        .clipShape(Capsule())
    }
}

// MARK: - Extra-usage bar

struct ExtraUsageBar: View {
    let extra: UsageSnapshot.ExtraUsage
    var showsBalance: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Text("Extra usage")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(format: "$%.2f / $%.2f", extra.usedUSD, extra.limitUSD))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.ringTrack)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.ringColor(for: extra.utilization))
                        .frame(width: max(geo.size.width * extra.utilization, 4), height: 6)
                }
            }
            .frame(height: 6)

            if showsBalance {
                Text(String(format: "Balance: $%.2f", extra.balanceUSD))
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

// MARK: - Empty / unauthenticated state

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "app.badge.checkmark")
                .font(.title2)
                .foregroundStyle(Theme.ringWarn)
            Text("No data yet")
                .font(.caption.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Open ClaudeUsageWidget.app")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - widgetBackground compatibility shim

extension View {
    /// Shim so we can call `.widgetBackground(...)` on macOS 13 and 14+.
    /// macOS 14 introduced `containerBackground(_:for:)` for widgets and
    /// requires it for proper rendering on the desktop.
    @ViewBuilder
    func widgetBackground<Background: View>(_ background: Background) -> some View {
        if #available(macOS 14.0, *) {
            self.containerBackground(for: .widget) { background }
        } else {
            self.background(background)
        }
    }
}
