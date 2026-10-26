import AppKit

/// Un evento, ya en la fecha concreta en la que ocurre (recurrencias expandidas).
struct CalEvent: Equatable {
    let id: Int              // event_id (ROWID de CalendarItem)
    let dayKey: Int          // día de la ocurrencia, para agrupar
    let title: String
    let start: Date?         // nil en todo el día
    let end: Date?
    let allDay: Bool
    let calendarRowID: Int
    let calendarTitle: String
    let color: NSColor

    var sortDate: Date { start ?? Calendar.current.startOfDay(for: end ?? Date()) }

    /// "10:30–11:30" o el texto de "todo el día" del idioma activo.
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

/// Un calendario disponible, para el selector.
struct CalSource: Identifiable, Equatable {
    let rowID: Int
    let title: String
    /// Nombre crudo de la cuenta según la tabla `Store` ("iCloud", "Google", "Other",
    /// "Subscribed Calendars", "Default" o el correo de la cuenta). Para mostrarlo,
    /// pasar por `providerLabel`.
    let provider: String
    var enabled: Bool
    var id: Int { rowID }
}

/// Lee Apple Calendar (solo lectura) desde ~/Library/Calendars/Calendar.sqlitedb.
///
/// Datos verificados en esta máquina:
/// - `OccurrenceCache.day` = CFAbsoluteTime de la medianoche LOCAL del día.
/// - `OccurrenceCache.occurrence_date` = CFAbsoluteTime del inicio real de la ocurrencia
///   (las columnas `occurrence_start_date`/`occurrence_end_date` vienen NULL).
/// - La duración se toma de `CalendarItem.end_date - start_date` (estable entre instancias).
/// - `Calendar.sqlitedb` es el archivo vivo; `Calendar Cache` no tiene las tablas Z que
///   supone el prompt del cron antiguo.
enum CalendarStore {
    enum CalError: LocalizedError {
        case notFound, unreadable(String)
        var errorDescription: String? {
            switch self {
            case .notFound: return "No encontré la base de Calendarios."
            case .unreadable(let m): return "No pude leer Apple Calendar: \(m)"
            }
        }
    }

    private static let cfOffset: Double = 978_307_200

    private static func dbPath() -> String? {
        // Mismo escape que `SEMANA_THINGS_DB` en ThingsStore: el modo demo del repo
        // apunta a una base inventada, para no depender del calendario real del usuario.
        if let override = ProcessInfo.processInfo.environment["SEMANA_CALENDAR_DB"],
           !override.isEmpty, FileManager.default.fileExists(atPath: override) {
            return override
        }
        let p = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Calendars/Calendar.sqlitedb").path
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }

    /// Calendarios visibles para el usuario, con los de sistema/ruido marcados como
    /// candidatos a ir fuera por defecto.
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
            // Placeholders internos de Calendar ("DEFAULT_CALENDAR_NAME", ...): nunca
            // traen eventos del usuario, así que ni se ofrecen en el selector.
            if title.hasPrefix("DEFAULT_") { continue }
            // Un mismo título puede aparecer en tres filas (iCloud/Google/Otros) cuando
            // la cuenta se registró con el correo: se distinguen por rowid, pero el
            // usuario elige por título.
            let noise = isNoise(title)
            if seenTitles.contains(title) && noise { continue }
            seenTitles.insert(title)
            out.append(CalSource(rowID: rid, title: title, provider: r.str("store") ?? "",
                                 enabled: !noise))
        }
        return out
    }

    /// Nombre de cuenta apto para mostrar. Se traduce al pintar el menú, no al leer la
    /// base, para que un cambio de idioma surta efecto sin recargar. El almacén
    /// "Default" de Apple no tiene proveedor: se deja vacío.
    static func providerLabel(_ store: String) -> String {
        switch store {
        case "", "Default": return ""
        case "Other": return L.s("cal.provider.local")
        case "Subscribed Calendars": return L.s("cal.provider.subscribed")
        case "Google", "iCloud", "Exchange", "CalDAV": return store
        default:
            // Google suele quedar registrado con el correo de la cuenta. Mejor decir
            // "Google" que mostrar una dirección de correo entera en el menú.
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

    /// Ruido conocido: calendarios de sistema, sugerencias, cumpleaños y astronomicía.
    static func isNoise(_ title: String) -> Bool {
        let t = title.lowercased()
        if t.contains("default") || t.contains("task") { return true }
        for bad in ["found in mail", "found in natural language", "facebook birthdays",
                    "phases of the moon", "siri", "birthdays"] where t.contains(bad) {
            return true
        }
        return false
    }

    /// Eventos entre `from` (inclusive) y `to` (exclusive) de los calendarios elegidos.
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
                title: title.isEmpty ? "(sin título)" : title,
                start: start, end: end, allDay: allDay,
                calendarRowID: r.intg("cid") ?? 0,
                calendarTitle: r.str("calTitle") ?? "",
                color: parseHex(r.str("calColor")) ?? .systemBlue
            ))
        }
        return out
    }

    /// Colores de Calendar vienen como ARGB hexadecimal ("#CC73E1" o "#9886C3FF").
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
            // Calendarios usan AARRGGBB
            a = CGFloat((v >> 24) & 0xFF) / 255; r = CGFloat((v >> 16) & 0xFF) / 255
            g = CGFloat((v >> 8) & 0xFF) / 255; b = CGFloat(v & 0xFF) / 255
        default:
            return nil
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: max(0.35, a))
    }
}
