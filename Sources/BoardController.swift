import AppKit
import ServiceManagement

final class BoardController: NSObject, NSWindowDelegate {
    private let store = ThingsStore()
    private let window: NSWindow
    private var board = Board()

    // Estado recordado
    private var weekOffset: Int
    private var filter: BoardFilter
    private var theme: ThemeMode
    private var showUndated: Bool
    private var search: String
    private var mode: Int                 // 0 semanal · 1 diaria
    private var dayOffset: Int
    private var framework: PlanFramework
    private var trayScope: TrayScope
    private var calendars: [CalSource] = []
    private var events: [CalEvent] = []

    // Vistas
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let columnsBar = NSView()
    private let columnsScroll = NSScrollView()
    private let dayPlanView = DayPlanView(frame: .zero)
    private let undatedHeader = NSButton()
    private let tray = UndatedTrayView()
    private let trayBar = NSStackView()
    private let trayScopePop = NSPopUpButton(frame: .zero, pullsDown: false)
    private let searchField = NSSearchField()
    private let filterPop = NSPopUpButton(frame: .zero, pullsDown: false)
    private let themePop = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshPop = NSPopUpButton(frame: .zero, pullsDown: false)
    private let frameworkPop = NSPopUpButton(frame: .zero, pullsDown: false)
    let modePop = NSPopUpButton(frame: .zero, pullsDown: false)
    private let calendarsButton = NSButton(title: "", target: nil, action: nil)
    private var reloadButton: NSButton?
    private var columns: [WeekColumnView] = []
    private var undatedHeightConstraint: NSLayoutConstraint!
    private var trayHeaderHeightConstraint: NSLayoutConstraint!
    private var lastModification: Date?

    private var timer: Timer?
    private let calendar = Calendar.current

    override init() {
        let p = Prefs.shared
        L.apply(p.language)                 // antes de formatear cualquier fecha
        self.weekOffset = p.weekOffset
        self.filter = p.filterMode
        self.theme = p.themeMode
        self.showUndated = p.showUndated
        self.search = p.searchText
        self.mode = p.viewMode
        self.dayOffset = p.dayOffset
        self.framework = p.framework
        self.trayScope = p.trayScope

        // `--day` / `--week` en la línea de órdenes: arrancar en una vista concreta sin
        // tocar la preferencia guardada (la usa Tools/demo.sh).
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--day") { self.mode = 1 }
        else if args.contains("--week") { self.mode = 0 }

        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1240, height: 720)
        let rect = NSRect(x: 0, y: 0,
                          width: min(1240, visible.width - 60),
                          height: min(760, visible.height - 60))
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()

        window.title = L.s("win.week")
        window.titleVisibility = .visible
        window.tabbingMode = .disallowed
        window.isRestorable = false      // la restauración de macOS revive marcos de otra configuración de monitores
        discardUnusableSavedFrame()
        window.setFrameAutosaveName("ThingsWeekMain")
        window.delegate = self
        window.minSize = NSSize(width: 900, height: 480)
        window.contentMinSize = NSSize(width: 900, height: 480)

        buildUI()
        applyTheme()
    }

    /// Un marco autosave venido de un monitor ya desconectado puede dejar la ventana
    /// más grande que cualquier pantalla: entonces se descarta y arranca centrada.
    private func discardUnusableSavedFrame() {
        let key = "NSWindow Frame ThingsWeekMain"
        guard let saved = UserDefaults.standard.string(forKey: key) else { return }
        let nums = saved.split(separator: " ").compactMap { Double($0) }
        guard nums.count >= 4 else { return }
        let w = nums[2], h = nums[3]
        let fits = NSScreen.screens.contains { w <= $0.frame.width && h <= $0.frame.height }
        if !fits {
            UserDefaults.standard.removeObject(forKey: key)
            if ProcessInfo.processInfo.environment["SEMANA_DEBUG"] != nil {
                FileHandle.standardError.write("clamp: marco guardado descartado (\(saved))\n".data(using: .utf8)!)
            }
        }
    }

    // MARK: - Montaje de interfaz

    private func buildUI() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1240, height: 720))
        root.wantsLayer = true
        window.contentView = root

        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(bar)

        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.stringValue = L.s("bar.loading")
        let weekGroup = NSStackView(views: [
            makeButton("◀", action: #selector(stepBack), tip: L.s("tip.prev")),
            makeButton(L.s("bar.today"), action: #selector(stepToday), tip: L.s("tip.today")),
            makeButton("▶", action: #selector(stepForward), tip: L.s("tip.next")),
            titleLabel,
        ])
        weekGroup.orientation = .horizontal
        weekGroup.spacing = 8

        filterPop.addItems(withTitles: BoardFilter.allCases.map { $0.label })
        filterPop.selectItem(at: filter.rawValue)
        filterPop.target = self
        filterPop.action = #selector(filterChanged)
        filterPop.toolTip = L.s("tip.filter")

        themePop.addItems(withTitles: ThemeMode.allCases.map { $0.label })
        themePop.selectItem(at: theme.rawValue)
        themePop.target = self
        themePop.action = #selector(themeChanged)
        themePop.toolTip = L.s("tip.theme")

        refreshPop.addItems(withTitles: [L.s("refresh.off"), L.s("refresh.30"), L.s("refresh.2m"),
                                         L.s("refresh.5m"), L.s("refresh.15m")])
        refreshPop.selectItem(at: indexForRefresh(Prefs.shared.refreshSeconds))
        refreshPop.target = self
        refreshPop.action = #selector(refreshChanged)
        refreshPop.toolTip = L.s("tip.refresh")

        modePop.addItems(withTitles: [L.s("bar.week"), L.s("bar.day")])
        modePop.selectItem(at: mode)
        modePop.target = self
        modePop.action = #selector(modeChanged)
        modePop.toolTip = L.s("tip.mode")

        frameworkPop.addItems(withTitles: PlanFramework.allCases.map { $0.shortLabel })
        frameworkPop.selectItem(at: framework.rawValue)
        frameworkPop.target = self
        frameworkPop.action = #selector(frameworkChanged)
        frameworkPop.toolTip = L.s("tip.framework")

        calendarsButton.bezelStyle = .rounded
        calendarsButton.font = NSFont.systemFont(ofSize: 11.5)
        calendarsButton.target = self
        calendarsButton.action = #selector(showCalendarMenu)
        calendarsButton.title = L.s("bar.calendars")
        calendarsButton.toolTip = L.s("tip.calendars")

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = L.s("bar.search")
        searchField.stringValue = search
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        let searchWidth = searchField.widthAnchor.constraint(equalToConstant: 250)
        // 200: por debajo de la resistencia de los desplegables (300) para que se encoja
        // el buscador antes que truncarse "Semana"/"Claro", y por debajo de 250 para que
        // el mínimo de la ventana no lo tome como demanda dura.
        searchWidth.priority = .init(200)
        searchWidth.isActive = true

        let reload = makeButton(L.s("bar.reload"), action: #selector(reloadNow), tip: L.s("tip.reload"))
        reloadButton = reload

        let right = NSStackView(views: [searchField, modePop, frameworkPop, filterPop,
                                        themePop, refreshPop, calendarsButton, reload])
        right.orientation = .horizontal
        right.spacing = 10

        bar.addSubview(weekGroup)
        bar.addSubview(right)
        weekGroup.translatesAutoresizingMaskIntoConstraints = false
        right.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 50),
            weekGroup.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            weekGroup.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            right.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            // Con ventanas estrechas, que el título se acorte: nada de montarse sobre el buscador.
            right.leadingAnchor.constraint(greaterThanOrEqualTo: weekGroup.trailingAnchor, constant: 12),
        ])
        titleLabel.lineBreakMode = .byTruncatingTail
        // Orden en que cede la barra cuando no cabe: primero la fecha (150, que ya está
        // escrita en el título de la ventana), después el buscador (200) y al final los
        // desplegables y botones (300), que tienen que seguir siendo legibles.
        titleLabel.setContentCompressionResistancePriority(.init(150), for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true

        // La barra era el suelo de ancho real de la ventana: seis desplegables y dos
        // botones con resistencia 750 sumaban ~1332 pt por su ancho intrínseco. 240 es el
        // número justo: sigue por encima del buscador (200) y de la fecha (150), así que
        // son lo último que cede, pero queda debajo de 250, el umbral a partir del cual
        // AppKit trata la restricción como demanda dura al calcular el mínimo de la ventana.
        for v in [modePop, frameworkPop, filterPop, themePop, refreshPop,
                  calendarsButton, reload] as [NSView] {
            v.setContentCompressionResistancePriority(.init(240), for: .horizontal)
            v.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            v.widthAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
        }
        searchField.setContentCompressionResistancePriority(.init(200), for: .horizontal)

        // Las ocho columnas van dentro de un scroll horizontal: si no, su ancho suma
        // (8 × 220 + separación) se convierte en el ancho mínimo de la ventana y ya no se
        // puede achicar. El documento es *al menos* tan ancho como el viewport (para no
        // dejar hueco a la derecha) y puede ser más (para desplazarse).
        columnsScroll.hasHorizontalScroller = true
        columnsScroll.hasVerticalScroller = false
        columnsScroll.autohidesScrollers = true
        columnsScroll.scrollerStyle = .overlay
        columnsScroll.drawsBackground = false
        columnsScroll.backgroundColor = .clear
        columnsScroll.translatesAutoresizingMaskIntoConstraints = false
        columnsBar.translatesAutoresizingMaskIntoConstraints = false
        columnsScroll.documentView = columnsBar
        root.addSubview(columnsScroll)
        NSLayoutConstraint.activate([
            columnsScroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 2),
            columnsScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            columnsScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            columnsBar.leadingAnchor.constraint(equalTo: columnsScroll.contentView.leadingAnchor),
            columnsBar.topAnchor.constraint(equalTo: columnsScroll.contentView.topAnchor),
            columnsBar.bottomAnchor.constraint(equalTo: columnsScroll.contentView.bottomAnchor),
        ])
        let fillWidth = columnsBar.widthAnchor.constraint(greaterThanOrEqualTo: columnsScroll.contentView.widthAnchor)
        fillWidth.priority = .defaultHigh        // cede ante el techo de 220 pt por columna
        fillWidth.isActive = true

        // El plan diario ocupa la misma región que las columnas: se alternan con isHidden.
        dayPlanView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(dayPlanView)
        NSLayoutConstraint.activate([
            dayPlanView.topAnchor.constraint(equalTo: columnsScroll.topAnchor),
            dayPlanView.bottomAnchor.constraint(equalTo: columnsScroll.bottomAnchor),
            dayPlanView.leadingAnchor.constraint(equalTo: columnsScroll.leadingAnchor),
            dayPlanView.trailingAnchor.constraint(equalTo: columnsScroll.trailingAnchor),
        ])
        dayPlanView.onSelect = { [weak self] in self?.openInThings($0) }
        dayPlanView.onMenu = { [weak self] in self?.menu(for: $0) }
        columnsScroll.isHidden = mode == 1
        dayPlanView.isHidden = mode == 0
        frameworkPop.isHidden = mode == 0

        // Cabecera de la bandeja: desplegar/plegar + alcance. Una sola pila para
        // poder colapsarla con una única restricción de altura.
        undatedHeader.isBordered = false
        undatedHeader.bezelStyle = .inline
        undatedHeader.title = "▾ " + L.s("tray.undated")
        undatedHeader.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        undatedHeader.target = self
        undatedHeader.action = #selector(toggleUndated)
        undatedHeader.contentTintColor = .secondaryLabelColor
        undatedHeader.lineBreakMode = .byTruncatingTail
        undatedHeader.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        trayScopePop.addItems(withTitles: TrayScope.allCases.map { $0.label })
        trayScopePop.selectItem(at: trayScope.rawValue)
        trayScopePop.target = self
        trayScopePop.action = #selector(trayScopeChanged)
        trayScopePop.controlSize = .small
        trayScopePop.font = NSFont.systemFont(ofSize: 10.5)
        trayScopePop.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        trayBar.orientation = .horizontal
        trayBar.spacing = 6
        trayBar.translatesAutoresizingMaskIntoConstraints = false
        [undatedHeader, trayScopePop, NSView()].forEach { trayBar.addArrangedSubview($0) }
        root.addSubview(trayBar)

        tray.translatesAutoresizingMaskIntoConstraints = false
        tray.onSelect = { [weak self] in self?.openInThings($0) }
        tray.onMenu = { [weak self] in self?.menu(for: $0) }
        root.addSubview(tray)

        NSLayoutConstraint.activate([
            trayBar.topAnchor.constraint(equalTo: columnsScroll.bottomAnchor, constant: 8),
            trayBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            trayBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            tray.topAnchor.constraint(equalTo: trayBar.bottomAnchor, constant: 2),
            tray.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            tray.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            tray.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
        ])
        undatedHeightConstraint = tray.heightAnchor.constraint(equalToConstant: showUndated ? 200 : 0)
        undatedHeightConstraint.isActive = true
        trayHeaderHeightConstraint = trayBar.heightAnchor.constraint(equalToConstant: 22)
        trayHeaderHeightConstraint.isActive = true

        statusLabel.font = NSFont.systemFont(ofSize: 10.5)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingMiddle
        // Es texto informativo: que se acorte, no que obligue a abrir la ventana.
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -7),
        ])

        rebuildColumns()
        scheduleTimer()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.modifierFlags.contains(.command) {
                switch event.keyCode {
                case 123: self.prevWeek(); return nil
                case 124: self.nextWeek(); return nil
                case 15:  self.reloadNow(); return nil
                default: break
                }
            }
            return event
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWoke),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func makeButton(_ title: String, action: Selector, tip: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.toolTip = tip
        b.font = NSFont.systemFont(ofSize: 11.5)
        return b
    }

    private func indexForRefresh(_ s: Int) -> Int {
        switch s { case 0: return 0; case 30: return 1; case 120: return 2; case 300: return 3; default: return 4 }
    }
    private func secondsForIndex(_ i: Int) -> Int { [0, 30, 120, 300, 900][max(0, min(4, i))] }

    private func rebuildColumns() {
        columns.forEach { $0.removeFromSuperview() }
        columns = []
        let overdue = WeekColumnView(day: nil, title: L.s("col.overdue"))
        columns.append(overdue)
        for d in 0..<7 {
            let date = WeekRangeHelper.addDays(d, to: weekStart)
            columns.append(WeekColumnView(day: date, title: DateFormat.header(date)))
        }
        for c in columns {
            c.translatesAutoresizingMaskIntoConstraints = false
            c.onSelect = { [weak self] in self?.openInThings($0) }
            c.onMenu = { [weak self] in self?.menu(for: $0) }
            columnsBar.addSubview(c)
        }
        var constraints: [NSLayoutConstraint] = []
        for (idx, c) in columns.enumerated() {
            constraints.append(c.topAnchor.constraint(equalTo: columnsBar.topAnchor))
            constraints.append(c.bottomAnchor.constraint(equalTo: columnsBar.bottomAnchor))
            if idx == 0 {
                constraints.append(c.leadingAnchor.constraint(equalTo: columnsBar.leadingAnchor))
            } else {
                constraints.append(c.leadingAnchor.constraint(equalTo: columns[idx - 1].trailingAnchor, constant: 8))
                constraints.append(c.widthAnchor.constraint(equalTo: columns[0].widthAnchor))
            }
            if idx == columns.count - 1 {
                constraints.append(c.trailingAnchor.constraint(equalTo: columnsBar.trailingAnchor))
            }
        }
        NSLayoutConstraint.activate(constraints)
        // Las columnas se reparten el ancho visible (prioridad 800, por encima del deseo
        // de 750 de sus etiquetas) y solo tienen un piso duro de 104 pt. Si la ventana
        // baja de ahí, el documento queda más ancho que el viewport y aparece el scroll
        // horizontal. Ya no hace falta techo: dentro del scroller las columnas no pueden
        // estirar la ventana.
        columns[0].widthAnchor.constraint(greaterThanOrEqualToConstant: 104).isActive = true
        let share = columns[0].widthAnchor.constraint(equalTo: columnsScroll.contentView.widthAnchor,
                                                      multiplier: 1.0 / 8.0, constant: -7)
        share.priority = .init(800)
        share.isActive = true
    }

    // MARK: - Datos

    var weekStart: Date {
        let base = WeekRangeHelper.mondayOfWeek(containing: Date(), calendar: calendar)
        return WeekRangeHelper.addDays(weekOffset * 7, to: base, calendar: calendar)
    }

    func start() {
        window.makeKeyAndOrderFront(nil)
        syncCalendarSelection()
        reloadNow()
        if ProcessInfo.processInfo.environment["SEMANA_DEBUG"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.debugFrames() }
        }
        if ProcessInfo.processInfo.environment["SEMANA_SHRINK"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.debugShrink() }
        }
    }

    private func debugFrames() {
        func p(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
        guard let root = window.contentView else { return }
        p("== frames == contentMinSize=\(window.contentMinSize) rootFit=\(root.fittingSize) rootFrame=\(root.frame)")
        for v in root.subviews {
            p("  \(String(describing: type(of: v))) frame=\(v.frame) fit=\(v.fittingSize) hidden=\(v.isHidden)")
        }
        for (i, c) in columns.enumerated() { p("  col\(i) frame=\(c.frame) fit=\(c.fittingSize)") }
        for s in NSScreen.screens { p("  screen frame=\(s.frame) visible=\(s.visibleFrame)") }
    }

    /// Diagnóstico (SEMANA_SHRINK=<ancho>): pide el ancho desde dentro y reporta el que
    /// realmente quedó. Es la única forma honesta de medir el mínimo que imponen las
    /// restricciones: `fittingSize` y Accessibility devuelven otros números.
    func debugShrink() {
        func p(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
        let want = CGFloat(Int(ProcessInfo.processInfo.environment["SEMANA_SHRINK"] ?? "1000") ?? 1000)
        p("SHRINK pidiendo \(want): antes=\(window.frame.size) min=\(window.minSize) "
          + "resizable=\(window.styleMask.contains(.resizable)) zoomed=\(window.isZoomed) "
          + "collectionBehavior=\(window.collectionBehavior.rawValue)")
        window.setContentSize(NSSize(width: want, height: window.frame.height - 28))
        window.layoutIfNeeded()
        p("SHRINK setContentSize → \(window.frame.size)")
        var f = window.frame
        f.size.width = want
        window.setFrame(f, display: false)
        window.layoutIfNeeded()
        p("SHRINK setFrame         → \(window.frame.size)")
        if let root = window.contentView {
            p("SHRINK root fitting=\(root.fittingSize) frame=\(root.frame.size)")
        }
    }

    @objc private func systemWoke() { reloadNow() }

    @objc func reloadNow() {
        let rowIDs = Set(calendars.filter { $0.enabled }.map { $0.rowID })
        let windowStart = min(weekStart, calendar.startOfDay(for: selectedDay))
            .addingTimeInterval(-21 * 86400)
        let windowEnd = max(WeekRangeHelper.addDays(7, to: weekStart, calendar: calendar),
                            calendar.startOfDay(for: selectedDay)).addingTimeInterval(21 * 86400)

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.store.snapshot()
            let evs = rowIDs.isEmpty ? [] : CalendarStore.events(from: windowStart, to: windowEnd, rowIDs: rowIDs)
            DispatchQueue.main.async {
                self.events = evs
                switch result {
                case .success(let b):
                    self.board = b
                    self.lastModification = self.store.sourceModificationDate()
                    self.render()
                case .failure(let e):
                    self.board = Board()
                    self.render(error: e.localizedDescription)
                }
                if let n = self.store.lastNotice { self.statusLabel.stringValue = "⚠︎ " + n }
            }
        }
    }

    private func filtered(_ items: [TaskItem]) -> [TaskItem] {
        var out = items
        switch filter {
        case .all: break
        case .datedOnly: out = out.filter { $0.hasDate }
        case .deadlinesOnly: out = out.filter { $0.deadline != nil }
        case .projectsOnly: out = out.filter { $0.isProject }
        }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            out = out.filter {
                $0.title.lowercased().contains(q)
                || ($0.project?.lowercased().contains(q) ?? false)
                || ($0.area?.lowercased().contains(q) ?? false)
                || $0.tags.contains { $0.lowercased().contains(q) }
                || $0.notes.lowercased().contains(q)
            }
        }
        return out
    }

    private func sameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }

    private func render(error: String? = nil) {
        let pal = Palette.current(dark: Palette.resolve(theme))
        applyPalette(pal)
        let items = filtered(board.tasks)
        if mode == 1 {
            renderDayPlan(pal, items: items, error: error)
            return
        }
        let end = WeekRangeHelper.addDays(7, to: weekStart, calendar: calendar)
        let today = calendar.startOfDay(for: Date())

        // Columna de atrasadas: todo lo con fecha anterior al lunes mostrado.
        let overdue = items.filter { item in
            guard let p = item.placement else { return false }
            return calendar.startOfDay(for: p) < weekStart
        }
        columns[0].set(items: sorted(overdue), palette: pal,
                       header: weekOffset <= 0 ? L.s("col.overdue") : L.s("col.previous"), dimmed: false)

        for (i, c) in columns.dropFirst().enumerated() {
            let day = WeekRangeHelper.addDays(i, to: weekStart, calendar: calendar)
            let isToday = sameDay(day, today)
            let dayItems = items.filter { item in
                // placement = deadline si existe, si no startDate (ver TaskItem).
                guard let p = item.placement else { return false }
                return sameDay(p, day)
            }
            let dayEvents = events.filter { sameDay(Date(timeIntervalSince1970: Double($0.dayKey)), day) }
            c.set(items: sorted(dayItems), events: dayEvents, palette: pal,
                  header: DateFormat.header(day) + (isToday ? " · " + L.s("day.hoyShort") : ""), dimmed: false)
        }

        // Bandeja sin fecha, con el alcance elegido por el usuario.
        let undatedAll = items.filter { !$0.hasDate }
        let undated = applyTrayScope(undatedAll, weekItems: items)
        tray.set(items: undated, palette: pal)
        undatedHeader.title = "\(showUndated ? "▾" : "▸") \(L.s("tray.undated")) · \(undated.count)" +
            " (\(L.s("start.inbox")) \(board.tasks.filter { $0.start == .inbox && !$0.hasDate }.count) · " +
            "\(L.s("start.anytime")) \(board.tasks.filter { $0.start == .anytime && !$0.hasDate }.count) · " +
            "\(L.s("start.someday")) \(board.tasks.filter { $0.start == .someday && !$0.hasDate }.count))"
        applyTrayLayout()

        let firstDay = weekStart
        let lastDay = WeekRangeHelper.addDays(6, to: weekStart, calendar: calendar)
        titleLabel.stringValue = L.f("title.weekRange",
                                     DateFormat.weekdayAbbr(firstDay), DateFormat.dayNumber.string(from: firstDay) as NSString,
                                     DateFormat.weekdayAbbr(lastDay), DateFormat.dayNumber.string(from: lastDay) as NSString,
                                     DateFormat.monthYear(lastDay))
        let shiftText: String
        switch weekOffset {
        case 0: shiftText = L.s("win.week")
        case 1: shiftText = L.f("win.weekOffset", "+1")
        case -1: shiftText = L.f("win.weekOffset", "−1")
        default: shiftText = L.f("win.weekOffset", "\(weekOffset > 0 ? "+" : "−")\(abs(weekOffset))")
        }
        window.title = shiftText

        if let error {
            statusLabel.stringValue = error
        } else {
            let weekTotal = items.filter { item in
                guard let p = item.placement else { return false }
                let d = calendar.startOfDay(for: p)
                return d >= weekStart && d < end
            }.count
            statusLabel.stringValue = [
                "\(L.s("st.open")) \(board.counts.open)",
                "\(L.s("st.dated")) \(board.counts.dated)",
                "\(L.s("st.overdue")) \(overdue.count)",
                "\(L.s("st.inWeek")) \(weekTotal)",
                "\(L.s("st.undated")) \(undatedAll.count)",
                "\(L.s("st.recurring")) \(board.counts.recurring)",
                "\(L.s("st.projects")) \(board.counts.projects)",
                L.s("st.legend"),
                "\(L.s("st.read")) \(readModeLabel) \(L.s("st.at")) \(DateFormat.time.string(from: board.generatedAt))",
                (board.databasePath as NSString).abbreviatingWithTildeInPath,
            ].joined(separator: "  ·  ")
        }
    }

    /// Cómo se leyó Things, en el idioma activo. `ThingsStore` guarda un token neutro
    /// ("live" / "mirror"), no texto ya traducido.
    private var readModeLabel: String {
        board.readMode == "mirror" ? L.s("mode.mirror") : L.s("mode.live")
    }

    /// Qué deja pasar cada alcance de la bandeja.
    private func applyTrayScope(_ undated: [TaskItem], weekItems: [TaskItem]) -> [TaskItem] {
        switch trayScope {
        case .all:
            return undated
        case .inbox:
            return undated.filter { $0.start == .inbox || $0.start == .anytime }
        case .week:
            // Relevante para la semana mostrada: comparte proyecto o área con lo
            // que ya tiene fecha en ella, o está en la Bandeja de entrada.
            let projects = Set(weekItems.compactMap { $0.project })
            let areas = Set(weekItems.compactMap { $0.area })
            return undated.filter {
                $0.start == .inbox || projects.contains($0.project ?? "") || areas.contains($0.area ?? "")
            }
        }
    }

    /// Ruta del modo diario: pinta el plan del día elegido con el marco activo.
    private func renderDayPlan(_ pal: Palette, items: [TaskItem], error: String?) {
        applyTrayLayout()
        let day = calendar.startOfDay(for: selectedDay)
        let dayEvents = events.filter { sameDay(Date(timeIntervalSince1970: Double($0.dayKey)), day) }
        let plan = Planner.build(framework: framework, day: day, tasks: items,
                                 events: dayEvents, includeOverdue: true)
        dayPlanView.render(plan, palette: pal)

        let name = DateFormat.dayHeading(day)
        titleLabel.stringValue = dayOffset == 0 ? L.f("title.dayHoy", name) : name
        window.title = L.s("win.day")
        statusLabel.stringValue = error ?? L.f("day.status", plan.framework.label,
                                               plan.demandMinutes, plan.capacityMinutes,
                                               dayEvents.count, L.n("u.event", dayEvents.count),
                                               plan.blocks.count, L.n("u.block", plan.blocks.count),
                                               L.s("st.read"), readModeLabel,
                                               DateFormat.time.string(from: board.generatedAt))
    }

    /// `isHidden` no saca una vista del Auto Layout: hay que colapsar también sus
    /// alturas, o la bandeja le sigue robando espacio al plan diario.
    private func applyTrayLayout() {
        let weekly = mode == 0
        trayBar.isHidden = !weekly
        tray.isHidden = !weekly || !showUndated
        undatedHeightConstraint.constant = (weekly && showUndated) ? 200 : 0
        trayHeaderHeightConstraint.constant = weekly ? 22 : 0
    }

    private func sorted(_ items: [TaskItem]) -> [TaskItem] {
        items.sorted { a, b in
            let ad = a.deadline != nil, bd = b.deadline != nil
            if ad != bd { return ad }
            if let ar = a.deadlineRaw, let br = b.deadlineRaw, ar != br { return ar < br }
            let ra = Planner.priorityRank(a), rb = Planner.priorityRank(b)
            if ra != rb { return ra < rb }
            return a.sortIndex < b.sortIndex
        }
    }

    private func applyPalette(_ pal: Palette) {
        window.backgroundColor = pal.windowBG
        window.contentView?.layer?.backgroundColor = pal.windowBG.cgColor
        undatedHeader.contentTintColor = pal.meta
    }

    // MARK: - Acciones

    @objc private func prevWeek() { weekOffset -= 1; Prefs.shared.weekOffset = weekOffset; render() }
    @objc private func nextWeek() { weekOffset += 1; Prefs.shared.weekOffset = weekOffset; render() }
    @objc private func gotoToday() {
        weekOffset = 0; dayOffset = 0
        Prefs.shared.weekOffset = 0; Prefs.shared.dayOffset = 0
        render(); reloadNow()
    }

    @objc private func stepBack() { mode == 1 ? prevDay() : prevWeek() }
    @objc private func stepForward() { mode == 1 ? nextDay() : nextWeek() }
    @objc private func stepToday() { gotoToday() }

    private func prevDay() { dayOffset -= 1; Prefs.shared.dayOffset = dayOffset; render() }
    private func nextDay() { dayOffset += 1; Prefs.shared.dayOffset = dayOffset; render() }

    var selectedDay: Date { WeekRangeHelper.addDays(dayOffset, to: Date(), calendar: calendar) }

    @objc private func modeChanged() {
        mode = modePop.indexOfSelectedItem
        Prefs.shared.viewMode = mode
        columnsScroll.isHidden = mode == 1
        dayPlanView.isHidden = mode == 0
        frameworkPop.isHidden = mode == 0
        render()
    }

    @objc private func frameworkChanged() {
        guard let f = PlanFramework(rawValue: frameworkPop.indexOfSelectedItem) else { return }
        framework = f
        Prefs.shared.framework = f
        render()
    }

    private var calendarPopover: NSPopover?
    private var calendarReload: DispatchWorkItem?

    /// Selector de calendarios (popover que sigue abierto al marcar); se guarda la
    /// selección por título.
    @objc func showCalendarMenu() {
        if let open = calendarPopover, open.isShown { open.performClose(nil); return }
        if calendars.isEmpty { calendars = CalendarStore.availableCalendars() }
        let picker = CalendarPicker(calendars: calendars) { [weak self] titles in
            self?.applySelection(titles: titles)
        }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = picker
        pop.appearance = window.appearance
        calendarPopover = pop
        pop.show(relativeTo: calendarsButton.bounds, of: calendarsButton, preferredEdge: .minY)
    }

    /// Guarda al instante y recarga tras una breve pausa, para no releer las bases en
    /// cada casilla cuando se marcan varias seguidas.
    private func applySelection(titles: Set<String>) {
        for i in calendars.indices { calendars[i].enabled = titles.contains(calendars[i].title) }
        Prefs.shared.enabledCalendars = Array(titles).sorted()
        calendarReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reloadNow() }
        calendarReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func syncCalendarSelection() {
        var src = CalendarStore.availableCalendars()
        if let saved = Prefs.shared.enabledCalendars {
            let set = Set(saved)
            for i in src.indices { src[i].enabled = set.contains(src[i].title) }
        }
        calendars = src
    }

    // Envolventes para el menú principal
    @objc func prevWeekAction() { prevWeek() }
    @objc func nextWeekAction() { nextWeek() }
    @objc func todayAction() { gotoToday() }

    func applyThemeMode(_ mode: ThemeMode) {
        theme = mode
        Prefs.shared.themeMode = mode
        themePop.selectItem(at: mode.rawValue)
        applyTheme()
        render()
    }

    func applyFilter(_ f: BoardFilter) {
        filter = f
        Prefs.shared.filterMode = f
        filterPop.selectItem(at: f.rawValue)
        render()
    }

    @objc private func filterChanged() {
        guard let f = BoardFilter(rawValue: filterPop.indexOfSelectedItem) else { return }
        filter = f; Prefs.shared.filterMode = f; render()
    }

    @objc private func themeChanged() {
        guard let t = ThemeMode(rawValue: themePop.indexOfSelectedItem) else { return }
        theme = t; Prefs.shared.themeMode = t; applyTheme(); render()
    }

    @objc private func refreshChanged() {
        let s = secondsForIndex(refreshPop.indexOfSelectedItem)
        Prefs.shared.refreshSeconds = s
        scheduleTimer()
        if s == 0 { statusLabel.stringValue = L.s("st.refreshOff") }
    }

    @objc private func trayScopeChanged() {
        guard let sc = TrayScope(rawValue: trayScopePop.indexOfSelectedItem) else { return }
        trayScope = sc
        Prefs.shared.trayScope = sc
        render()
    }

    /// La app la instala para que el menú principal se rehaga en el idioma nuevo.
    var menuRebuilder: (() -> Void)?

    /// Cambia el idioma sin reiniciar: se rehacen los textos de la barra, el menú
    /// principal y todo lo que pinta render().
    func applyLanguage(_ lang: Lang) {
        Prefs.shared.language = lang
        L.apply(lang)
        modePop.item(at: 0)?.title = L.s("bar.week")
        modePop.item(at: 1)?.title = L.s("bar.day")
        for (i, f) in BoardFilter.allCases.enumerated() { filterPop.item(at: i)?.title = f.label }
        for (i, t) in ThemeMode.allCases.enumerated() { themePop.item(at: i)?.title = t.label }
        for (i, k) in ["refresh.off", "refresh.30", "refresh.2m", "refresh.5m", "refresh.15m"].enumerated() {
            refreshPop.item(at: i)?.title = L.s(k)
        }
        for (i, f) in PlanFramework.allCases.enumerated() { frameworkPop.item(at: i)?.title = f.shortLabel }
        for (i, sc) in TrayScope.allCases.enumerated() { trayScopePop.item(at: i)?.title = sc.label }
        searchField.placeholderString = L.s("bar.search")
        calendarsButton.title = L.s("bar.calendars")
        calendarsButton.toolTip = L.s("tip.calendars")
        reloadButton?.title = L.s("bar.reload")
        reloadButton?.toolTip = L.s("tip.reload")
        titleLabel.stringValue = L.s("bar.loading")
        if weekGroupButtons.count > 1 { weekGroupButtons[1].title = L.s("bar.today") }
        for (i, tip) in [L.s("tip.prev"), L.s("tip.today"), L.s("tip.next")].enumerated()
        where i < weekGroupButtons.count {
            weekGroupButtons[i].toolTip = tip
        }
        menuRebuilder?()
        rebuildColumns()
        render()
    }

    /// Los tres botones de navegación viven dentro de la pila de la barra.
    private var weekGroupButtons: [NSButton] {
        guard let stack = titleLabel.superview as? NSStackView else { return [] }
        return stack.arrangedSubviews.compactMap { $0 as? NSButton }
    }

    @objc private func searchChanged() {
        search = searchField.stringValue
        Prefs.shared.searchText = search
        render()
    }

    @objc private func toggleUndated() {
        showUndated.toggle()
        Prefs.shared.showUndated = showUndated
        render()
    }

    private func applyTheme() {
        let dark = Palette.resolve(theme)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    private func openInThings(_ item: TaskItem) {
        guard let url = ThingsStore.showURL(uuid: item.id) else { return }
        NSWorkspace.shared.open(url)
    }

    private func completeItem(_ item: TaskItem) {
        // Things rechaza `completed` en repetitivas; el menú ya lo desactiva, esto es la red.
        guard !item.recurring else { return }
        guard let token = board.authToken else {
            let a = NSAlert()
            a.messageText = L.s("alert.token.title")
            a.informativeText = L.s("alert.token.body")
            a.addButton(withTitle: L.s("alert.ok"))
            a.runModal()
            return
        }
        guard let url = ThingsStore.completeURL(item: item, authToken: token) else { return }
        NSWorkspace.shared.open(url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.reloadNow() }
    }

    private var menuTarget: TaskItem?

    func menu(for item: TaskItem) -> NSMenu {
        menuTarget = item
        let m = NSMenu()
        m.addItem(withTitle: L.s("ctx.open"), action: #selector(menuOpen), keyEquivalent: "").target = self
        let complete = m.addItem(withTitle: L.s("ctx.complete"), action: #selector(menuComplete), keyEquivalent: "")
        complete.target = self
        if item.recurring {
            m.autoenablesItems = false
            complete.isEnabled = false
            complete.toolTip = L.s("ctx.completeRecurring")
        }
        m.addItem(.separator())
        m.addItem(withTitle: L.s("ctx.copyTitle"), action: #selector(menuCopyTitle), keyEquivalent: "").target = self
        m.addItem(withTitle: L.s("ctx.copyUUID"), action: #selector(menuCopyUUID), keyEquivalent: "").target = self
        return m
    }

    @objc private func menuOpen() { if let i = menuTarget { openInThings(i) } }
    @objc private func menuComplete() { if let i = menuTarget { completeItem(i) } }
    @objc private func menuCopyTitle() {
        guard let i = menuTarget else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(i.title, forType: .string)
    }
    @objc private func menuCopyUUID() {
        guard let i = menuTarget else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(i.id, forType: .string)
    }

    // MARK: - Refresco programado

    private func scheduleTimer() {
        timer?.invalidate()
        let s = Prefs.shared.refreshSeconds
        guard s > 0 else { timer = nil; return }
        let t = Timer(timeInterval: Double(s), repeats: true) { [weak self] _ in
            guard let self else { return }
            let m = self.store.sourceModificationDate()
            if let m, let last = self.lastModification, m == last { return }
            self.reloadNow()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func showMainWindow() { window.makeKeyAndOrderFront(nil) }
    var mainWindow: NSWindow { window }

    // MARK: - Preferencias de arranque
    // (El arranque automático se gestiona desde el menú de la app con SMAppService.)

    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
}
