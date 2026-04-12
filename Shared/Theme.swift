import SwiftUI

/// Centralised colors / fonts so the widget and the menu-bar popover stay
/// visually aligned with the inspiration screenshot (dark teal background,
/// neon green progress rings).
public enum Theme {
    // Background gradient
    public static let bgTop    = Color(red: 0.04, green: 0.18, blue: 0.21)   // ≈ #0A2E34
    public static let bgBottom = Color(red: 0.02, green: 0.10, blue: 0.13)   // ≈ #061821

    // Ring colors keyed off utilization
    public static let ringHealthy = Color(red: 0.00, green: 0.88, blue: 0.64) // ≈ #00E0A4
    public static let ringWarn    = Color(red: 1.00, green: 0.69, blue: 0.13) // ≈ #FFB020
    public static let ringCrit    = Color(red: 1.00, green: 0.32, blue: 0.32) // ≈ #FF5252

    // Track behind the rings
    public static let ringTrack   = Color.white.opacity(0.10)

    // Text
    public static let textPrimary   = Color.white
    public static let textSecondary = Color.white.opacity(0.65)
    public static let textTertiary  = Color.white.opacity(0.45)

    public static func ringColor(for utilization: Double) -> Color {
        switch utilization {
        case ..<0.60: return ringHealthy
        case ..<0.85: return ringWarn
        default:      return ringCrit
        }
    }

    public static var background: some View {
        LinearGradient(
            colors: [bgTop, bgBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
