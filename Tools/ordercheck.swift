import Foundation

/// Arnés de verificación (no forma parte de la app):
///   xcrun swiftc -O Sources/{Models,ThingsDate,Strings,Planner,CalendarStore,SQLiteDB,Theme}.swift \
///          Tools/ordercheck.swift -o /tmp/ordercheck && /tmp/ordercheck
/// Comprueba que la escalera de prioridad ordena como pidió Raúl:
/// Important › Urgent › High › Medium › Low › sin etiqueta.

func makeTask(_ id: String, _ title: String, tags: [String] = [], deadline: Int? = nil,
              scheduled: Int? = nil, checklist: Int = 0, project: String? = nil) -> TaskItem {
    TaskItem(id: id, title: title, notes: "", isProject: project != nil, start: .anytime,
             startRaw: scheduled, deadlineRaw: deadline, deadlineSuppressed: false,
             recurring: false, openChecklist: 0, totalChecklist: checklist,
             project: project, area: nil, heading: nil, tags: tags, sortIndex: 0, created: nil)
}

@main
enum OrderCheck {
    static func main() {
        let cal = Calendar(identifier: .gregorian)
        func bits(_ y: Int, _ m: Int, _ d: Int) -> Int { (y << 16) | (m << 12) | (d << 7) }
        let today = cal.startOfDay(for: Date())
        func offset(_ days: Int) -> Int {
            let d = cal.date(byAdding: .day, value: days, to: today)!
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return bits(c.year!, c.month!, c.day!)
        }

        let items: [TaskItem] = [
            makeTask("t01", "Low con plazo vencido", tags: ["Low"], deadline: offset(-2)),
            makeTask("t02", "Sin etiqueta urgente hoy", deadline: offset(0)),
            makeTask("t03", "Medium tranquila", tags: ["Medium"], scheduled: offset(0)),
            makeTask("t04", "Low tranquila", tags: ["Low"], scheduled: offset(0)),
            makeTask("t05", "Important sin plazo", tags: ["Important"], scheduled: offset(3)),
            makeTask("t06", "Urgent sin plazo", tags: ["Urgent"], scheduled: offset(3)),
            makeTask("t07", "High con checklist larga", tags: ["High"], scheduled: offset(0), checklist: 6),
            makeTask("t08", "Sin etiqueta sin fecha"),
            makeTask("t09", "High urgente por plazo", tags: ["High"], deadline: offset(0)),
            makeTask("t10", "Important urgente por plazo", tags: ["Important"], deadline: offset(-1)),
        ]

        for pref in [Lang.spanish, .english] {
            L.apply(pref)
            print("=== \(pref == .spanish ? "ES" : "EN") · día \(DateFormat.iso.string(from: today)) ===")
            let sorted = items.sorted { Planner.byPriority($0, $1, day: today) }
            for (i, t) in sorted.enumerated() {
                let tag = Planner.priorityTag(t) ?? "—"
                print("  \(String(format: "%2d", i + 1)). [\(tag)] rank=\(Planner.priorityRank(t)) "
                      + "urgente=\(Planner.isUrgent(t, day: today) ? "sí" : "no") "
                      + "\(Planner.cleanTitle(t.title)) · \(Planner.estimate(t)) min")
            }
            print("")
        }
    }
}
