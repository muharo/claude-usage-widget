import Foundation

/// Decoded response from `GET https://api.anthropic.com/api/oauth/usage`,
/// plus a few computed conveniences for the views.
///
/// Wire format notes (verified against live API 2026-04-11):
///   • `utilization` is 0–100, not 0–1.
///   • `used_credits` / `monthly_limit` are Doubles (cents, USD).
///   • `resets_at` is ISO-8601 with fractional seconds + `+00:00` timezone.
///   • `currency` is absent from extra_usage — we default to "USD".
public struct UsageSnapshot: Codable, Equatable {

    public struct Window: Codable, Equatable {
        /// Normalised 0.0–1.0 (API returns 0–100, we divide on decode).
        public let utilization: Double
        public let resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    public struct ExtraUsage: Codable, Equatable {
        public let isEnabled: Bool
        /// Normalised 0.0–1.0 (API returns 0–100, we divide on decode).
        public let utilization: Double
        /// Dollars (API returns cents as Double, we divide by 100 on decode).
        public let usedUSD: Double
        /// Dollars.
        public let limitUSD: Double

        public var balanceUSD: Double { max(limitUSD - usedUSD, 0) }

        enum CodingKeys: String, CodingKey {
            case isEnabled    = "is_enabled"
            case utilization
            case usedUSD      = "used_credits"   // remapped & converted on decode
            case limitUSD     = "monthly_limit"  // remapped & converted on decode
        }
    }

    public let fiveHour: Window?
    public let sevenDay: Window?
    public let sevenDayOpus: Window?        // hidden in v1, parsed defensively
    public let extraUsage: ExtraUsage?
    public let planName: String?            // pulled from /api/oauth/profile
    public let fetchedAt: Date

    enum CodingKeys: String, CodingKey {
        case fiveHour    = "five_hour"
        case sevenDay    = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case extraUsage  = "extra_usage"
        case planName    = "_plan_name"     // injected client-side
        case fetchedAt   = "_fetched_at"   // injected client-side
    }

    public init(
        fiveHour: Window?,
        sevenDay: Window?,
        sevenDayOpus: Window?,
        extraUsage: ExtraUsage?,
        planName: String?,
        fetchedAt: Date
    ) {
        self.fiveHour    = fiveHour
        self.sevenDay    = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.extraUsage  = extraUsage
        self.planName    = planName
        self.fetchedAt   = fetchedAt
    }

    /// Sample data for SwiftUI previews and the widget placeholder.
    public static let placeholder = UsageSnapshot(
        fiveHour: .init(utilization: 0.42, resetsAt: Date().addingTimeInterval(2 * 3600)),
        sevenDay: .init(utilization: 0.61, resetsAt: Date().addingTimeInterval(4 * 24 * 3600)),
        sevenDayOpus: nil,
        extraUsage: .init(isEnabled: true, utilization: 0.59, usedUSD: 59.49, limitUSD: 100.00),
        planName: "Max",
        fetchedAt: Date()
    )
}

// MARK: - Encoder / decoder

public extension UsageSnapshot {
    static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .flexibleISO8601
        return d
    }()
}

// MARK: - Flexible ISO-8601 date strategy

public extension JSONDecoder.DateDecodingStrategy {
    /// Handles ISO-8601 with or without fractional seconds, and `+00:00`
    /// or `Z` timezone. Also falls back to numeric Unix timestamps.
    static var flexibleISO8601: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let str = try? container.decode(String.self) {
                // With fractional seconds (e.g. "2026-04-11T23:00:00.376878+00:00").
                let frac = ISO8601DateFormatter()
                frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = frac.date(from: str) { return d }

                // Without fractional seconds (e.g. "2026-04-11T17:00:00Z").
                let plain = ISO8601DateFormatter()
                plain.formatOptions = [.withInternetDateTime]
                if let d = plain.date(from: str) { return d }

                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognised date string: \(str)"
                )
            }

            // Numeric fallback: milliseconds if > 1e10, else seconds.
            if let raw = try? container.decode(Double.self) {
                let seconds = raw > 1e10 ? raw / 1000.0 : raw
                return Date(timeIntervalSince1970: seconds)
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO-8601 string or numeric timestamp"
            )
        }
    }
}
