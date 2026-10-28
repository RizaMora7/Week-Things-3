import Foundation

/// An open to-do or project, already decoded.
struct TaskItem: Identifiable, Equatable {
    let id: String                 // Things uuid
    let title: String
    let notes: String
    let isProject: Bool
    let start: StartBucket
    let startRaw: Int?             // Things value (startDate) or nil
    let deadlineRaw: Int?          // Things value (deadline) or nil
    let deadlineSuppressed: Bool
    let recurring: Bool
    let openChecklist: Int
    let totalChecklist: Int
    let project: String?
    let area: String?
    let heading: String?
    let tags: [String]
    let sortIndex: Int
    let created: Date?

    var deadline: Date? { deadlineRaw.flatMap { ThingsDate.date(from: $0) } }
    var scheduled: Date? { startRaw.flatMap { ThingsDate.date(from: $0) } }

    /// Day the task occupies on the schedule. With both dates present the **earlier** one
    /// wins: the day you planned to work on it, not the last possible day.
    ///
    /// The deadline used to eclipse the schedule (`deadline ?? scheduled`) and a task
    /// scheduled for today with a deadline tomorrow only showed up tomorrow, disagreeing with
    /// Things —which shows it under the Today star— and with the app's own Day view.
    /// The deadline isn't lost: the card draws its red stripe and a «due dd/mm».
    var placement: Date? {
        switch (scheduled, deadline) {
        case let (s?, d?): return min(s, d)
        case let (s?, nil): return s
        case let (nil, d?): return d
        default: return nil
        }
    }

    var hasDate: Bool { placement != nil }
}

/// A board snapshot: what the app shows from a single read.
struct Board {
    var tasks: [TaskItem] = []
    var generatedAt = Date()
    var databasePath = ""
    var readMode = "—"
    var counts = Counts()
    /// Things URL-scheme authorization token (`TMSettings`). Required by
    /// `things:///update`; nil if Things has none or the database lacks the table.
    var authToken: String?

    struct Counts {
        var open = 0
        var dated = 0
        var overdue = 0
        var undated = 0
        var recurring = 0
        var projects = 0
    }
}

enum WeekRangeHelper {
    /// Monday as the first day of the week (NZ convention and your weekly board's).
    static func mondayOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)   // 1 = Sunday
        let fromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -fromMonday, to: startOfDay) ?? startOfDay
    }

    static func addDays(_ days: Int, to date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func sameDay(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }
}

enum DateFormat {
    private static var localeID = "es_CL"

    private static func make(_ fmt: String, posix: Bool = false) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: posix ? "en_US_POSIX" : localeID)
        f.dateFormat = fmt
        return f
    }

    /// Called at launch and whenever the language changes.
    static func rebuild() {
        localeID = L.code == "en" ? "en_US" : "es_CL"
        let en = L.code == "en"
        shortWeekday = make("EEE")
        longWeekday = make("EEEE")
        dayNumber = make("d")
        monthShort = make(en ? "MMM yyyy" : "MMMM yyyy")
        time = make("HH:mm:ss")
        iso = make("yyyy-MM-dd", posix: true)
        hm = make("HH:mm")
        dueShort = make("dd/MM", posix: true)
        dayTitle = make(en ? "EEEE, MMMM d, yyyy" : "EEEE d 'de' MMMM yyyy")
    }

    static var shortWeekday = make("EEE")
    static var longWeekday = make("EEEE")
    static var dayNumber = make("d")
    static var monthShort = make("MMMM yyyy")
    static var time = make("HH:mm:ss")
    static var iso = make("yyyy-MM-dd", posix: true)
    static var hm = make("HH:mm")
    /// "28/10": the deadline on the card when it falls on another day.
    static var dueShort = make("dd/MM", posix: true)
    static var dayTitle = make("EEEE d 'de' MMMM yyyy")

    /// "lun 26" / "Mon 26"
    static func header(_ date: Date) -> String {
        let w = weekdayAbbr(date)
        return "\(w) \(dayNumber.string(from: date))"
    }
    /// "Lunes 26 de octubre 2026" / "Monday, October 26, 2026". In Spanish only the
    /// first letter is capitalised (`.capitalized` would give "De Octubre").
    static func dayHeading(_ date: Date) -> String {
        let raw = dayTitle.string(from: date)
        return L.code == "en" ? raw : raw.firstUppercased
    }
    /// "octubre 2026" / "Oct 2026"
    static func monthYear(_ date: Date) -> String { monthShort.string(from: date) }
    /// "lun" / "Mon"
    static func weekdayAbbr(_ date: Date) -> String {
        let w = shortWeekday.string(from: date).replacingOccurrences(of: ".", with: "")
        return L.code == "en" ? w.firstUppercased : w
    }
}

extension String {
    var firstUppercased: String {
        guard let first = self.first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
