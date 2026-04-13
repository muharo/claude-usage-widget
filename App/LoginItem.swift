import Foundation
import ServiceManagement
import os

/// Thin wrapper around `SMAppService.mainApp` (macOS 13+) for toggling
/// "launch at login". Registering the main app here makes macOS start the
/// host app after the user logs in; the menu-bar icon appears automatically
/// and the `Poller` begins its normal 5-minute cadence.
///
/// No helper bundle or Login Items entitlement is needed — `SMAppService.mainApp`
/// is specifically designed for the "start the same app at login" case.
@MainActor
public final class LoginItem: ObservableObject {

    @Published public private(set) var isEnabled: Bool

    private let log = Logger(subsystem: "com.robert.claude-usage-widget", category: "LoginItem")
    private let service = SMAppService.mainApp

    public init() {
        self.isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    /// Flip the launch-at-login state. Safe to call repeatedly.
    public func setEnabled(_ enable: Bool) {
        do {
            if enable {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            log.error("SMAppService toggle failed: \(error.localizedDescription, privacy: .public)")
        }
        // Re-read the live status — macOS may have declined (e.g. the user
        // needs to approve in System Settings → General → Login Items).
        isEnabled = (service.status == .enabled)
    }

    /// Whether macOS is holding our registration for user approval. When
    /// `true`, the user needs to visit System Settings → General → Login
    /// Items to enable the app.
    public var requiresApproval: Bool {
        service.status == .requiresApproval
    }
}
