import AppKit

/// An event, already on the concrete date it occurs (recurrences expanded).
struct CalEvent: Equatable {
    let id: Int              // event_id (CalendarItem ROWID)
    let dayKey: Int          // day of the occurrence, for grouping
    let title: String
    let start: Date?         // nil for all-day
    let end: Date?
    let allDay: Bool
    let calendarRowID: Int
    let calendarTitle: String
    let color: NSColor

    var sortDate: Date { start ?? Calendar.current.startOfDay(for: end ?? Date()) }

    /// "10:30–11:30" or the active language's "all day" text.
    var timeText: String {
        guard !allDay, let s = start else { return L.s("cal.allDay") }
        let f = DateFormat.hm
        if let e = end, e > s { return "\(f.string(from: s))–\(f.string(from: e))" }
        return f.string(from: s)
    }

    var durationMinutes: Int {
        guard let s = start, let e = end, e > s else { return 0 }
        return Int(e.timeIntervalSince(s) / 60)
    }
}

/// An available calendar, for the picker.
struct CalSource: Identifiable, Equatable {
    let rowID: Int
    let title: String
    /// Raw account name from the `Store` table ("iCloud", "Google", "Other",
    /// "Subscribed Calendars", "Default" or the account's email). To display it,
    /// pass it through `providerLabel`.
    let provider: String
    var enabled: Bool
    var color: NSColor = .systemGray
    var id: Int { rowID }
}

/// Reads Apple Calendar (read-only) from ~/Library/Calendars/Calendar.sqlitedb.
///
/// Facts verified on this machine:
/// - `OccurrenceCache.day` = CFAbsoluteTime of the day's LOCAL midnight.
/// - `OccurrenceCache.occurrence_date` = CFAbsoluteTime of the occurrence's real start
///   (the `occurrence_start_date`/`occurrence_end_date` columns are NULL).
/// - Duration comes from `CalendarItem.end_date - start_date` (stable across instances).
/// - `Calendar.sqlitedb` is the live file; `Calendar Cache` lacks the Z tables
///   the old cron prompt assumed.
enum CalendarStore {
    enum CalError: LocalizedError {
        case notFound, unreadable(String)
        var errorDescription: String? {
            switch self {
            case .notFound: return L.s("err.calNotFound")
            case .unreadable(let m): return L.f("err.calUnreadable", m)
            }
        }
    }

    private static let cfOffset: Double = 978_307_200

    private static func dbPath() -> String? {
        // Same escape hatch as `SEMANA_THINGS_DB` in ThingsStore: the repo's demo mode
        // points at a made-up database, so it doesn't depend on the user's real calendar.
        if let override = ProcessInfo.processInfo.environment["SEMANA_CALENDAR_DB"],
           !override.isEmpty, FileManager.default.fileExists(atPath: override) {
            return override
        }
        let p = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Calendars/Calendar.sqlitedb").path
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }

    /// Calendars visible to the user, with system/noise ones flagged as
    /// candidates to be off by default.
    static func availableCalendars() -> [CalSource] {
        guard let path = dbPath(), let db = try? SQLiteDB(path: path, readOnly: true),
              let rows = try? db.rows("""
              SELECT cal.ROWID AS rid, cal.title AS title, cal.color AS color, cal.flags AS flags,
                     s.name AS store
              FROM Calendar cal
              LEFT JOIN Store s ON s.ROWID = cal.store_id
              WHERE cal.title IS NOT NULL AND cal.title != ''
              ORDER BY s.name, cal.title
              """) else { return [] }
        var out: [CalSource] = []
        var seenTitles = Set<String>()
        for r in rows {
            guard let title = r.str("title"), let rid = r.intg("rid") else { continue }
            // Calendar's internal placeholders ("DEFAULT_CALENDAR_NAME", ...): they never
            // hold user events, so they aren't even offered in the picker.
            if title.hasPrefix("DEFAULT_") { continue }
            // Same for the "Default" calendar in Apple's Default store.
            if title == "Default" && (r.str("store") ?? "") == "Default" { continue }
            // The same title can appear in three rows (iCloud/Google/Other) when the
            // account was registered with the email: they differ by rowid, but the
            // user picks by title.
            let noise = isNoise(title)
            if seenTitles.contains(title) && noise { continue }
            seenTitles.insert(title)
            out.append(CalSource(rowID: rid, title: title, provider: r.str("store") ?? "",
                                 enabled: !noise,
                                 color: parseHex(r.str("color")) ?? .systemGray))
        }
        return out
    }

    /// Account name fit for display. Translated when the menu is drawn, not when the
    /// database is read, so a language change applies without reloading. Apple's
    /// "Default" store has no provider: left empty.
    static func providerLabel(_ store: String) -> String {
        switch store {
        case "", "Default": return ""
        case "Other": return L.s("cal.provider.local")
        case "Subscribed Calendars": return L.s("cal.provider.subscribed")
        case "Google", "iCloud", "Exchange", "CalDAV": return store
        default:
            // Google is usually registered with the account's email. Better to say
            // "Google" than to show a whole email address in the menu.
            if store.contains("@") {
                let domain = store.components(separatedBy: "@").last ?? ""
                if domain.hasSuffix("gmail.com") || domain.hasSuffix("googlemail.com") { return "Google" }
                if domain.contains("icloud.com") || domain.contains("me.com") { return "iCloud" }
                if domain.contains("outlook") || domain.contains("hotmail") || domain.contains("live.") { return "Outlook" }
                return "Google"
            }
            return store
        }
    }

    /// Known noise: system calendars, suggestions, birthdays and astronomy.
    static func isNoise(_ title: String) -> Bool {
        let t = title.lowercased()
        if t.contains("default") || t.contains("task") { return true }
        for bad in ["found in mail", "found in natural language", "facebook birthdays",
                    "phases of the moon", "siri", "birthdays"] where t.contains(bad) {
            return true
        }
        return false
    }

    /// Events between `from` (inclusive) and `to` (exclusive) for the chosen calendars.
    static func events(from: Date, to: Date, rowIDs: Set<Int>) -> [CalEvent] {
        guard let path = dbPath() else { return [] }
        guard let db = try? SQLiteDB(path: path, readOnly: true) else { return [] }
        let startCF = from.timeIntervalSince1970 - cfOffset
        let endCF = to.timeIntervalSince1970 - cfOffset
        let ids = rowIDs.sorted().map(String.init).joined(separator: ",")
        guard !ids.isEmpty else { return [] }

        let sql = """
        SELECT oc.event_id AS eid, oc.day AS day, oc.occurrence_date AS occ,
               ci.summary AS summary, ci.all_day AS allDay,
               ci.start_date AS s, ci.end_date AS e,
               cal.ROWID AS cid, cal.title AS calTitle, cal.color AS calColor
        FROM OccurrenceCache oc
        JOIN CalendarItem ci ON ci.ROWID = oc.event_id
        JOIN Calendar cal    ON cal.ROWID = oc.calendar_id
        WHERE oc.day >= \(startCF) AND oc.day < \(endCF)
          AND oc.calendar_id IN (\(ids))
          AND IFNULL(ci.hidden,0) = 0
          AND IFNULL(ci.status,0) != 2
        ORDER BY oc.day, oc.occurrence_date
        """
        guard let rows = try? db.rows(sql) else { return [] }

        var seen = Set<String>()
        var out: [CalEvent] = []
        let cal = Calendar.current

        for r in rows {
            guard let dayCF = r["day"] as? Double, let eid = r.intg("eid") else { continue }
            let dayDate = Date(timeIntervalSince1970: dayCF + cfOffset)
            let dayKey = cal.startOfDay(for: dayDate)
            let title = (r.str("summary") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let allDay = (r.intg("allDay") ?? 0) == 1
            let occCF = r["occ"] as? Double

            var start: Date?
            var end: Date?
            if allDay {
                start = nil
                end = nil
            } else if let occ = occCF, occ > 0 {
                let s = Date(timeIntervalSince1970: occ + cfOffset)
                let durGuess: TimeInterval = {
                    if let scf = r["s"] as? Double, let ecf = r["e"] as? Double, ecf > scf {
                        return (ecf - scf)
                    }
                    return 3600
                }()
                start = s
                end = s.addingTimeInterval(durGuess)
            } else {
                continue
            }

            let key = "\(eid)@\(dayKey.timeIntervalSince1970)"
            if seen.contains(key) { continue }
            seen.insert(key)

            out.append(CalEvent(
                id: eid,
                dayKey: Int(dayKey.timeIntervalSince1970),
                title: title.isEmpty ? L.s("task.untitled") : title,
                start: start, end: end, allDay: allDay,
                calendarRowID: r.intg("cid") ?? 0,
                calendarTitle: r.str("calTitle") ?? "",
                color: parseHex(r.str("calColor")) ?? .systemBlue
            ))
        }
        return out
    }

    /// Calendar colours come as ARGB hex ("#CC73E1" or "#9886C3FF").
    static func parseHex(_ raw: String?) -> NSColor? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard !s.isEmpty, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        switch s.count {
        case 6:
            r = CGFloat((v >> 16) & 0xFF) / 255; g = CGFloat((v >> 8) & 0xFF) / 255
            b = CGFloat(v & 0xFF) / 255; a = 1
        case 8:
            // Calendars use AARRGGBB
            a = CGFloat((v >> 24) & 0xFF) / 255; r = CGFloat((v >> 16) & 0xFF) / 255
            g = CGFloat((v >> 8) & 0xFF) / 255; b = CGFloat(v & 0xFF) / 255
        default:
            return nil
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: max(0.35, a))
    }
}
