import Foundation
import CoreFoundation
import Darwin

enum ConfigLocation {
    static var home: URL {
        if let passwd = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: passwd.pointee.pw_dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    static var url: URL { home.appendingPathComponent(".claude/claude-usage-widget.json") }
    static var codexAuthURL: URL { home.appendingPathComponent(".codex/auth.json") }
}

struct WidgetConfig: Codable, Sendable {
    var sessionKey: String?
    var organizationId: String?
    var oauthToken: String?
    var claudeEnabled: Bool?
    var codexEnabled: Bool?
    var codexAccessToken: String?
    var codexAccountId: String?

    static func load(from url: URL = ConfigLocation.url) throws -> WidgetConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return WidgetConfig() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func save(to url: URL = ConfigLocation.url) throws {
        // Keep fields added by other versions/tools when editing known settings.
        var json: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            guard let existing = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
                throw UsageError.invalidConfig
            }
            json = existing
        }
        let fields = ["sessionKey", "organizationId", "oauthToken", "claudeEnabled",
                      "codexEnabled", "codexAccessToken", "codexAccountId"]
        fields.forEach { json.removeValue(forKey: $0) }
        guard let values = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] else {
            throw UsageError.invalidConfig
        }
        json.merge(values) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".usage-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}

struct UsageMetric: Identifiable, Sendable {
    let id: String
    let title: String
    let percent: Double?
    let resetsAt: Date?

    var fraction: Double { min(1, max(0, (percent ?? 0) / 100)) }
    var percentageText: String {
        guard let percent, percent.isFinite else { return "—" }
        return percent.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    /// A copy with the countdown cleared once its target has passed `boundary`. Percent is
    /// left as-is: we know it's stale at that point, but we don't fabricate a 0% reset
    /// without confirming it from the server.
    func clearingResetIfPast(_ boundary: Date) -> UsageMetric {
        guard let resetsAt, resetsAt <= boundary else { return self }
        return UsageMetric(id: id, title: title, percent: percent, resetsAt: nil)
    }
}

struct ProviderUsage: Sendable {
    let name: String
    var metrics: [UsageMetric] = []
    var error: String?
    var isEnabled = true

    func clearingResetsPast(_ boundary: Date) -> ProviderUsage {
        var copy = self
        copy.metrics = metrics.map { $0.clearingResetIfPast(boundary) }
        return copy
    }
}

struct UsageSnapshot: Sendable {
    let date: Date
    let claude: ProviderUsage
    let codex: ProviderUsage

    /// Distinct future reset timestamps across both providers, ascending. Used to schedule
    /// timeline entries exactly at each boundary instead of on a fixed reload cadence. A
    /// disabled provider always has an empty metrics array, so it naturally contributes none.
    var upcomingResets: [Date] {
        Array(Set([claude, codex].flatMap(\.metrics).compactMap(\.resetsAt).filter { $0 > date })).sorted()
    }

    /// A copy dated at `boundary` where any metric whose reset has already passed by then
    /// has its countdown cleared. `Text(_:style:.relative)` keeps counting past its target
    /// with no way to know the window actually rolled over, so once we schedule this entry
    /// the row falls back to a neutral "Refreshing…" state instead of counting upward.
    func clearingResetsPast(_ boundary: Date) -> UsageSnapshot {
        UsageSnapshot(date: boundary, claude: claude.clearingResetsPast(boundary),
                      codex: codex.clearingResetsPast(boundary))
    }

    static var preview: UsageSnapshot {
        let now = Date()
        return UsageSnapshot(date: now, claude: ProviderUsage(name: "Claude", metrics: [
            UsageMetric(id: "five_hour", title: "5h Session", percent: 42.5, resetsAt: now.addingTimeInterval(10800)),
            UsageMetric(id: "seven_day", title: "Weekly", percent: 28, resetsAt: now.addingTimeInterval(259200)),
            UsageMetric(id: "fable", title: "Fable · Weekly", percent: 61, resetsAt: now.addingTimeInterval(259200))
        ]), codex: ProviderUsage(name: "Codex", metrics: [
            UsageMetric(id: "primary", title: "5h Session", percent: 35, resetsAt: now.addingTimeInterval(7200)),
            UsageMetric(id: "secondary", title: "Weekly", percent: 18, resetsAt: now.addingTimeInterval(172800))
        ]))
    }
}

enum UsageParser {
    static func number(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        // JSON booleans also bridge to NSNumber; they are not percentages.
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite {
            return n.doubleValue
        }
        return nil
    }

    static func date(_ value: Any?) -> Date? {
        if let seconds = number(value) { return Date(timeIntervalSince1970: seconds) }
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.invalidResponse
        }
        return object
    }

    static func claude(_ data: Data) throws -> ProviderUsage {
        let json = try object(data)
        let limits = json["limits"] as? [[String: Any]] ?? []
        func metric(_ id: String, _ title: String, _ raw: [String: Any]?) -> UsageMetric {
            UsageMetric(id: id, title: title,
                        percent: number(raw?["utilization"]) ?? number(raw?["percent"]),
                        resetsAt: date(raw?["resets_at"]))
        }
        let scopedFable = limits.first {
            guard $0["kind"] as? String == "weekly_scoped",
                  let scope = $0["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let name = model["display_name"] as? String else { return false }
            return name.localizedCaseInsensitiveContains("fable")
        }
        let fable = scopedFable ?? (json["seven_day_overage_included"] as? [String: Any])
            ?? (json["seven_day_fable"] as? [String: Any])
        let metrics = [
            metric("five_hour", "5h Session", json["five_hour"] as? [String: Any]),
            metric("seven_day", "Weekly", json["seven_day"] as? [String: Any]),
            metric("fable", "Fable · Weekly", fable)
        ]
        guard metrics.contains(where: { $0.percent != nil }) else { throw UsageError.noLimits }
        return ProviderUsage(name: "Claude", metrics: metrics)
    }

    static func codex(_ data: Data) throws -> ProviderUsage {
        let json = try object(data)
        let rate = json["rate_limit"] as? [String: Any] ?? [:]
        let metrics = [("primary_window", "primary"), ("secondary_window", "secondary")].compactMap { key, id -> UsageMetric? in
            guard let window = rate[key] as? [String: Any] else { return nil }
            let seconds = number(window["limit_window_seconds"])
            let title: String
            switch seconds {
            case 18000: title = "5h Session"
            case 604800: title = "Weekly"
            case .some(let duration) where duration > 0:
                title = duration >= 86400 ? "\(Int(duration / 86400))d Window" :
                    duration >= 3600 ? "\(Int(duration / 3600))h Window" : "\(Int(duration / 60))m Window"
            default: title = id == "primary" ? "Primary" : "Secondary"
            }
            return UsageMetric(id: id, title: title, percent: number(window["used_percent"]),
                               resetsAt: date(window["reset_at"]))
        }
        guard metrics.contains(where: { $0.percent != nil }) else { throw UsageError.noLimits }
        return ProviderUsage(name: "Codex", metrics: metrics)
    }
}

enum UsageError: LocalizedError {
    case invalidResponse, noLimits, http(Int), missingClaude, missingCodex, invalidConfig

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Unexpected usage response. Try again later."
        case .noLimits: return "No subscription limits returned for this account."
        case .http(401): return "Login expired. Update credentials in the app."
        case .http(403): return "Access denied. Check login and account permissions."
        case .http(429): return "Rate limited. Wait for the next refresh."
        case .http(let code): return "Usage service returned HTTP \(code)."
        case .missingClaude: return "Add Claude credentials in the app."
        case .missingCodex: return "Sign in with Codex CLI, or add a token in the app."
        case .invalidConfig: return "Cannot read configuration. Open the app to fix it."
        }
    }
}
