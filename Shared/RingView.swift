import SwiftUI

/// A circular progress ring with a centered label. Used by every widget size
/// and by the menu-bar popover.
public struct RingView: View {
    public let utilization: Double          // 0 ... 1
    public let lineWidth: CGFloat
    public let icon: String?                // SF Symbol
    public let label: String?               // typically the percentage

    public init(
        utilization: Double,
        lineWidth: CGFloat = 8,
        icon: String? = nil,
        label: String? = nil
    ) {
        self.utilization = max(0, min(utilization, 1))
        self.lineWidth = lineWidth
        self.icon = icon
        self.label = label
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.ringTrack, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: utilization)
                .stroke(
                    Theme.ringColor(for: utilization),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: utilization)

            VStack(spacing: 2) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: lineWidth * 1.4, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                if let label {
                    Text(label)
                        .font(.system(size: lineWidth * 1.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
            }
        }
    }
}

#if DEBUG
struct RingView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            HStack(spacing: 24) {
                RingView(utilization: 0.42, lineWidth: 10, icon: "clock.fill", label: "42%")
                RingView(utilization: 0.78, lineWidth: 10, icon: "calendar", label: "78%")
                RingView(utilization: 0.95, lineWidth: 10, icon: "creditcard.fill", label: "95%")
            }
            .frame(width: 360, height: 120)
        }
        .frame(width: 400, height: 160)
    }
}
#endif
