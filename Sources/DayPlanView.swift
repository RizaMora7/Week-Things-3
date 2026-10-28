import AppKit

/// Native rendering of the daily plan. Takes a DayPlan and draws the four sections
/// you already know from the HTML: framework panel, timeline, list and guidelines.
final class DayPlanView: NSView {
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let doc = FlipView()
    var onSelect: ((TaskItem) -> Void)?
    var onMenu: ((TaskItem) -> NSMenu?)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 18, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.topLeftOrigin = true
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    private var pal = Palette.current(dark: false)
    private var currentDay = Date()

    func render(_ plan: DayPlan, palette: Palette) {
        pal = palette
        currentDay = plan.day
        layer?.backgroundColor = palette.windowBG.cgColor
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        addHeader(plan)
        addFrameworkPanel(plan)
        addTimeline(plan)
        addTaskList(plan)
        addDirectives(plan)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        if ProcessInfo.processInfo.environment["SEMANA_DEBUG"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.debugDump() }
        }
    }

    // MARK: header

    private func addHeader(_ plan: DayPlan) {
        let overdue = (plan.quadrants.values.flatMap { $0 }).filter {
            Planner.daysOverdue($0, day: plan.day) > 0
        }.count
        let isToday = Calendar.current.isDate(plan.day, inSameDayAs: Date())
        let heading = DateFormat.dayHeading(plan.day)
        let titleText = isToday ? L.f("title.dayHoy", heading) : heading
        let title = label(titleText, size: 17, weight: .semibold,
                          color: isToday ? pal.todayAccent : pal.title)
        let sub = label("\(plan.framework.label) · \(plan.framework.explainer)", size: 11.5, weight: .regular,
                        color: pal.meta)
        sub.maximumNumberOfLines = 2
        let stats = label(L.f("day.demand", plan.demandMinutes, plan.capacityMinutes,
                              plan.events.count, L.n("u.event", plan.events.count),
                              overdue, L.n("u.overdue", overdue)),
                          size: 11, weight: .regular, color: pal.badgeText)
        [title, sub, stats].forEach { addFullWidth($0) }
    }

    // MARK: framework panel

    private func addFrameworkPanel(_ plan: DayPlan) {
        switch plan.framework {
        case .eisenhower: addMatrix(plan)
        case .moscow: addMoscow(plan)
        case .oneThreeFive: add135(plan)
        case .pareto: addTop3(plan)
        case .frog, .timeBlock: addFocusStrip(plan)
        }
    }

    private func addMatrix(_ plan: DayPlan) {
        let section = sectionBox(L.s("day.matrix"))
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 8
        for row in [[Quadrant.q1, Quadrant.q2], [Quadrant.q3, Quadrant.q4]] {
            let h = NSStackView()
            h.orientation = .horizontal
            h.spacing = 8
            h.distribution = .fillEqually
            for q in row { h.addArrangedSubview(quadrantCard(q, plan.quadrants[q] ?? [])) }
            grid.addArrangedSubview(h)
            // Without this the row takes its width from the content: a card with long
            // titles overflowed the section and drew over its neighbour.
            h.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        }
        section.addArrangedSubview(grid)
        grid.widthAnchor.constraint(equalTo: section.widthAnchor, constant: -28).isActive = true
    }

    private func quadrantCard(_ q: Quadrant, _ items: [TaskItem]) -> NSView {
        let tint = pal.quadrantTint(q)
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = tint.bg.cgColor
        box.layer?.borderColor = tint.edge.cgColor
        box.layer?.borderWidth = 1
        box.layer?.cornerRadius = 8
        // Accent bar on the left: identifies the quadrant at a glance.
        let accent = NSView()
        accent.wantsLayer = true
        accent.layer?.backgroundColor = tint.edge.cgColor
        accent.layer?.cornerRadius = 2
        accent.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(accent)
        let head = label("\(q.title) · \(items.count)", size: 11.5, weight: .semibold, color: tint.edge)
        let hint = label(q.hint, size: 10, weight: .regular, color: pal.meta)
        let body = NSStackView()
        body.orientation = .vertical
        // `.width` is only valid in horizontal stacks: in a vertical one AppKit falls back to
        // `.trailing` and the lines came out right-aligned. Align to the
        // left and set each line's width by hand.
        body.alignment = .leading
        body.distribution = .fill
        body.spacing = 3
        for t in items.prefix(6) {
            let l = label("· \(t.title)", size: 11, weight: .regular, color: pal.title)
            // A single truncated line: two lines without `preferredMaxLayoutWidth` would make
            // the field measure its whole text and eat the right half of the matrix.
            l.maximumNumberOfLines = 1
            l.lineBreakMode = .byTruncatingTail
            body.addArrangedSubview(l)
            l.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        if items.count > 6 {
            let more = label(L.f("day.more", items.count - 6), size: 10, weight: .regular, color: pal.meta)
            body.addArrangedSubview(more)
            more.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        if items.isEmpty {
            let none = label(L.s("day.none"), size: 10, weight: .regular, color: pal.meta)
            body.addArrangedSubview(none)
            none.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        [head, hint, body].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview($0)
        }
        NSLayoutConstraint.activate([
            accent.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            accent.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            accent.widthAnchor.constraint(equalToConstant: 3),
            accent.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            head.topAnchor.constraint(equalTo: box.topAnchor, constant: 9),
            head.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            head.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -10),
            hint.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 1),
            hint.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -10),
            body.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 7),
            body.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            body.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            body.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
        ])
        return box
    }

    private func addMoscow(_ plan: DayPlan) {
        let section = sectionBox(PlanFramework.moscow.label)
        for m in Moscow.allCases {
            let items = plan.moscow[m] ?? []
            addBounded(label("\(m.title) — \(items.count)", size: 11.5, weight: .semibold, color: pal.title), to: section)
            for t in items.prefix(m == .wont ? 4 : 8) {
                addBounded(taskLine(t, indent: 14), to: section)
            }
        }
    }

    private func add135(_ plan: DayPlan) {
        let section = sectionBox(L.s("day.trio"))
        let trio = plan.oneThreeFive
        let bigText = trio.big.isEmpty ? L.s("day.noBig")
            : "— " + trio.big.map { Planner.cleanTitle($0.title) }.joined(separator: ", ")
        addBounded(label("\(L.s("day.big")) \(bigText)", size: 11.5, weight: .semibold, color: pal.title), to: section)
        addBounded(label(L.s("day.medium"), size: 11.5, weight: .semibold, color: pal.title), to: section)
        trio.medium.forEach { addBounded(taskLine($0, indent: 14), to: section) }
        addBounded(label(L.s("day.small"), size: 11.5, weight: .semibold, color: pal.title), to: section)
        trio.small.forEach { addBounded(taskLine($0, indent: 14), to: section) }
        if !plan.leftovers.isEmpty {
            addBounded(label(L.f("day.overCapacity", plan.leftovers.count),
                             size: 11, weight: .regular, color: pal.meta), to: section)
        }
    }

    private func addTop3(_ plan: DayPlan) {
        let section = sectionBox(L.s("day.top3"))
        for (i, t) in plan.top3.enumerated() {
            addBounded(label("\(i + 1). \(Planner.cleanTitle(t.title))  ·  \(Planner.estimate(t)) min",
                             size: 12, weight: .medium, color: pal.title), to: section)
        }
        if plan.top3.isEmpty {
            addBounded(label(L.s("day.noTasks"), size: 11, weight: .regular, color: pal.meta), to: section)
        }
    }

    private func addFocusStrip(_ plan: DayPlan) {
        let section = sectionBox(plan.framework == .frog ? PlanFramework.frog.label : L.s("day.energy"))
        if let frog = plan.frog {
            addBounded(label(L.f("day.first", Planner.cleanTitle(frog.title), Planner.estimate(frog)),
                             size: 12, weight: .semibold, color: pal.deadline), to: section)
        }
        let counts = Dictionary(grouping: plan.blocks, by: { $0.kind }).mapValues { $0.count }
        let text = PlanBlock.Kind.allCases.compactMap { k -> String? in
            guard let n = counts[k], n > 0 else { return nil }
            return "\(k.label) \(n)"
        }.joined(separator: " · ")
        addBounded(label(text.isEmpty ? L.s("day.noBlocks") : text,
                         size: 11, weight: .regular, color: pal.meta), to: section)
    }

    // MARK: timeline

    private func addTimeline(_ plan: DayPlan) {
        let section = sectionBox(L.s("day.timeline"))
        section.addArrangedSubview(label(L.s("day.legend"), size: 10, weight: .regular, color: pal.meta))
        if plan.blocks.isEmpty {
            section.addArrangedSubview(label(L.s("day.emptyBlock"),
                                             size: 11, weight: .regular, color: pal.meta))
        }
        for b in plan.blocks {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            let time = label("\(DateFormat.hm.string(from: b.start))–\(DateFormat.hm.string(from: b.end))",
                             size: 11, weight: .medium, color: pal.meta)
            time.widthAnchor.constraint(equalToConstant: 92).isActive = true
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.backgroundColor = blockColor(b.kind).cgColor
            bar.layer?.cornerRadius = 2
            bar.widthAnchor.constraint(equalToConstant: 4).isActive = true
            let kindText = (b.kind == .buffer || b.kind == .rest) ? "" : "  ·  \(b.kind.label)"
            let text = label("\(b.title)  ·  \(b.minutes) min\(kindText)",
                             size: 11.5, weight: b.kind == .calendar ? .semibold : .regular, color: pal.title)
            text.lineBreakMode = .byTruncatingTail
            text.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(time)
            row.addArrangedSubview(bar)
            row.addArrangedSubview(text)
            bar.heightAnchor.constraint(equalTo: row.heightAnchor).isActive = true
            section.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: section.widthAnchor, constant: -28).isActive = true
        }
    }

    private func blockColor(_ kind: PlanBlock.Kind) -> NSColor {
        switch kind {
        case .calendar: return pal.scheduled
        case .deep: return pal.deadline
        case .admin: return pal.todayAccent
        case .lowEnergy: return pal.recurring
        case .buffer: return pal.meta
        case .rest: return pal.separator
        }
    }

    // MARK: list

    private func addTaskList(_ plan: DayPlan) {
        var seen = Set<String>()
        let all = plan.quadrants.values.flatMap { $0 }.filter { seen.insert($0.id).inserted }
        let ordered = all.sorted { Planner.byPriority($0, $1, day: plan.day) }
        let section = sectionBox(L.f("day.tasks", ordered.count))
        for t in ordered.prefix(60) { addBounded(taskLine(t, indent: 0), to: section) }
        if ordered.isEmpty {
            addBounded(label(L.s("day.emptyDay"), size: 11, weight: .regular, color: pal.meta), to: section)
        }
    }

    private func taskLine(_ t: TaskItem, indent: CGFloat) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = tagColor(t).cgColor
        dot.layer?.cornerRadius = 3
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
        let text = label(t.title, size: 11.5, weight: .regular, color: pal.title)
        text.lineBreakMode = .byTruncatingTail
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let over = Planner.daysOverdue(t, day: Date())
        let minutes = Planner.estimate(t)
        let pTag = Planner.priorityTag(t)
        let head: String
        if let pTag { head = L.f("day.priority", pTag, minutes) }
        else {
            head = L.f("day.min", minutes)
                + (Planner.isUrgent(t, day: currentDay) ? " · " + L.s("day.urgCal") : "")
        }
        let meta = label(head + (over > 0 ? " · " + L.f("day.overdueTag", over) : ""),
                         size: 10, weight: .regular, color: pal.meta)
        row.addArrangedSubview(dot)
        row.addArrangedSubview(text)
        row.addArrangedSubview(meta)
        row.edgeInsets = NSEdgeInsets(top: 1, left: indent, bottom: 1, right: 0)
        let card = ClickRow()
        card.onClick = { [weak self] in self?.onSelect?(t) }
        card.menuProvider = { [weak self] in self?.onMenu?(t) }
        card.attach(row)
        return card
    }

    private func tagColor(_ t: TaskItem) -> NSColor {
        switch Planner.priorityRank(t) {
        case 0, 1: return pal.deadline        // Important / Urgent
        case 2: return pal.warn               // High
        case 3: return pal.scheduled          // Medium
        default: return pal.meta              // Low or untagged
        }
    }

    // MARK: guidelines

    private func addDirectives(_ plan: DayPlan) {
        let section = sectionBox(L.s("day.directives"))
        for d in plan.directives {
            let l = label("— \(d)", size: 11.5, weight: .regular, color: pal.title)
            l.maximumNumberOfLines = 3
            section.addArrangedSubview(l)
            // The stack aligns to the left edge: without this cap the text would measure its
            // single-line length and spill out of the card.
            l.widthAnchor.constraint(lessThanOrEqualTo: section.widthAnchor, constant: -28).isActive = true
        }
    }

    // MARK: utilities

    private func sectionBox(_ title: String) -> NSStackView {
        let box = NSStackView()
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 5
        box.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)
        box.wantsLayer = true
        box.layer?.backgroundColor = pal.columnBG.cgColor
        box.layer?.cornerRadius = 10
        box.layer?.borderColor = pal.separator.cgColor
        box.layer?.borderWidth = 1
        let head = label(title, size: 12.5, weight: .semibold, color: pal.columnHeader)
        box.addArrangedSubview(head)
        addFullWidth(box)
        box.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        return box
    }

    private func addFullWidth(_ v: NSView) {
        stack.addArrangedSubview(v)
    }

    /// Adds to a section and caps its usable width. Sections align to the
    /// left, so without the cap a long line would measure its single-line length
    /// and spill out of the card.
    @discardableResult
    private func addBounded(_ v: NSView, to section: NSStackView) -> NSView {
        section.addArrangedSubview(v)
        v.widthAnchor.constraint(lessThanOrEqualTo: section.widthAnchor, constant: -28).isActive = true
        return v
    }

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.maximumNumberOfLines = 2
        l.lineBreakMode = .byWordWrapping
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // Without this the field asks for the width of its whole text on one line and overflows the
        // section; with low resistance it truncates (and wraps) before pushing the window.
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    /// Diagnostic dump (SEMANA_DEBUG=1) to catch collapsed sections.
    func debugDump() {
        needsLayout = true
        layoutSubtreeIfNeeded()
        func line(_ v: NSView, _ depth: Int) {
            let pad = String(repeating: "  ", count: depth)
            let name = String(describing: type(of: v))
            let fit = v.fittingSize
            let txt = (v as? NSTextField)?.stringValue.prefix(38).replacingOccurrences(of: "\n", with: " ") ?? ""
            let msg = "\(pad)\(name) frame=\(v.frame) fit=\(fit) huggingY=\(v.contentHuggingPriority(for: .vertical).rawValue) \(txt)\n"
            FileHandle.standardError.write(msg.data(using: .utf8)!)
            if depth < 3 { v.subviews.forEach { line($0, depth + 1) } }
        }
        FileHandle.standardError.write("== DayPlanView ==\n".data(using: .utf8)!)
        line(self, 0)
        line(stack, 1)
    }
}

/// Clickable row that forwards clicks and the context menu.
final class ClickRow: NSView {
    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    private var inner: NSView?

    func attach(_ view: NSView) {
        inner?.removeFromSuperview()
        inner = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func rightMouseDown(with event: NSEvent) {
        guard let menuProvider, let m = menuProvider() else { return }
        NSMenu.popUpContextMenu(m, with: event, for: self)
    }
}
