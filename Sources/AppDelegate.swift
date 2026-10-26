import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: BoardController?
    private var loginMenuItem: NSMenuItem?

    /// ítem + clave para re-titular todo cuando cambia el idioma sin rehacer el menú
    /// (rehacerlo desde una acción de menú mientras el menú está abierto es inestable).
    private var titledItems: [(NSMenuItem, String)] = []
    private var submenuTitles: [(NSMenu, String)] = []
    private var themeItems: [NSMenuItem] = []
    private var filterItems: [NSMenuItem] = []
    private var langItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let c = BoardController()
        controller = c
        c.menuRebuilder = { [weak self] in self?.refreshTitles() }
        buildMenu()
        c.start()
        NSApp.activate(ignoringOtherApps: true)

        if !Prefs.shared.hasLaunchedBefore {
            Prefs.shared.hasLaunchedBefore = true
            showFirstRunHelp()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showMainWindow()
        return true
    }

    // MARK: - Menú principal

    private func buildMenu() {
        let mainMenu = NSMenu()
        titledItems.removeAll()
        submenuTitles.removeAll()

        // Aplicación
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        let about = addItem(appMenu, "menu.about", #selector(showAbout))
        about.target = self
        appMenu.addItem(.separator())
        let login = addItem(appMenu, "menu.login", #selector(toggleLogin))
        login.target = self
        if #available(macOS 13.0, *) { login.state = SMAppService.mainApp.status == .enabled ? .on : .off }
        loginMenuItem = login
        appMenu.addItem(.separator())
        addItem(appMenu, "menu.hide", #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = addItem(appMenu, "menu.hideOthers", #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        addItem(appMenu, "menu.quit", #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Semana
        let weekItem = NSMenuItem()
        mainMenu.addItem(weekItem)
        let weekMenu = NSMenu()
        submenuTitles.append((weekMenu, "menu.week"))
        weekItem.submenu = weekMenu
        addItem(weekMenu, "menu.prevWeek", #selector(BoardController.prevWeekAction), keyEquivalent: "←").target = controller
        addItem(weekMenu, "menu.nextWeek", #selector(BoardController.nextWeekAction), keyEquivalent: "→").target = controller
        addItem(weekMenu, "menu.today", #selector(BoardController.todayAction), keyEquivalent: "t").target = controller
        weekMenu.addItem(.separator())
        addItem(weekMenu, "menu.reload", #selector(BoardController.reloadNow), keyEquivalent: "r").target = controller
        weekMenu.addItem(.separator())
        addItem(weekMenu, "menu.calendars", #selector(BoardController.showCalendarMenu)).target = controller

        // Vista
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu()
        submenuTitles.append((viewMenu, "menu.view"))
        viewItem.submenu = viewMenu
        themeItems = []
        for (i, mode) in ThemeMode.allCases.enumerated() {
            let it = NSMenuItem(title: L.f("menu.theme", mode.label), action: #selector(setTheme(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = (Prefs.shared.themeMode == mode) ? .on : .off
            viewMenu.addItem(it)
            themeItems.append(it)
        }
        filterItems = []
        for (i, f) in BoardFilter.allCases.enumerated() {
            let it = NSMenuItem(title: L.f("menu.filter", f.label), action: #selector(setFilter(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = (Prefs.shared.filterMode == f) ? .on : .off
            viewMenu.addItem(it)
            filterItems.append(it)
        }
        viewMenu.addItem(.separator())
        let langMenu = NSMenu()
        submenuTitles.append((langMenu, "menu.language"))
        let langItem = addItem(viewMenu, "menu.language", nil)
        langItem.submenu = langMenu
        langItems = []
        for (i, lang) in Lang.allCases.enumerated() {
            let it = NSMenuItem(title: lang.label, action: #selector(setLanguage(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = (Prefs.shared.language == lang) ? .on : .off
            langMenu.addItem(it)
            langItems.append(it)
        }

        // Edición (necesario para escribir en el buscador y para ⌘C del menú contextual)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu()
        submenuTitles.append((editMenu, "menu.edit"))
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: L.s("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L.s("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L.s("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L.s("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Ventana
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu()
        submenuTitles.append((windowMenu, "menu.window"))
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: L.s("menu.minimize"), action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L.s("menu.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
        refreshTitles()
    }

    /// Crea un ítem con título traducido y lo queda registrado para re-titularlo.
    @discardableResult
    private func addItem(_ menu: NSMenu, _ key: String, _ action: Selector?, keyEquivalent: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: L.s(key), action: action, keyEquivalent: keyEquivalent)
        menu.addItem(it)
        track(it, key)
        return it
    }

    private func track(_ item: NSMenuItem, _ key: String) {
        titledItems.append((item, key))
    }

    /// Re-titula el menú en el idioma activo. Se llama también al cambiar de idioma.
    func refreshTitles() {
        for (item, key) in titledItems { item.title = L.s(key) }
        for (menu, key) in submenuTitles { menu.title = L.s(key) }
        for (i, mode) in ThemeMode.allCases.enumerated() where i < themeItems.count {
            themeItems[i].title = L.f("menu.theme", mode.label)
            themeItems[i].state = (Prefs.shared.themeMode == mode) ? .on : .off
        }
        for (i, f) in BoardFilter.allCases.enumerated() where i < filterItems.count {
            filterItems[i].title = L.f("menu.filter", f.label)
            filterItems[i].state = (Prefs.shared.filterMode == f) ? .on : .off
        }
        for (i, lang) in Lang.allCases.enumerated() where i < langItems.count {
            langItems[i].title = lang.label
            langItems[i].state = (Prefs.shared.language == lang) ? .on : .off
        }
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Semana",
            .credits: NSAttributedString(string: L.s("about.credits"),
                                         attributes: [.font: NSFont.systemFont(ofSize: 11)]),
        ])
    }

    @objc private func toggleLogin() {
        guard #available(macOS 13.0, *) else { return }
        let on = loginMenuItem?.state != .on
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginMenuItem?.state = on ? .on : .off
        } catch {
            let a = NSAlert()
            a.messageText = L.s("alert.loginFail")
            a.informativeText = L.f("alert.loginBody", error.localizedDescription)
            a.alertStyle = .warning
            a.runModal()
        }
    }

    @objc private func setTheme(_ sender: NSMenuItem) {
        guard let mode = ThemeMode(rawValue: sender.tag) else { return }
        controller?.applyThemeMode(mode)
        refreshTitles()
    }

    @objc private func setFilter(_ sender: NSMenuItem) {
        guard let f = BoardFilter(rawValue: sender.tag) else { return }
        controller?.applyFilter(f)
        refreshTitles()
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let lang = Lang(rawValue: sender.tag) else { return }
        controller?.applyLanguage(lang)
    }

    private func showFirstRunHelp() {
        let a = NSAlert()
        a.messageText = L.s("alert.fda.title")
        a.informativeText = L.s("alert.fda.body")
        a.addButton(withTitle: L.s("alert.ok"))
        a.runModal()
    }
}
