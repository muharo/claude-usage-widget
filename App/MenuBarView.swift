import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var poller: Poller

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if let snap = poller.lastSnapshot {
                snapshotSection(snap)
            } else {
                Text("Fetching first data…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Divider()
            statusFooter
            HStack {
                Button {
                    Task { await poller.fetchNow() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(poller.status.isFetching)
                Text("every")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("", selection: $poller.pollIntervalIndex) {
                    ForEach(Poller.availableIntervals.indices, id: \.self) { i in
                        Text(Poller.availableIntervals[i].label).tag(i)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                .font(.caption2)
            }
        }
        .padding(14)
        .frame(width: 290)
        .onAppear { poller.start() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .foregroundStyle(Theme.ringHealthy)
            Text("Claude Usage")
                .font(.headline)
            Spacer()
            if poller.status.isFetching {
                ProgressView().controlSize(.small)
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    // MARK: - Snapshot rows

    @ViewBuilder
    private func snapshotSection(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let f = snap.fiveHour {
                row(icon: "clock.fill", title: "5-hour session",
                    pct: f.utilization, resets: f.resetsAt)
            }
            if let w = snap.sevenDay {
                row(icon: "calendar", title: "Weekly",
                    pct: w.utilization, resets: w.resetsAt)
            }
            if let e = snap.extraUsage, e.isEnabled {
                row(icon: "creditcard.fill", title: "Extra usage",
                    pct: e.utilization, resets: nil,
                    detail: String(format: "$%.2f used / $%.2f limit",
                                   e.usedUSD, e.limitUSD))
            }
            if let plan = snap.planName {
                Text("Plan: \(plan)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(
        icon: String, title: String,
        pct: Double, resets: Date?,
        detail: String? = nil
    ) -> some View {
        HStack(spacing: 10) {
            RingView(utilization: pct, lineWidth: 4)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Image(systemName: icon).font(.caption)
                    Text(title).font(.caption).bold()
                    Spacer()
                    Text("\(Int(pct * 100))%")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(Theme.ringColor(for: pct))
                }
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                } else if let resets {
                    (Text("Resets ") + Text(resets, style: .relative))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Status footer

    @ViewBuilder
    private var statusFooter: some View {
        switch poller.status {
        case .idle:
            EmptyView()
        case .fetching:
            Text("Fetching…").font(.caption2).foregroundStyle(.secondary)
        case .ok(let date):
            HStack(spacing: 4) {
                Circle().fill(Theme.ringHealthy).frame(width: 6, height: 6)
                (Text("Updated ") + Text(date, style: .relative))
            }
            .font(.caption2).foregroundStyle(.secondary)
        case .rateLimited:
            HStack(spacing: 4) {
                Circle().fill(Theme.ringWarn).frame(width: 6, height: 6)
                Text("Rate limited")
            }
            .font(.caption2).foregroundStyle(Theme.ringWarn)
        case .error(let msg, _):
            HStack(alignment: .top, spacing: 4) {
                Circle().fill(Theme.ringCrit).frame(width: 6, height: 6).padding(.top, 4)
                ScrollView {
                    Text(msg).font(.caption2).foregroundStyle(Theme.ringCrit)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 80)
            }
        }
    }
}

#if DEBUG
struct MenuBarView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarView().environmentObject(Poller())
    }
}
#endif
