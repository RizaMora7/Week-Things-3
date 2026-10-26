import Foundation

/// Una tarea o proyecto abierto, ya decodificado.
struct TaskItem: Identifiable, Equatable {
    let id: String                 // uuid de Things
    let title: String
    let notes: String
    let isProject: Bool
    let start: StartBucket
    let startRaw: Int?             // valor Things (startDate) o nil
    let deadlineRaw: Int?          // valor Things (deadline) o nil
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

    /// Día en el que la tarea ocupa la agenda: el plazo manda si existe.
    var placement: Date? { deadline ?? scheduled }

    var hasDate: Bool { placement != nil }
}

/// Corte del tablero: lo que la app muestra de una sola lectura.
struct Board {
    var tasks: [TaskItem] = []
    var generatedAt = Date()
    var databasePath = ""
    var readMode = "—"
    var counts = Counts()

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
    /// Lunes como primer día de la semana (convención NZ y de tu tablero semanal).
    static func mondayOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)   // 1 = domingo
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

    /// Se llama al arrancar y cada vez que cambia el idioma.
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
        dayTitle = make(en ? "EEEE, MMMM d, yyyy" : "EEEE d 'de' MMMM yyyy")
    }

    static var shortWeekday = make("EEE")
    static var longWeekday = make("EEEE")
    static var dayNumber = make("d")
    static var monthShort = make("MMMM yyyy")
    static var time = make("HH:mm:ss")
    static var iso = make("yyyy-MM-dd", posix: true)
    static var hm = make("HH:mm")
    static var dayTitle = make("EEEE d 'de' MMMM yyyy")

    /// "lun 26" / "Mon 26"
    static func header(_ date: Date) -> String {
        let w = weekdayAbbr(date)
        return "\(w) \(dayNumber.string(from: date))"
    }
    /// "Lunes 26 de octubre 2026" / "Monday, October 26, 2026". En español solo se
    /// capitaliza la primera letra (`.capitalized` daría "De Octubre").
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
