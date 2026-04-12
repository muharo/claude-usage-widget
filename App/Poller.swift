import Foundation
import WidgetKit
import os

/// Owns the background polling loop that keeps the widget up to date.
/// The menu bar popover reflects the same data but does not need a manual
/// refresh — opening it just shows whatever the last poll fetched.
@MainActor
public final class Poller: ObservableObject {

    public enum Status: Equatable {
        case idle
        case fetching
        case ok(Date)
        case rateLimited
        case error(String, Date)

        public var isFetching: Bool {
            if case .fetching = self { return true } else { return false }
        }
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var lastSnapshot: UsageSnapshot?

    // MARK: - Configurable poll interval

    public static let availableIntervals: [(label: String, seconds: TimeInterval)] = [
        ("1 minute",   1 * 60),
        ("2 minutes",  2 * 60),
        ("5 minutes",  5 * 60),
        ("10 minutes", 10 * 60),
        ("15 minutes", 15 * 60),
    ]

    /// Persisted index into `availableIntervals`. Changing it restarts the timer.
    @Published public var pollIntervalIndex: Int {
        didSet {
            UserDefaults.standard.set(pollIntervalIndex, forKey: "pollIntervalIndex")
            if timer != nil { restartTimer() }
        }
    }

    private var pollInterval: TimeInterval {
        Self.availableIntervals[min(pollIntervalIndex, Self.availableIntervals.count - 1)].seconds
    }

    // MARK: - Internals

    private let store   = SharedStore()
    private let service = UsageService()
    private let log     = Logger(subsystem: "com.robert.claude-usage-widget", category: "Poller")

    private var timer:              Timer?
    private var rateLimitClearTask: Task<Void, Never>?
    private var lastOkDate:         Date?

    // MARK: - Lifecycle

    public init() {
        let saved = UserDefaults.standard.integer(forKey: "pollIntervalIndex")
        self.pollIntervalIndex = UserDefaults.standard.object(forKey: "pollIntervalIndex") != nil ? saved : 2
        self.lastSnapshot = store.read()
    }

    public func start() {
        guard timer == nil else { return }
        Task { await fetchNow() }
        scheduleTimer()
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        rateLimitClearTask?.cancel()
    }

    private func restartTimer() {
        timer?.invalidate(); timer = nil
        scheduleTimer()
    }

    private func scheduleTimer() {
        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.fetchNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Fetch

    public func fetchNow() async {
        guard !status.isFetching else { return }
        status = .fetching
        do {
            let token = try CredentialsProvider.currentAccessToken()
            store.writeToken(token.value)

            let snap = try await service.fetch(token: token.value)
            store.write(snap)
            lastSnapshot = snap
            let now = Date()
            lastOkDate = now
            status = .ok(now)
            log.info("fetched 5h=\(Int((snap.fiveHour?.utilization ?? 0) * 100))% 7d=\(Int((snap.sevenDay?.utilization ?? 0) * 100))%")
            WidgetCenter.shared.reloadTimelines(ofKind: "ClaudeUsageWidget")
        } catch let UsageService.ServiceError.http(code, _) where code == 429 {
            status = .rateLimited
            log.warning("rate limited (429)")
            scheduleRateLimitClear()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = .error(msg, Date())
            log.error("fetch failed: \(msg, privacy: .public)")
        }
    }

    // MARK: - Rate-limit auto-clear

    private func scheduleRateLimitClear() {
        rateLimitClearTask?.cancel()
        rateLimitClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, case .rateLimited = self.status else { return }
                if let d = self.lastOkDate { self.status = .ok(d) } else { self.status = .idle }
            }
        }
    }
}
