import AppKit

/// Calendar picker in a popover that doesn't close when you tick a box.
///
/// Replaces the old NSMenu, which had three flaws: it closed on every click (changing
/// five calendars meant opening it five times), it repeated «· Google» on every row,
/// and it showed the same title three times even though the selection is stored by
/// title, so ticking one ticked all three without it being visible.
///
/// Here each title appears once, grouped under its account, with the calendar's colour
/// dot; system noise (suggestions, birthdays, moon phases) goes last.
final class CalendarPicker: NSViewController {
    private struct Row { let title: String; let color: NSColor }
    private struct Section { let header: String; var rows: [Row] }

    private let sections: [Section]
    private var selected: Set<String>
    private let mine: Set<String>
    private let onChange: (Set<String>) -> Void
    private var checkboxes: [String: NSButton] = [:]

    init(calendars: [CalSource], onChange: @escaping (Set<String>) -> Void) {
        self.selected = Set(calendars.filter { $0.enabled }.map { $0.title })
        self.mine = Set(calendars.filter { !CalendarStore.isNoise($0.title) }.map { $0.title })
        self.onChange = onChange
        self.sections = CalendarPicker.group(calendars)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    /// One row per title (first occurrence wins), grouped by account in a stable
    /// order: iCloud, Google, Outlook/Exchange, the rest, local, subscribed and,
    /// last, system noise.
    private static func group(_ calendars: [CalSource]) -> [Section] {
        let order = ["iCloud", "Google", "Outlook", "Exchange", "CalDAV"]
        var seen = Set<String>()
        var byHeader: [String: [Row]] = [:]
        var headers: [String] = []
        let noiseHeader = L.s("cal.section.noise")

        for c in calendars where !seen.contains(c.title) {
            seen.insert(c.title)
            let header: String
            if CalendarStore.isNoise(c.title) {
                header = noiseHeader
            } else {
                let p = CalendarStore.providerLabel(c.provider)
                header = p.isEmpty ? L.s("cal.provider.other") : p
            }
            if byHeader[header] == nil { headers.append(header) }
            byHeader[header, default: []].append(Row(title: c.title, color: c.color))
        }

        func rank(_ h: String) -> Int {
            if h == noiseHeader { return 99 }
            if let i = order.firstIndex(of: h) { return i }
            if h == L.s("cal.provider.local") { return 50 }
            if h == L.s("cal.provider.subscribed") { return 51 }
            return 40
        }
        return headers
            .sorted { (rank($0), $0) < (rank($1), $1) }
            .map { h in
                Section(header: h, rows: (byHeader[h] ?? []).sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                })
            }
    }

    // MARK: - View

    override func loadView() {
        let width: CGFloat = 300

        let bulk = NSStackView(views: [
            linkButton(L.s("cal.all"), #selector(pickAll)),
            linkButton(L.s("cal.mine"), #selector(pickMine)),
            linkButton(L.s("cal.none"), #selector(pickNone)),
        ])
        bulk.orientation = .horizontal
        bulk.spacing = 14

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 3
        list.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 8, right: 0)
        for (i, s) in sections.enumerated() {
            let header = NSTextField(labelWithString: s.header.uppercased())
            header.font = .systemFont(ofSize: 10.5, weight: .semibold)
            header.textColor = .secondaryLabelColor
            list.addArrangedSubview(header)
            if i > 0 { list.setCustomSpacing(12, after: list.arrangedSubviews[list.arrangedSubviews.count - 2]) }
            list.setCustomSpacing(5, after: header)
            for r in s.rows { list.addArrangedSubview(row(r)) }
        }

        // Top-left-origin document: scrolling starts at the first section.
        let doc = FlipView()
        doc.topLeftOrigin = true
        doc.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(list)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: doc.topAnchor),
            list.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = doc
        scroll.translatesAutoresizingMaskIntoConstraints = false
        doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        let separator = NSBox()
        separator.boxType = .separator

        let root = NSStackView(views: [bulk, separator, scroll])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 6, right: 14)
        separator.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28).isActive = true
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28).isActive = true

        // Height follows the content, capped for long lists.
        list.layoutSubtreeIfNeeded()
        let natural = list.fittingSize.height
        scroll.heightAnchor.constraint(equalToConstant: min(natural, 440)).isActive = true
        root.widthAnchor.constraint(equalToConstant: width).isActive = true

        view = root
    }

    private func row(_ r: Row) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        // Opaque with a neutral grey ring: pale colours (lavender, light blue) used to
        // disappear against the popover's light background.
        dot.layer?.backgroundColor = r.color.withAlphaComponent(1).cgColor
        dot.layer?.cornerRadius = 4.5
        dot.layer?.borderWidth = 0.5
        dot.layer?.borderColor = NSColor(white: 0.45, alpha: 0.45).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 9),
            dot.heightAnchor.constraint(equalToConstant: 9),
        ])

        let box = NSButton(checkboxWithTitle: r.title, target: self, action: #selector(toggled(_:)))
        box.font = .systemFont(ofSize: 12.5)
        box.state = selected.contains(r.title) ? .on : .off
        box.lineBreakMode = .byTruncatingTail
        box.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        box.toolTip = r.title
        checkboxes[r.title] = box

        let h = NSStackView(views: [dot, box])
        h.orientation = .horizontal
        h.spacing = 7
        h.alignment = .centerY
        return h
    }

    private func linkButton(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.font = .systemFont(ofSize: 12, weight: .medium)
        b.contentTintColor = .controlAccentColor
        return b
    }

    // MARK: - Actions

    @objc private func toggled(_ sender: NSButton) {
        guard let title = checkboxes.first(where: { $0.value === sender })?.key else { return }
        if sender.state == .on { selected.insert(title) } else { selected.remove(title) }
        onChange(selected)
    }

    @objc private func pickAll() { set(Set(checkboxes.keys)) }
    @objc private func pickMine() { set(mine) }
    @objc private func pickNone() { set([]) }

    private func set(_ titles: Set<String>) {
        selected = titles
        for (t, b) in checkboxes { b.state = titles.contains(t) ? .on : .off }
        onChange(selected)
    }
}
