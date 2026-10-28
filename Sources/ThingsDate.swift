import Foundation

/// Things 3 date encoding.
///
/// Things does NOT store dates as an epoch: it uses an integer with packed bits
/// `YYYYYYYYYYYMMMMDDDDD0000000` (year, month, day and 7 unused low bits).
/// That's why an "extra day" shows up at every month boundary, and any attempt
/// to treat the value as seconds or days since 1970 drifts.
///
/// Masks verified against the `things-py` library (the one used by the installed
/// Things MCP) and against 8 dates read from Things' own UI.
enum ThingsDate {
    static let yearMask = 0b111111111110000000000000000
    static let monthMask = 0b000000000001111000000000000
    static let dayMask = 0b000000000000000111110000000

    /// Decodes a Things value to a local date. `nil` if missing or invalid.
    static func components(from value: Int) -> DateComponents? {
        guard value != 0 else { return nil }
        let year = (value & yearMask) >> 16
        let month = (value & monthMask) >> 12
        let day = (value & dayMask) >> 7
        guard year > 1900, year < 4000, month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 12              // noon: immune to DST changes when subtracting days
        c.calendar = Calendar(identifier: .gregorian)
        return c
    }

    static func date(from value: Int) -> Date? {
        guard let c = components(from: value) else { return nil }
        return c.calendar?.date(from: c)
    }

    /// Difference in calendar days between the Things value and a reference date.
    static func dayOffset(_ value: Int, from reference: Date, calendar: Calendar = .current) -> Int? {
        guard let d = date(from: value) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: reference),
                                       to: calendar.startOfDay(for: d)).day
    }
}

/// Short label for Things' start bucket.
enum StartBucket: Int {
    case inbox = 0
    case anytime = 1
    case someday = 2
    case unknown = -1

    init(raw: Int) { self = StartBucket(rawValue: raw) ?? .unknown }

    var label: String {
        switch self {
        case .inbox: return L.s("start.inbox")
        case .anytime: return L.s("start.anytime")
        case .someday: return L.s("start.someday")
        case .unknown: return L.s("start.unknown")
        }
    }
}
