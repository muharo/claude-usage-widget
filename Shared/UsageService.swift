import Foundation
import os

/// Calls the (undocumented) `api.anthropic.com/api/oauth/usage` endpoint
/// that Claude Code itself uses to render its `/usage` panel.
///
/// Verified wire format (2026-04-11):
///   {
///     "five_hour":   { "utilization": 100.0, "resets_at": "2026-04-11T23:00:00.376878+00:00" },
///     "seven_day":   { "utilization": 62.0,  "resets_at": "2026-04-13T23:00:00.376900+00:00" },
///     "seven_day_opus": null,   // and several other null fields we ignore
///     "extra_usage": { "is_enabled": true, "monthly_limit": 10000, "used_credits": 5949.0,
///                      "utilization": 59.49 }
///   }
///
/// Note: utilization values are 0–100 (percentages), NOT 0–1 fractions.
///       used_credits / monthly_limit are in cents as Doubles.
public struct UsageService {

    public enum ServiceError: Error, LocalizedError {
        case http(Int, String)
        case decoding(Error, String)    // error + raw JSON excerpt for debugging
        case transport(Error)
        case unauthorized

        public var errorDescription: String? {
            switch self {
            case .http(let code, let body):
                return "HTTP \(code): \(body.prefix(200))"
            case .decoding(let err, let raw):
                return "Decode error: \(err.localizedDescription) | raw: \(raw.prefix(300))"
            case .transport(let err):
                return "Network error: \(err.localizedDescription)"
            case .unauthorized:
                return "Unauthorized (401). Token expired — run `claude /login`."
            }
        }
    }

    public static let usageURL   = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    public static let betaHeader = "oauth-2025-04-20"

    private let session: URLSession
    private let log = Logger(subsystem: "com.robert.claude-usage-widget", category: "UsageService")

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public fetch

    public func fetch(token: String) async throws -> UsageSnapshot {
        async let usagePayload = fetchUsageRaw(token: token)
        async let plan = fetchPlanName(token: token)

        let payload  = try await usagePayload
        let planName = try? await plan

        let rawString = String(data: payload, encoding: .utf8) ?? "<binary>"
        log.info("raw usage: \(rawString, privacy: .public)")

        do {
            let wire = try decodeWire(payload)
            return buildSnapshot(wire: wire, planName: planName)
        } catch {
            log.error("decode failed: \(error.localizedDescription, privacy: .public) | raw: \(rawString, privacy: .public)")
            throw ServiceError.decoding(error, rawString)
        }
    }

    // MARK: - Wire decoding

    /// Local wire types — more permissive than the public model (all optional,
    /// Doubles for numeric fields, flexible dates).
    private struct WireWindow: Decodable {
        let utilization: Double?    // 0–100 range from API
        let resetsAt: Date?
        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    private struct WireExtra: Decodable {
        let isEnabled: Bool?
        let usedCredits: Double?    // cents as Double
        let monthlyLimit: Double?   // cents as Double
        let utilization: Double?    // 0–100 range from API
        enum CodingKeys: String, CodingKey {
            case isEnabled    = "is_enabled"
            case usedCredits  = "used_credits"
            case monthlyLimit = "monthly_limit"
            case utilization
        }
    }

    private struct Wire: Decodable {
        let fiveHour: WireWindow?
        let sevenDay: WireWindow?
        let sevenDayOpus: WireWindow?
        let extraUsage: WireExtra?
        enum CodingKeys: String, CodingKey {
            case fiveHour    = "five_hour"
            case sevenDay    = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case extraUsage  = "extra_usage"
        }
    }

    private func decodeWire(_ data: Data) throws -> Wire {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        return try decoder.decode(Wire.self, from: data)
    }

    private func buildSnapshot(wire: Wire, planName: String?) -> UsageSnapshot {
        func mapWindow(_ w: WireWindow?) -> UsageSnapshot.Window? {
            guard let w else { return nil }
            // Divide by 100 — API returns 0–100, our views use 0–1.
            let util = (w.utilization ?? 0) / 100.0
            return UsageSnapshot.Window(utilization: util, resetsAt: w.resetsAt)
        }

        let extra: UsageSnapshot.ExtraUsage? = wire.extraUsage.flatMap { e in
            guard let enabled = e.isEnabled else { return nil }
            let util     = (e.utilization ?? 0) / 100.0
            let usedUSD  = (e.usedCredits  ?? 0) / 100.0  // cents → dollars
            let limitUSD = (e.monthlyLimit ?? 0) / 100.0  // cents → dollars
            return UsageSnapshot.ExtraUsage(
                isEnabled:   enabled,
                utilization: util,
                usedUSD:     usedUSD,
                limitUSD:    limitUSD
            )
        }

        return UsageSnapshot(
            fiveHour:    mapWindow(wire.fiveHour),
            sevenDay:    mapWindow(wire.sevenDay),
            sevenDayOpus: mapWindow(wire.sevenDayOpus),
            extraUsage:  extra,
            planName:    planName,
            fetchedAt:   Date()
        )
    }

    // MARK: - Raw HTTP

    private func fetchUsageRaw(token: String) async throws -> Data {
        var req = URLRequest(url: Self.usageURL)
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.betaHeader,   forHTTPHeaderField: "anthropic-beta")
        req.setValue("ClaudeUsageWidget/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ServiceError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.http(-1, "no HTTP response")
        }
        if http.statusCode == 401 { throw ServiceError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw ServiceError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func fetchPlanName(token: String) async throws -> String? {
        var req = URLRequest(url: Self.profileURL)
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.betaHeader,   forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }

        let raw = String(data: data, encoding: .utf8) ?? ""
        log.info("raw profile: \(raw, privacy: .public)")

        struct Profile: Decodable {
            let plan: String?
            let subscriptionType: String?
            let tier: String?
            enum CodingKeys: String, CodingKey {
                case plan
                case subscriptionType = "subscription_type"
                case tier
            }
        }
        let p = try? JSONDecoder().decode(Profile.self, from: data)
        return p?.plan ?? p?.subscriptionType ?? p?.tier
    }
}
