import AppKit

/// Tarjeta de una tarea: banda de color a la izquierda, título y metadatos.
final class TaskCard: NSView {
    private(set) var item: TaskItem?
    var onClick: ((TaskItem) -> Void)?
    var onMenu: ((TaskItem) -> NSMenu?)?

    private let accent = CALayer()
    private let titleLabel = TaskCard.makeLabel(size: 12, weight: .medium)
    private let metaLabel = TaskCard.makeLabel(size: 10.5, weight: .regular)
    private var palette = Palette.current(dark: false)
    private let hInset: CGFloat = 11
    private let topInset: CGFloat = 8
    private var lastMeasuredWidth: CGFloat = 0
    private let fallbackTextWidth: CGFloat = 168

    convenience init() { self.init(frame: .zero) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = false
        accent.cornerRadius = 2
        layer?.addSublayer(accent)

        titleLabel.maximumNumberOfLines = 3
        titleLabel.lineBreakMode = .byWordWrapping
        metaLabel.maximumNumberOfLines = 2
        metaLabel.lineBreakMode = .byWordWrapping
        [titleLabel, metaLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: topInset),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hInset),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hInset),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            metaLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hInset),
            metaLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hInset),
            metaLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    private static func makeLabel(size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.cell?.wraps = true
        l.cell?.isScrollable = false
        l.drawsBackground = false
        l.isBezeled = false
        l.isEditable = false
        l.isSelectable = false
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return l
    }

    func configure(_ item: TaskItem, palette: Palette, showNotes: Bool = false) {
        self.item = item
        self.palette = palette
        titleLabel.stringValue = item.title
        metaLabel.stringValue = Self.meta(item)
        titleLabel.textColor = palette.title
        metaLabel.textColor = palette.meta
        layer?.backgroundColor = palette.cardBG.cgColor
        layer?.borderColor = palette.cardBorder.cgColor
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.10).cgColor
        layer?.shadowOpacity = 0.5
        layer?.shadowRadius = 2
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        let color: NSColor
        if item.isProject { color = palette.meta }
        else if item.deadline != nil { color = palette.deadline }
        else if item.recurring { color = palette.recurring }
        else { color = palette.scheduled }
        accent.backgroundColor = color.cgColor
        toolTip = Self.tooltip(for: item, showNotes: showNotes)
        needsLayout = true
    }

    static func meta(_ i: TaskItem) -> String {
        var parts: [String] = []
        if let p = i.project { parts.append(p) }
        else if let a = i.area { parts.append(a) }
        if let h = i.heading, i.project != nil || i.area != nil { parts.append("· \(h)") }
        if i.totalChecklist > 0 {
            let done = i.totalChecklist - i.openChecklist
            parts.append("✓ \(done)/\(i.totalChecklist)")
        }
        if i.recurring { parts.append("↻") }
        if !i.tags.isEmpty { parts.append(i.tags.prefix(3).joined(separator: " ")) }
        return parts.joined(separator: "  ")
    }

    static func tooltip(for i: TaskItem, showNotes: Bool) -> String {
        var s = i.title
        if let d = i.deadline { s += "\nPlazo: \(DateFormat.iso.string(from: d))" }
        if let s2 = i.scheduled { s += "\nProgramada: \(DateFormat.iso.string(from: s2))" }
        s += "\n\(i.start.label)"
        if let p = i.project { s += " · \(p)" }
        if showNotes, !i.notes.isEmpty {
            let trimmed = i.notes.count > 600 ? String(i.notes.prefix(600)) + "…" : i.notes
            s += "\n\n" + trimmed
        }
        return s
    }

    override func layout() {
        super.layout()
        let w = max(20, bounds.width - hInset * 2)
        if abs(w - lastMeasuredWidth) > 0.5 {
            lastMeasuredWidth = w
            titleLabel.preferredMaxLayoutWidth = w
            metaLabel.preferredMaxLayoutWidth = w
            invalidateIntrinsicContentSize()
        }
        accent.frame = CGRect(x: 0, y: 0, width: 3, height: bounds.height)
    }

    override var intrinsicContentSize: NSSize {
        // Antes de la primera pasada de layout no hay ancho real: se usa una reserva
        // y layout() invalida para corregir la altura en cuanto exista.
        let w = lastMeasuredWidth > 0 ? lastMeasuredWidth : fallbackTextWidth
        let th = titleLabel.sizeThatFits(NSSize(width: w, height: 400)).height
        let metaEmpty = metaLabel.stringValue.isEmpty
        let mh = metaEmpty ? 0 : metaLabel.sizeThatFits(NSSize(width: w, height: 120)).height
        let height = ceil(th) + (metaEmpty ? 0 : ceil(mh) + 3) + topInset + 8
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    // MARK: interacción

    override func mouseDown(with event: NSEvent) {
        if let item { onClick?(item) }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let item, let onMenu, let menu = onMenu(item) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = palette.cardBGHover.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = palette.cardBG.cgColor
    }
}

/// Columna del tablero: cabecera fija + lista desplazable de tarjetas.
final class WeekColumnView: NSView {
    let day: Date?
    let titleText: String
    var onSelect: ((TaskItem) -> Void)?
    var onMenu: ((TaskItem) -> NSMenu?)?

    private let headerLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    let stack = NSStackView()
    private let scroll = NSScrollView()
    private let doc = FlipView()
    private var palette = Palette.current(dark: false)
    private var isDimmed = false

    init(day: Date?, title: String) {
        self.day = day
        self.titleText = title
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10

        headerLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        countLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        countLabel.alignment = .right
        // Etiquetas normales traen resistencia 750 a comprimirlas: ocho columnas con
        // ese piso pedían más ancho del que cabe en cualquier pantalla.
        for l in [headerLabel, countLabel] {
            l.lineBreakMode = .byTruncatingTail
            l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 9, bottom: 14, right: 9)
        stack.translatesAutoresizingMaskIntoConstraints = false

        doc.topLeftOrigin = true
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)

        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.autohidesScrollers = true

        [headerLabel, countLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        addSubview(scroll)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            countLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: headerLabel.trailingAnchor, constant: 6),
            scroll.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 5),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
        doc.widthAnchor.constraint(equalTo: scroll.widthAnchor).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    func set(items: [TaskItem], events: [CalEvent] = [], palette: Palette, header: String,
             count: Int? = nil, dimmed: Bool = false) {
        self.palette = palette
        isDimmed = dimmed
        headerLabel.stringValue = header
        let countText = events.isEmpty
            ? String(count ?? items.count)
            : "\(count ?? items.count)·\(events.count)"
        countLabel.stringValue = countText
        headerLabel.textColor = palette.columnHeader
        countLabel.textColor = palette.badgeText
        layer?.backgroundColor = palette.columnBG.withAlphaComponent(dimmed ? 0.45 : 1).cgColor
        layer?.borderColor = palette.separator.cgColor
        layer?.borderWidth = 1

        // Hoy: fondo teñido con el acento, borde del mismo color y cabecera marcada.
        let isToday = day.map { Calendar.current.isDate($0, inSameDayAs: Date()) } ?? false
        if isToday {
            let alpha: CGFloat = dimmed ? 0.06 : (palette.dark ? 0.22 : 0.13)
            layer?.backgroundColor = palette.todayAccent.withAlphaComponent(alpha).cgColor
            layer?.borderColor = palette.todayAccent.cgColor
            layer?.borderWidth = 1.5
            headerLabel.textColor = palette.todayAccent
        }

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for event in events {
            stack.addArrangedSubview(EventRow(event: event, palette: palette))
        }
        for item in items {
            let card = TaskCard()
            card.configure(item, palette: palette, showNotes: true)
            card.onClick = { [weak self] in self?.onSelect?($0) }
            card.onMenu = { [weak self] item in self?.onMenu?(item) }
            stack.addArrangedSubview(card)
            // Después de agregarla: antes no habría ancestro común con la pila.
            card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -18).isActive = true
        }
        if items.isEmpty && events.isEmpty {
            let empty = NSTextField(labelWithString: "—")
            empty.font = NSFont.systemFont(ofSize: 14)
            empty.textColor = palette.meta
            stack.addArrangedSubview(empty)
        }
    }
}

/// Fila compacta de un evento del calendario dentro de la columna semanal.
final class EventRow: NSView {
    init(event: CalEvent, palette: Palette) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = palette.cardBG.withAlphaComponent(0.75).cgColor
        layer?.borderColor = palette.cardBorder.cgColor
        layer?.borderWidth = 1

        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = event.color.cgColor
        bar.layer?.cornerRadius = 2
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        let time = NSTextField(labelWithString: event.timeText)
        time.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        time.textColor = palette.meta
        time.lineBreakMode = .byTruncatingTail
        time.translatesAutoresizingMaskIntoConstraints = false
        addSubview(time)

        let title = NSTextField(labelWithString: event.title)
        title.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        title.textColor = palette.title
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        title.toolTip = "\(event.calendarTitle) · \(event.timeText)"
        addSubview(title)
        // Sin esto, un evento con título largo exigía su ancho intrínseco completo y
        // arrastraba el ancho mínimo de la columna (y de la ventana) cientos de puntos.
        for l in [time, title] {
            l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            bar.widthAnchor.constraint(equalToConstant: 3),
            time.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 6),
            time.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            time.widthAnchor.constraint(lessThanOrEqualToConstant: 96),
            title.leadingAnchor.constraint(equalTo: time.trailingAnchor, constant: 6),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            title.centerYAnchor.constraint(equalTo: time.centerYAnchor),
            time.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
}

/// Bandeja «sin fecha»: rejilla que aprovecha el alto en varias filas.
/// Sustituye a la antigua fila única con scroll horizontal: ese scroller quedaba
/// con una restricción de ancho fija y congelaba el ancho de la ventana.
final class UndatedTrayView: NSView {
    private let scroll = NSScrollView()
    private let doc = FlipView()
    private let grid = NSStackView()
    private var cards: [TaskCard] = []
    private var palette = Palette.current(dark: false)
    private var perRow = 0
    private let cardW: CGFloat = 212
    private let gap: CGFloat = 8
    private let inset: CGFloat = 12

    var onSelect: ((TaskItem) -> Void)?
    var onMenu: ((TaskItem) -> NSMenu?)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10

        grid.orientation = .vertical
        grid.alignment = .leading
        grid.distribution = .fill
        grid.spacing = 8
        grid.edgeInsets = NSEdgeInsets(top: 6, left: inset, bottom: 8, right: inset)
        grid.translatesAutoresizingMaskIntoConstraints = false

        doc.topLeftOrigin = true
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(grid)

        scroll.documentView = doc
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: doc.topAnchor),
            grid.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            // El ancho útil lo fija esta cadena (doc == viewport, fila == doc - 2·inset);
            // lo único que puede ceder es el ancho de cada tarjeta (prioridad 900).
            grid.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    func set(items: [TaskItem], palette: Palette) {
        self.palette = palette
        layer?.backgroundColor = palette.columnBG.cgColor
        layer?.borderColor = palette.separator.cgColor
        layer?.borderWidth = 1
        cards = items.prefix(240).map { item in
            let c = TaskCard()
            c.configure(item, palette: palette, showNotes: true)
            c.onClick = { [weak self] in self?.onSelect?($0) }
            c.onMenu = { [weak self] in self?.onMenu?($0) }
            return c
        }
        perRow = -1                 // fuerza la recomposición en el próximo layout
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let usable = max(cardW, bounds.width - inset * 2)
        let fit = max(1, Int((usable + gap) / (cardW + gap)))
        if fit != perRow { recompose(fit) }
    }

    private func recompose(_ n: Int) {
        perRow = n
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if cards.isEmpty {
            let empty = NSTextField(labelWithString: "—")
            empty.font = NSFont.systemFont(ofSize: 13)
            empty.textColor = palette.meta
            grid.addArrangedSubview(empty)
            return
        }
        var i = 0
        while i < cards.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.distribution = .fill
            row.spacing = gap
            for _ in 0..<n where i < cards.count {
                let card = cards[i]
                row.addArrangedSubview(card)
                // 200, medido: el cálculo del mínimo de la ventana respeta las
                // restricciones de 250 para arriba. Con 900 y con 600 la ventana no bajaba
                // de 1148 pt; con 200 baja hasta el mínimo declarado (900). Como el
                // espaciador huguea a 50, las tarjetas igual mantienen sus 212 pt.
                let w = card.widthAnchor.constraint(equalToConstant: cardW)
                w.priority = .init(200)
                w.isActive = true
                i += 1
            }
            // Espaciador colapsable: absorbe el sobrante para que las tarjetas no se
            // estiren cuando la fila queda corta.
            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(50), for: .horizontal)
            spacer.setContentCompressionResistancePriority(.init(50), for: .horizontal)
            row.addArrangedSubview(spacer)
            grid.addArrangedSubview(row)
            // La fila nunca desborda la rejilla, pero puede ser más angosta: con `==` el
            // ancho de la ventana heredaba la suma de las tarjetas de la fila (5 × 212 pt
            // eran 1148 pt de mínimo) y la ventana no se podía achicar.
            row.widthAnchor.constraint(lessThanOrEqualTo: grid.widthAnchor, constant: -inset * 2).isActive = true
        }
    }
}

/// Vista con origen arriba para que el scroll empiece en la cabecera.
final class FlipView: NSView {
    var topLeftOrigin = false
    override var isFlipped: Bool { topLeftOrigin }
}
