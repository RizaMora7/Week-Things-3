import Foundation

/// Verification harness (not part of the app):
///   xcrun swiftc Sources/{Models,ThingsDate,Strings,Planner,CalendarStore,SQLiteDB,Theme}.swift \
///          Tools/ordercheck.swift -o /tmp/ordercheck && /tmp/ordercheck
///   (no `-O`: whole-module optimisation takes minutes on this MacBook Air)
///
/// Checks two things:
///   1. The priority ladder: Important › Urgent › High › Medium › Low › untagged.
///   2. The Eisenhower quadrant split and day membership, with the cases
///      surfaced by the 2026-10-27 review.
/// Exits non-zero if anything fails, so it works as a final check
/// before rebuilding the app.

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
            // Quadrant split cases (fix of 2026-10-27).
            makeTask("t11", "Important con plazo mañana", tags: ["Important"], deadline: offset(1)),
            makeTask("t12", "Medium arrastrada de ayer", tags: ["Medium"], scheduled: offset(-1)),
            makeTask("t13", "Proyecto sin etiqueta", scheduled: offset(0), project: "p-x"),
            makeTask("t14", "Proyecto con High", tags: ["High"], scheduled: offset(0), project: "p-y"),
            // The case the review with real data surfaced: scheduled today, deadline tomorrow.
            makeTask("t15", "Important hoy con plazo mañana", tags: ["Important"],
                     deadline: offset(1), scheduled: offset(0)),
            makeTask("t16", "Futura con plazo futuro", deadline: offset(4), scheduled: offset(3)),
        ]

        func quadrant(_ t: TaskItem) -> String {
            let u = Planner.isUrgent(t, day: today), i = Planner.isImportant(t)
            return (u && i) ? "Q1" : (!u && i) ? "Q2" : (u && !i) ? "Q3" : "Q4"
        }
        let expected: [String: String] = [
            "t03": "Q4",   // today's Medium: no longer important, not urgent
            "t05": "Q2",   // Important with no deadline: important, not urgent
            "t11": "Q1",   // Important with deadline tomorrow: the new rule
            "t12": "Q3",   // Medium carried over from yesterday: urgent from a past date, not important
            "t13": "Q4",   // untagged project: being a project no longer scores
            "t14": "Q2",   // project with High: the tag scores
            "t15": "Q1",   // the real task that used to vanish from the plan
        ]

        for pref in [Lang.spanish, .english] {
            L.apply(pref)
            print("=== \(pref == .spanish ? "ES" : "EN") · day \(DateFormat.iso.string(from: today)) ===")
            let sorted = items.sorted { Planner.byPriority($0, $1, day: today) }
            for (i, t) in sorted.enumerated() {
                let tag = Planner.priorityTag(t) ?? "—"
                print("  \(String(format: "%2d", i + 1)). [\(tag)] rank=\(Planner.priorityRank(t)) "
                      + "urgente=\(Planner.isUrgent(t, day: today) ? "sí" : "no") "
                      + "\(quadrant(t))  \(Planner.cleanTitle(t.title)) · \(Planner.estimate(t)) min")
            }
            var counts = ["Q1": 0, "Q2": 0, "Q3": 0, "Q4": 0]
            for t in items { counts[quadrant(t), default: 0] += 1 }
            print("  quadrants: " + counts.sorted { $0.key < $1.key }
                  .map { "\($0.key)=\($0.value)" }.joined(separator: " "))
            print("")
        }

        var fallos: [String] = []
        for t in items {
            if let want = expected[t.id], want != quadrant(t) {
                fallos.append("\(t.id) \(t.title): esperaba \(want), dió \(quadrant(t))")
            }
        }
        let t15 = items.first { $0.id == "t15" }!, t16 = items.first { $0.id == "t16" }!
        if !Planner.isRelevant(t15, day: today) {
            fallos.append("t15 agendada hoy con plazo mañana quedó fuera del plan de hoy")
        }
        if Planner.isRelevant(t16, day: today) {
            fallos.append("t16 con agenda y plazo futuros entró en el plan de hoy")
        }
        // placement: with both dates present the earlier one wins.
        if t15.placement.map({ !cal.isDate($0, inSameDayAs: today) }) ?? true {
            fallos.append("t15 no se ubica en el día agendado (hoy)")
        }
        let soloPlazo = items.first { $0.id == "t02" }!
        if soloPlazo.placement.map({ !cal.isDate($0, inSameDayAs: today) }) ?? true {
            fallos.append("t02 con solo plazo perdió su ubicación")
        }
        if let p = items.first(where: { $0.id == "t05" })?.placement,
           cal.isDate(p, inSameDayAs: today) {
            fallos.append("t05 agendada en +3 días se muestra hoy")
        }
        let u = items.filter { Planner.isUrgent($0, day: today) }.count
        let i = items.filter { Planner.isImportant($0) }.count
        if u == 0 { fallos.append("ninguna tarea urgente: el eje de urgencia volvió a morir") }
        if i == 0 { fallos.append("ninguna tarea importante: el eje de importancia murió") }
        let mediumsSueltas = items.filter {
            $0.tags.contains("Medium") && !$0.tags.contains("Important") && !$0.tags.contains("High")
        }
        if mediumsSueltas.contains(where: Planner.isImportant) {
            fallos.append("una Medium sin otra etiqueta sigue contando como importante")
        }
        if fallos.isEmpty {
            print("OK · \(items.count) cases, urgent=\(u), important=\(i)")
        } else {
            print("FAILURES:"); fallos.forEach { print("  ✗ \($0)") }
            exit(1)
        }
    }
}
