import Foundation

/// The six frameworks offered by the daily view.
enum PlanFramework: Int, CaseIterable {
    case eisenhower = 0
    case timeBlock = 1
    case frog = 2
    case moscow = 3
    case oneThreeFive = 4
    case pareto = 5

    var label: String {
        switch self {
        case .eisenhower: return L.s("fw.eisenhower")
        case .timeBlock: return L.s("fw.timeBlock")
        case .frog: return L.s("fw.frog")
        case .moscow: return L.s("fw.moscow")
        case .oneThreeFive: return L.s("fw.135")
        case .pareto: return L.s("fw.pareto")
        }
    }

    var shortLabel: String {
        switch self {
        case .eisenhower: return L.s("fwS.eisenhower")
        case .timeBlock: return L.s("fwS.timeBlock")
        case .frog: return L.s("fwS.frog")
        case .moscow: return L.s("fwS.moscow")
        case .oneThreeFive: return L.s("fwS.135")
        case .pareto: return L.s("fwS.pareto")
        }
    }

    /// One honest line about what each framework decides and from which signal.
    var explainer: String {
        switch self {
        case .eisenhower: return L.s("fx.eisenhower")
        case .timeBlock: return L.s("fx.timeBlock")
        case .frog: return L.s("fx.frog")
        case .moscow: return L.s("fx.moscow")
        case .oneThreeFive: return L.s("fx.135")
        case .pareto: return L.s("fx.pareto")
        }
    }
}

enum EffortSize: Int { case small = 0, medium = 1, large = 2 }

enum Quadrant: Int, CaseIterable {
    case q1 = 0, q2 = 1, q3 = 2, q4 = 3
    var title: String {
        switch self {
        case .q1: return L.s("q1.title")
        case .q2: return L.s("q2.title")
        case .q3: return L.s("q3.title")
        case .q4: return L.s("q4.title")
        }
    }
    var hint: String {
        switch self {
        case .q1: return L.s("q1.hint")
        case .q2: return L.s("q2.hint")
        case .q3: return L.s("q3.hint")
        case .q4: return L.s("q4.hint")
        }
    }
}

enum Moscow: Int, CaseIterable {
    case must = 0, should = 1, could = 2, wont = 3
    var title: String {
        switch self {
        case .must: return L.s("m.must")
        case .should: return L.s("m.should")
        case .could: return L.s("m.could")
        case .wont: return L.s("m.wont")
        }
    }
}

/// A slice of the day.
struct PlanBlock {
    enum Kind: Int, CaseIterable { case calendar, deep, admin, lowEnergy, buffer, rest
        var label: String {
            switch self {
            case .calendar: return L.s("k.calendar")
            case .deep: return L.s("k.deep")
            case .admin: return L.s("k.admin")
            case .lowEnergy: return L.s("k.lowEnergy")
            case .buffer: return L.s("k.buffer")
            case .rest: return L.s("k.rest")
            }
        }
    }
    let start: Date
    let end: Date
    let kind: Kind
    let title: String
    let items: [TaskItem]
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

/// Result of applying a framework to a day.
struct DayPlan {
    let framework: PlanFramework
    let day: Date
    var events: [CalEvent] = []
    var quadrants: [Quadrant: [TaskItem]] = [:]
    var moscow: [Moscow: [TaskItem]] = [:]
    var oneThreeFive: (big: [TaskItem], medium: [TaskItem], small: [TaskItem]) = ([], [], [])
    var top3: [TaskItem] = []
    var frog: TaskItem?
    var quickWins: [TaskItem] = []
    var blocks: [PlanBlock] = []
    var leftovers: [TaskItem] = []
    var directives: [String] = []
    var capacityMinutes = 0
    var demandMinutes = 0
}

/// Daily plan engine. All prioritisation logic lives here; the view only draws.
enum Planner {
    static let calendar = Calendar.current

    // MARK: signals

    /// Estimated effort in minutes, inferred (not invented):
    /// 1) time written in the title or notes ("25 min", "1h30", "60 min");
    /// 2) number of checklist items × 10 min, minimum 15;
    /// 3) fallback by tag: High 45, Medium 30, Low 15.
    static func estimate(_ t: TaskItem) -> Int {
        if let m = parseDuration(t.title) ?? parseDuration(t.notes) { return m }
        if t.totalChecklist > 0 { return max(15, min(180, t.totalChecklist * 10)) }
        if t.isProject { return 90 }
        if t.tags.contains("High") || t.tags.contains("Important") { return 45 }
        if t.tags.contains("Low") { return 15 }
        return 30
    }

    static func size(_ minutes: Int) -> EffortSize {
        minutes >= 60 ? .large : (minutes >= 25 ? .medium : .small)
    }

    /// "25 min", "1h30", "60 minutos", "(1 h)"
    static func parseDuration(_ text: String) -> Int? {
        let lower = text.lowercased()
        let patterns = [
            "(\\d+)\\s*h\\s*(\\d+)?\\s*min",
            "(\\d+)\\s*(?:min|mins|minutos)",
            "(\\d+)\\s*h\\b",
            "(\\d+)\\s*horas?",
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let range = NSRange(lower.startIndex..., in: lower)
            guard let m = re.firstMatch(in: lower, range: range) else { continue }
            func group(_ i: Int) -> Int? {
                guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: lower) else { return nil }
                return Int(lower[r])
            }
            if p.contains("h\\s*(\\d+)?"), let h = group(1) {
                return h * 60 + (group(2) ?? 0)
            }
            if let v = group(1) { return p.contains("min") ? v : v * 60 }
        }
        return nil
    }

    /// "Gestión del pipeline · 15 min" → "Gestión del pipeline". The timeline already
    /// prints the block's minutes, so the duration in the title is redundant.
    static func cleanTitle(_ raw: String) -> String {
        let pattern = "[\\s(\\[·,\\-–—]*\\d+\\s*(?:mins?\\.?|minutos?|hrs?|horas?)\\s*[\\)\\]]?\\s*$"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return raw }
        var s = raw
        for _ in 0..<2 {
            let r = NSRange(s.startIndex..<s.endIndex, in: s)
            let out = re.stringByReplacingMatches(in: s, range: r, withTemplate: "")
            if out == s || !bracketsBalanced(out) { break }
            s = out
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ·-–—,(["))
        return s.isEmpty || !bracketsBalanced(s) ? raw : s
    }

    /// "(Vie 15 min)" trimmed to "(Vie" is worse than not trimming at all.
    static func bracketsBalanced(_ s: String) -> Bool {
        var round = 0, square = 0
        for ch in s {
            switch ch {
            case "(": round += 1
            case ")": round -= 1
            case "[": square += 1
            case "]": square -= 1
            default: break
            }
            if round < 0 || square < 0 { return false }
        }
        return round == 0 && square == 0
    }

    /// Urgency: the `Urgent` tag, a deadline that has passed or falls tomorrow at the latest, or a
    /// scheduled date that has passed and is still open (Things carries it to Today).
    ///
    /// Widened on 2026-10-27. With only «deadline today or overdue» the axis was dead in this
    /// project: deadlines are rarely used and the `Urgent` tag shows up rarely, so Q1 and Q3
    /// were always empty and the matrix collapsed into a single axis.
    static func isUrgent(_ t: TaskItem, day: Date) -> Bool {
        if t.tags.contains("Urgent") { return true }
        let today = calendar.startOfDay(for: day)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        if let dl = t.deadline, calendar.startOfDay(for: dl) <= tomorrow { return true }
        if let s = t.scheduled, calendar.startOfDay(for: s) < today { return true }
        return false
    }

    /// Importance follows the same ladder used by QwenWork's scheduled tasks:
    /// `Important` and `High` matter; `Medium`, `Low` or no tag don't.
    ///
    /// It used to be enough to have `Medium`, or for the row to be a project. That was written
    /// when this project only had Low/Medium/High and treating Medium as
    /// «not important» emptied the matrix. Once `Important` tags existed, that
    /// compromise erased the difference: `Important` didn't decide anything's quadrant.
    /// A project only scores if it carries `Important` or `High` itself.
    static func isImportant(_ t: TaskItem) -> Bool {
        return t.tags.contains("Important") || t.tags.contains("High")
    }

    /// Priority ladder by tag, in the requested order:
    /// Important › Urgent › High › Medium › Low › untagged.
    static func priorityRank(_ t: TaskItem) -> Int {
        if t.tags.contains("Important") { return 0 }
        if t.tags.contains("Urgent") { return 1 }
        if t.tags.contains("High") { return 2 }
        if t.tags.contains("Medium") { return 3 }
        if t.tags.contains("Low") { return 4 }
        return 5
    }

    /// The ladder tag that ranks the task, exactly as written in
    /// Things. `nil` if it has none (then deadline and estimate decide the order).
    static func priorityTag(_ t: TaskItem) -> String? {
        for name in ["Important", "Urgent", "High", "Medium", "Low"] where t.tags.contains(name) {
            return name
        }
        return nil
    }

    /// The app's canonical order: tag priority first, then real urgency
    /// (an overdue low-tag item beats an untagged one), then the quick ones.
    static func byPriority(_ a: TaskItem, _ b: TaskItem, day: Date) -> Bool {
        let ra = priorityRank(a), rb = priorityRank(b)
        if ra != rb { return ra < rb }
        let ua = isUrgent(a, day: day), ub = isUrgent(b, day: day)
        if ua != ub { return ua }
        let ia = isImportant(a), ib = isImportant(b)
        if ia != ib { return ia }
        if daysOverdue(a, day: day) != daysOverdue(b, day: day) {
            return daysOverdue(a, day: day) > daysOverdue(b, day: day)
        }
        return estimate(a) < estimate(b)
    }

    static func daysOverdue(_ t: TaskItem, day: Date) -> Int {
        guard let dl = t.deadline else { return 0 }
        let d = calendar.dateComponents([.day], from: calendar.startOfDay(for: dl),
                                         to: calendar.startOfDay(for: day)).day ?? 0
        return max(0, d)
    }

    /// Does this task belong to that day's plan? Either signal is enough:
    /// scheduled on or before that day, or deadline on or before that day.
    ///
    /// Fixed on 2026-10-27: the deadline used to take precedence and `return`, so
    /// a task scheduled for today with a deadline tomorrow was left out of today's plan. That's
    /// the case of the day's only `Important`, which vanished and left Q1 empty.
    static func isRelevant(_ t: TaskItem, day: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        if let dl = t.deadline, calendar.startOfDay(for: dl) <= dayStart { return true }
        if let s = t.scheduled, calendar.startOfDay(for: s) <= dayStart { return true }
        return false
    }

    // MARK: construction

    /// Builds the day's plan. `tasks` must be the ones that fall on that day
    /// (deadline or schedule), plus overdue ones if `includeOverdue`.
    static func build(framework: PlanFramework, day: Date, tasks: [TaskItem],
                      events: [CalEvent], includeOverdue: Bool) -> DayPlan {
        var plan = DayPlan(framework: framework, day: day)
        let dayStart = calendar.startOfDay(for: day)

        let relevant = tasks.filter { isRelevant($0, day: day) }
        let sortedAll = relevant.sorted { byPriority($0, $1, day: day) }

        plan.events = events.sorted { $0.sortDate < $1.sortDate }

        // Eisenhower
        for t in sortedAll {
            let u = isUrgent(t, day: day), i = isImportant(t)
            let q: Quadrant = (u && i) ? .q1 : (!u && i) ? .q2 : (u && !i) ? .q3 : .q4
            plan.quadrants[q, default: []].append(t)
        }

        // Frog and quick wins
        plan.frog = sortedAll.first { isImportant($0) && estimate($0) >= 45 } ?? sortedAll.first
        plan.quickWins = sortedAll.filter { estimate($0) <= 5 && $0.id != plan.frog?.id }.prefix(5).map { $0 }

        // Pareto Top-3
        plan.top3 = Array(sortedAll.prefix(3))

        // Capacity: 08:00–18:00 working day minus what the calendar already takes.
        let busy = busyMinutes(events, day: dayStart)
        plan.capacityMinutes = max(60, 600 - busy - 60)     // 60 min of statutory breaks
        plan.demandMinutes = sortedAll.reduce(0) { $0 + estimate($1) }

        // MoSCoW: scope against the day's real capacity, not a mirror of urgency.
        var must: [TaskItem] = [], should: [TaskItem] = [], could: [TaskItem] = [], wont: [TaskItem] = []
        let mustLine = Int(Double(plan.capacityMinutes) * 0.55)
        let shouldLine = Int(Double(plan.capacityMinutes) * 0.85)
        var acc = 0
        for t in sortedAll {
            acc += estimate(t)
            if isUrgent(t, day: day) && isImportant(t) { must.append(t); continue }
            if acc <= mustLine { must.append(t) }
            else if acc <= shouldLine { should.append(t) }
            else if isImportant(t) || size(estimate(t)) != .small { could.append(t) }
            else { wont.append(t) }
        }
        plan.moscow = [.must: must, .should: should, .could: could, .wont: wont]

        // 1-3-5
        var big: [TaskItem] = [], med: [TaskItem] = [], small: [TaskItem] = []
        var rest: [TaskItem] = []
        for t in sortedAll {
            switch size(estimate(t)) {
            case .large: if big.count < 1 { big.append(t) } else { rest.append(t) }
            case .medium: if med.count < 3 { med.append(t) } else { rest.append(t) }
            case .small: if small.count < 5 { small.append(t) } else { rest.append(t) }
            }
        }
        plan.oneThreeFive = (big, med, small)
        plan.leftovers = rest

        plan.blocks = makeBlocks(framework: framework, day: dayStart, ordered: orderedFor(framework, plan, sortedAll),
                                 events: events, includeOverdue: includeOverdue)
        plan.directives = makeDirectives(framework: framework, plan: plan)
        return plan
    }

    /// Execution order for the chosen framework.
    private static func orderedFor(_ fw: PlanFramework, _ plan: DayPlan, _ base: [TaskItem]) -> [TaskItem] {
        switch fw {
        case .frog:
            guard let frog = plan.frog else { return base }
            return [frog] + base.filter { $0.id != frog.id }
        case .moscow:
            let m = plan.moscow[.must] ?? []
            let s = plan.moscow[.should] ?? []
            let c = plan.moscow[.could] ?? []
            return m + s + c
        case .oneThreeFive:
            let trio = plan.oneThreeFive
            return trio.big + trio.medium + trio.small
        case .pareto:
            let top = Set(plan.top3.map { $0.id })
            return plan.top3 + base.filter { !top.contains($0.id) }
        case .eisenhower:
            return (plan.quadrants[.q1] ?? []) + (plan.quadrants[.q2] ?? [])
                 + (plan.quadrants[.q3] ?? []) + (plan.quadrants[.q4] ?? [])
        case .timeBlock:
            // Size rules here: big ones in deep focus, medium ones admin, small ones last.
            return base.sorted { a, b in
                let ea = estimate(a), eb = estimate(b)
                if isImportant(a) != isImportant(b) { return isImportant(a) }
                return eb > ea
            }
        }
    }

    private static func busyMinutes(_ events: [CalEvent], day: Date) -> Int {
        events.reduce(0) { acc, e in
            guard let s = e.start, let en = e.end, !e.allDay else { return acc }
            let dayEnd = calendar.date(byAdding: .hour, value: 18, to: day)!
            let from = max(s, calendar.date(byAdding: .hour, value: 8, to: day)!)
            let to = min(en, dayEnd)
            return to > from ? acc + Int(to.timeIntervalSince(from) / 60) : acc
        }
    }

    /// 08:00–18:00 timeline respecting the calendar, with blocks by energy type.
    private static func makeBlocks(framework: PlanFramework, day: Date, ordered: [TaskItem],
                                   events: [CalEvent], includeOverdue: Bool) -> [PlanBlock] {
        var blocks: [PlanBlock] = []
        let windowStart = calendar.date(byAdding: .hour, value: 8, to: day)!
        let windowEnd = calendar.date(byAdding: .hour, value: 18, to: day)!
        let dayEndRef = calendar.startOfDay(for: day)

        // 1) Real events come first.
        for e in events where !e.allDay {
            guard let s = e.start, let en = e.end else { continue }
            let clippedStart = max(s, windowStart)
            let clippedEnd = min(en, windowEnd)
            if clippedEnd > clippedStart {
                blocks.append(PlanBlock(start: clippedStart, end: clippedEnd, kind: .calendar,
                                        title: e.title, items: []))
            }
        }
        blocks.sort { $0.start < $1.start }

        func occupied(_ from: Date, _ to: Date) -> Bool {
            blocks.contains { from < $0.end && to > $0.start }
        }

        func slot(minutes: Int) -> Date? {
            var t = windowStart
            while t.addingTimeInterval(TimeInterval(minutes * 60)) <= windowEnd {
                let endT = t.addingTimeInterval(TimeInterval(minutes * 60))
                if !occupied(t, endT) && endT > dayEndRef.addingTimeInterval(0) { return t }
                t = t.addingTimeInterval(15 * 60)
            }
            return nil
        }

        // 2) Lunch break: fixed at 13:00, and only if that slot is free.
        let lunchStart = calendar.date(byAdding: .hour, value: 13, to: day)!
        let lunchEnd = lunchStart.addingTimeInterval(3600)
        if lunchEnd <= windowEnd && !occupied(lunchStart, lunchEnd) {
            blocks.append(PlanBlock(start: lunchStart, end: lunchEnd, kind: .rest,
                                    title: L.s("b.longBreak"), items: []))
        }

        // 3) Tasks into blocks.
        var deepRun = 0
        for t in ordered {
            let est = estimate(t)
            let kind: PlanBlock.Kind
            if isImportant(t) && est >= 45 { kind = .deep }
            else if est <= 20 { kind = .lowEnergy }
            else { kind = .admin }

            let length = kind == .deep ? min(120, max(60, est)) : min(60, max(15, est))
            guard let start = slot(minutes: length) else { continue }
            let end = start.addingTimeInterval(TimeInterval(length * 60))
            blocks.append(PlanBlock(start: start, end: end, kind: kind, title: cleanTitle(t.title), items: [t]))
            deepRun += 1
            if kind == .deep && deepRun % 2 == 0, let b = slot(minutes: 15) {
                blocks.append(PlanBlock(start: b, end: b.addingTimeInterval(900), kind: .buffer,
                                        title: L.s("b.buffer"), items: []))
            }
        }
        blocks.sort { $0.start < $1.start }
        return blocks
    }

    private static func makeDirectives(framework: PlanFramework, plan: DayPlan) -> [String] {
        var out: [String] = []
        let f = DateFormat.hm

        if let frog = plan.frog {
            let atDate = plan.blocks.first(where: { $0.items.contains(where: { $0.id == frog.id }) })?.start
            let at = atDate.map { L.f("d.at", f.string(from: $0)) } ?? ""
            out.append(L.f("d.frog", frog.title, at))
        }
        if !plan.quickWins.isEmpty {
            out.append(L.f("d.twoMin", plan.quickWins.count,
                           plan.quickWins.prefix(2).map { $0.title }.joined(separator: " · ")))
        }
        switch framework {
        case .eisenhower:
            out.append(L.f("d.q1q3", (plan.quadrants[.q1] ?? []).count, (plan.quadrants[.q3] ?? []).count))
        case .moscow:
            out.append(L.f("d.wont", (plan.moscow[.wont] ?? []).count))
        case .oneThreeFive:
            let trio = plan.oneThreeFive
            out.append(L.f("d.135", trio.big.count, trio.medium.count, trio.small.count, plan.leftovers.count))
        case .pareto:
            out.append(L.f("d.top3", plan.top3.prefix(3).map { $0.title }.joined(separator: " · ")))
        case .timeBlock, .frog:
            break
        }
        out.append(plan.demandMinutes > plan.capacityMinutes
            ? L.f("d.overload", plan.demandMinutes, plan.capacityMinutes)
            : L.f("d.fits", plan.demandMinutes, plan.capacityMinutes))
        out.append(L.s("d.parkinson"))
        return out
    }
}
