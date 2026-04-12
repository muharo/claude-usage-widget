import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        ZStack {
            Theme.background
            content.padding(14)
        }
        .widgetBackground(Color.clear)
    }

    @ViewBuilder
    private var content: some View {
        if let snap = entry.snapshot {
            VStack(spacing: 10) {
                header(snap: snap)
                grid(snap: snap)
                Spacer(minLength: 0)
                footer(snap: snap)
            }
        } else {
            EmptyState()
        }
    }

    // MARK: - Header

    private func header(snap: UsageSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .foregroundStyle(Theme.ringHealthy)
            Text("Claude Usage")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if let plan = snap.planName {
                Text(plan.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.ringHealthy.opacity(0.18))
                    .foregroundStyle(Theme.ringHealthy)
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
            if #available(macOS 14.0, *) { RefreshButton() }
        }
    }

    // MARK: - 2 × 2 grid (fixed-size rings so header/footer always fit)

    private func grid(snap: UsageSnapshot) -> some View {
        let e = snap.extraUsage?.isEnabled == true ? snap.extraUsage : nil
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                bigRing(icon: "clock.fill",  title: "5-hour",
                        util: snap.fiveHour?.utilization ?? 0,
                        resets: snap.fiveHour?.resetsAt)
                bigRing(icon: "calendar",    title: "Weekly",
                        util: snap.sevenDay?.utilization ?? 0,
                        resets: snap.sevenDay?.resetsAt)
            }

            Spacer(minLength: 0)

            if let e {
                HStack(spacing: 12) {
                    bigRing(icon: "creditcard.fill", title: "Extra",
                            util: e.utilization,
                            detail: String(format: "$%.2f / $%.2f", e.usedUSD, e.limitUSD))
                    infoPanel(snap: snap, extra: e)
                }
            }
        }
    }

    // MARK: - Ring tile

    private func bigRing(
        icon: String, title: String, util: Double,
        resets: Date? = nil, detail: String? = nil
    ) -> some View {
        VStack(spacing: 4) {
            RingView(utilization: util, lineWidth: 9, icon: icon, label: "\(Int(util * 100))%")
                .frame(width: 72, height: 72)

            Text(title)
                .font(.caption.bold())
                .foregroundStyle(Theme.textPrimary)

            Group {
                if let resets {
                    Text("Resets ") + Text(resets, style: .relative)
                } else if let detail {
                    Text(detail)
                } else {
                    Text(" ")
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Info panel (bottom-right cell)

    private func infoPanel(snap: UsageSnapshot, extra: UsageSnapshot.ExtraUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(label: "Used",      value: String(format: "$%.2f", extra.usedUSD))
            infoRow(label: "Limit",     value: String(format: "$%.2f", extra.limitUSD))
            infoRow(label: "Remaining", value: String(format: "$%.2f", extra.balanceUSD))

            if let plan = snap.planName {
                Divider().overlay(Theme.textTertiary.opacity(0.3))
                infoRow(label: "Plan", value: plan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.caption2.bold())
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
    }

    // MARK: - Footer

    private func footer(snap: UsageSnapshot) -> some View {
        HStack {
            if entry.isStale { StaleBadge() }
            Spacer()
            (Text("Updated ") + Text(snap.fetchedAt, style: .relative))
        }
        .font(.caption2)
        .foregroundStyle(Theme.textTertiary)
    }
}
