import Foundation

// MARK: - Claude Usage Parser

/// Parses the `/api/oauth/usage` response into a `ClaudeUsage` value.
/// All methods are pure functions with no side effects.
///
/// Current response shape (2026-09):
///
///     {"five_hour": {"utilization": 7.0, "resets_at": "..."},
///      "seven_day": {"utilization": 12.0, "resets_at": "..."},
///      "seven_day_sonnet": null, "seven_day_opus": null,
///      "limits": [
///        {"kind": "session",       "percent": 7,  "resets_at": "...", "scope": null},
///        {"kind": "weekly_all",    "percent": 12, "resets_at": "...", "scope": null},
///        {"kind": "weekly_scoped", "percent": 12, "resets_at": "...",
///         "scope": {"model": {"id": null, "display_name": "Fable"}}}
///      ], ...}
///
/// Per-model weekly limits now live only in `limits[]` (`weekly_scoped`), so
/// that array is the primary source; the legacy top-level keys are fallbacks.
struct ClaudeUsageParser {

    // MARK: - Date Formatters

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Public API

    enum ParseError: Error, Equatable {
        case invalidJSON
        case unrecognizedFormat(keys: [String])
    }

    /// Parse raw JSON data into a `ClaudeUsage` value.
    static func parseResponse(_ data: Data) -> Result<ClaudeUsage, ParseError> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.invalidJSON)
        }

        // 1. Structured `limits[]` array (authoritative when present).
        let limits = parseLimits(json)

        // 2. Legacy / flat keys as fallbacks.
        let fiveHourKeys = ["five_hour", "fiveHour", "5_hour", "short_term", "shortTerm"]
        let fiveHour = limits.session ?? firstBucket(json, keys: fiveHourKeys)

        let weeklyAllKeys = [
            "seven_day", "seven_day_all", "daily", "sevenDayAll",
            "7_day_all", "long_term", "longTerm", "weekly",
        ]
        let weeklyAll = limits.weeklyAll ?? firstBucket(json, keys: weeklyAllKeys)

        var weeklyModel = limits.weeklyModel
        var weeklyModelName = limits.weeklyModelName
        if weeklyModel == nil {
            // Older responses exposed per-model weekly limits as top-level keys.
            let legacy: [(String, String)] = [
                ("seven_day_fable", "Fable"), ("seven_day_opus", "Opus"),
                ("seven_day_sonnet", "Sonnet"), ("daily_sonnet", "Sonnet"),
                ("sevenDaySonnet", "Sonnet"), ("7_day_sonnet", "Sonnet"), ("sonnet", "Sonnet"),
            ]
            for (key, name) in legacy {
                if let b = parseBucket(json, key: key) {
                    weeklyModel = b
                    weeklyModelName = name
                    break
                }
            }
        }

        // If none of the known keys matched, try dynamic parse
        if fiveHour == nil && weeklyAll == nil && weeklyModel == nil {
            var buckets: [(String, UsageBucket)] = []
            for (key, value) in json {
                if let dict = value as? [String: Any],
                   let bucket = parseBucketFromDict(dict) {
                    buckets.append((key, bucket))
                }
            }

            if !buckets.isEmpty {
                let sorted = buckets.sorted { $0.0 < $1.0 }
                let usage = ClaudeUsage(
                    fiveHour: sorted.count > 0 ? sorted[0].1 : UsageBucket(percent: 0, resetAt: nil),
                    weeklyAll: sorted.count > 1 ? sorted[1].1 : UsageBucket(percent: 0, resetAt: nil),
                    weeklyModel: sorted.count > 2 ? sorted[2].1 : UsageBucket(percent: 0, resetAt: nil),
                    weeklyModelName: nil
                )
                return .success(usage)
            }

            return .failure(.unrecognizedFormat(keys: json.keys.sorted()))
        }

        let usage = ClaudeUsage(
            fiveHour: fiveHour ?? UsageBucket(percent: 0, resetAt: nil),
            weeklyAll: weeklyAll ?? UsageBucket(percent: 0, resetAt: nil),
            weeklyModel: weeklyModel ?? UsageBucket(percent: 0, resetAt: nil),
            weeklyModelName: weeklyModelName
        )

        return .success(usage)
    }

    // MARK: - limits[] Parsing

    struct Limits: Equatable {
        var session: UsageBucket?
        var weeklyAll: UsageBucket?
        var weeklyModel: UsageBucket?
        var weeklyModelName: String?
    }

    /// Extract session / weekly_all / weekly_scoped(model) entries from `limits[]`.
    /// Among several model-scoped entries, `ClaudeUsage.preferredModelName`
    /// wins; otherwise the first one is used.
    static func parseLimits(_ json: [String: Any]) -> Limits {
        var out = Limits()
        guard let entries = json["limits"] as? [[String: Any]] else { return out }

        var scoped: [(name: String?, bucket: UsageBucket)] = []
        for entry in entries {
            guard let kind = entry["kind"] as? String,
                  let bucket = parseLimitEntry(entry) else { continue }
            switch kind {
            case "session":
                if out.session == nil { out.session = bucket }
            case "weekly_all":
                if out.weeklyAll == nil { out.weeklyAll = bucket }
            case "weekly_scoped":
                let scope = entry["scope"] as? [String: Any]
                let model = scope?["model"] as? [String: Any]
                // Only model scopes; surface-scoped limits are not what we show.
                guard model != nil || scope == nil else { continue }
                let name = model?["display_name"] as? String
                scoped.append((name, bucket))
            default:
                continue
            }
        }

        let preferred = ClaudeUsage.preferredModelName.lowercased()
        if let match = scoped.first(where: { $0.name?.lowercased() == preferred }) ?? scoped.first {
            out.weeklyModel = match.bucket
            out.weeklyModelName = match.name
        }
        return out
    }

    /// `{"percent": 12, "resets_at": "..."}` -> bucket. `percent` is already 0-100.
    static func parseLimitEntry(_ entry: [String: Any]) -> UsageBucket? {
        let percent: Double
        if let p = entry["percent"] as? Double {
            percent = p
        } else if let p = entry["percent"] as? Int {
            percent = Double(p)
        } else {
            return nil
        }
        let resetAt = parseDate(from: entry, key: "resets_at") ?? parseDate(from: entry, key: "reset_at")
        return UsageBucket(percent: clamp0100(percent), resetAt: resetAt)
    }

    // MARK: - Bucket Parsing

    /// Try to parse a usage bucket from the JSON under a given key.
    /// Supports both nested object and flat key patterns.
    /// Return the first bucket found under any of `keys`, in order.
    private static func firstBucket(_ json: [String: Any], keys: [String]) -> UsageBucket? {
        for key in keys {
            if let bucket = parseBucket(json, key: key) { return bucket }
        }
        return nil
    }

    static func parseBucket(_ json: [String: Any], key: String) -> UsageBucket? {
        // Try as nested object
        if let bucket = json[key] as? [String: Any] {
            return parseBucketFromDict(bucket)
        }

        // Try as flat keys (e.g. "five_hour_utilization", "five_hour_reset_at")
        if let utilization = json["\(key)_utilization"] as? Double {
            let resetAt = parseDate(from: json, key: "\(key)_reset_at")
            return UsageBucket(percent: clamp0100(utilization), resetAt: resetAt)
        }

        return nil
    }

    /// Parse a usage bucket from a dictionary of values.
    static func parseBucketFromDict(_ dict: [String: Any]) -> UsageBucket? {
        let utilization = (dict["utilization"] as? Double)
            ?? (dict["usage"] as? Double)
            ?? (dict["percent"] as? Double).map { $0 / 100.0 }
            ?? (dict["value"] as? Double)

        guard let util = utilization else { return nil }

        let resetAt = parseDate(from: dict, key: "reset_at")
            ?? parseDate(from: dict, key: "resetAt")
            ?? parseDate(from: dict, key: "resets_at")
            ?? parseDate(from: dict, key: "reset")
            ?? parseDate(from: dict, key: "expires_at")

        return UsageBucket(percent: clamp0100(util), resetAt: resetAt)
    }

    // MARK: - Date Parsing

    /// Parse a date from a dictionary value, supporting ISO 8601 strings and Unix timestamps.
    static func parseDate(from dict: [String: Any], key: String) -> Date? {
        if let str = dict[key] as? String {
            return isoFormatter.date(from: str)
                ?? isoFormatterNoFrac.date(from: str)
        }
        if let ts = dict[key] as? TimeInterval {
            if ts > 1_000_000_000 {
                return Date(timeIntervalSince1970: ts)
            }
        }
        return nil
    }

    // MARK: - Utilities

    /// Clamp a value to the range [0, 100].
    static func clamp0100(_ v: Double) -> Double {
        min(max(v, 0), 100)
    }
}
