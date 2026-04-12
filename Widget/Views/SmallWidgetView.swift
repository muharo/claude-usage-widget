import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
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
            let util   = snap.fiveHour?.utilization ?? 0
            let resets = snap.fiveHour?.resetsAt
            VStack(spacing: 6) {
                Spacer(minLength: 6)
                RingView(utilization: util, lineWidth: 9, icon: "clock.fill",
                         label: "\(Int(util * 100))%")
                    .frame(width: 76, height: 76)

                Text("5-hour")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textPrimary)

                Group {
                    if let resets {
                        Text("Resets ") + Text(resets, style: .relative)
                    } else {
                        Text(" ")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            }
        } else {
            EmptyState()
        }
    }
}
