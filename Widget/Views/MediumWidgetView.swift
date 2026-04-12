import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        ZStack {
            Theme.background

            if let snap = entry.snapshot {
                VStack(spacing: 4) {
                    // Top bar: refresh button pinned to the trailing edge
                    // with identical top/trailing insets so it sits
                    // symmetrically in the corner.
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if #available(macOS 14.0, *) { RefreshButton() }
                    }

                    rings(snap: snap)

                    Spacer(minLength: 0)
                }
                .padding(12)
            } else {
                EmptyState()
            }
        }
        .widgetBackground(Color.clear)
    }

    // MARK: - Ring row

    private func rings(snap: UsageSnapshot) -> some View {
        HStack(spacing: 8) {
            ring(icon: "clock.fill",      title: "5-hour",
                 util: snap.fiveHour?.utilization ?? 0,
                 sub:  resetText(snap.fiveHour?.resetsAt))
            ring(icon: "calendar",        title: "Weekly",
                 util: snap.sevenDay?.utilization ?? 0,
                 sub:  resetText(snap.sevenDay?.resetsAt))
            if let e = snap.extraUsage, e.isEnabled {
                ring(icon: "creditcard.fill", title: "Extra",
                     util: e.utilization,
                     sub:  String(format: "$%.2f / $%.2f", e.usedUSD, e.limitUSD))
            }
        }
    }

    // MARK: - Ring tile

    private func ring(icon: String, title: String, util: Double, sub: String) -> some View {
        VStack(spacing: 4) {
            RingView(utilization: util, lineWidth: 7, icon: icon, label: "\(Int(util * 100))%")
                .frame(width: 58, height: 58)

            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(Theme.textPrimary)

            Text(sub)
                .font(.system(size: 9))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "resetting…" }
        let hours = Int(diff / 3600)
        let mins  = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 { return "resets \(hours)h \(mins)m" }
        return "resets \(mins)m"
    }
}
