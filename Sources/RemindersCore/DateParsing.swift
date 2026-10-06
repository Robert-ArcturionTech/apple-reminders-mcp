import Foundation

/// A parsed due date. `hasTime` is false when the caller supplied a bare date
/// (`2026-05-01`), in which case the reminder gets an all-day due date and no alarm.
public struct DueDate: Equatable {
    public let date: Date
    public let hasTime: Bool

    public init(date: Date, hasTime: Bool) {
        self.date = date
        self.hasTime = hasTime
    }
}

public enum DateParsing {
    /// Accepts, in order:
    /// 1. a full ISO 8601 timestamp with zone, e.g. `2026-05-01T09:00:00Z` or `2026-05-01T09:00:00-04:00`
    /// 2. the same with fractional seconds, e.g. `2026-05-01T09:00:00.000Z`
    /// 3. a zone-less local timestamp, `2026-05-01T09:00:00` (interpreted in `timeZone`)
    /// 4. a zone-less local timestamp without seconds, `2026-05-01T09:00`
    /// 5. a bare date, `2026-05-01` (all-day, `hasTime == false`)
    public static func parse(
        _ input: String,
        timeZone: TimeZone = .current
    ) -> DueDate? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return DueDate(date: d, hasTime: true) }

        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return DueDate(date: d, hasTime: true) }

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            if let d = formatter(format, timeZone).date(from: s) {
                return DueDate(date: d, hasTime: true)
            }
        }

        if let d = formatter("yyyy-MM-dd", timeZone).date(from: s) {
            return DueDate(date: d, hasTime: false)
        }
        return nil
    }

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.isLenient = false
        f.dateFormat = format
        return f
    }

    public static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
