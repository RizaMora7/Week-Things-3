import AppKit

enum ThemeMode: Int, CaseIterable {
    case auto = 0, light = 1, dark = 2
    var label: String {
        switch self {
        case .auto: return L.s("theme.auto")
        case .light: return L.s("theme.light")
        case .dark: return L.s("theme.dark")
        }
    }
}

struct Palette {
    let windowBG: NSColor
    let columnBG: NSColor
    let columnHeader: NSColor
    let cardBG: NSColor
    let cardBGHover: NSColor
    let cardBorder: NSColor
    let title: NSColor
    let meta: NSColor
    let deadline: NSColor
    let scheduled: NSColor
    let recurring: NSColor
    let todayAccent: NSColor
    let warn: NSColor
    let separator: NSColor
    let badgeText: NSColor

    /// Fondo y borde de un cuadrante de la matriz de Eisenhower.
    func quadrantTint(_ q: Quadrant) -> (bg: NSColor, edge: NSColor) {
        let edge: NSColor
        switch q {
        case .q1: edge = deadline            // hazlo ahora
        case .q2: edge = todayAccent         // agenda
        case .q3: edge = warn                // delega
        case .q4: edge = meta                // suéltalo
        }
        return (edge.withAlphaComponent(dark ? 0.20 : 0.12), edge.withAlphaComponent(dark ? 0.55 : 0.45))
    }

    let dark: Bool

    static func resolve(_ mode: ThemeMode, hour: Int = Calendar.current.component(.hour, from: Date())) -> Bool {
        switch mode {
        case .light: return false
        case .dark: return true
        case .auto: return hour >= 19 || hour < 7      // 19:00–06:59 nocturno
        }
    }

    static func current(dark: Bool) -> Palette {
        if dark {
            return Palette(
                windowBG: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1),
                columnBG: NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.18, alpha: 1),
                columnHeader: NSColor(calibratedWhite: 0.86, alpha: 1),
                cardBG: NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.24, alpha: 1),
                cardBGHover: NSColor(calibratedRed: 0.24, green: 0.26, blue: 0.30, alpha: 1),
                cardBorder: NSColor(calibratedWhite: 1, alpha: 0.07),
                title: NSColor(calibratedWhite: 0.94, alpha: 1),
                meta: NSColor(calibratedWhite: 0.62, alpha: 1),
                deadline: NSColor(calibratedRed: 0.98, green: 0.42, blue: 0.38, alpha: 1),
                scheduled: NSColor(calibratedRed: 0.36, green: 0.66, blue: 0.98, alpha: 1),
                recurring: NSColor(calibratedRed: 0.62, green: 0.52, blue: 0.95, alpha: 1),
                todayAccent: NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.55, alpha: 1),
                warn: NSColor(calibratedRed: 0.96, green: 0.65, blue: 0.22, alpha: 1),
                separator: NSColor(calibratedWhite: 1, alpha: 0.10),
                badgeText: NSColor(calibratedWhite: 0.80, alpha: 1),
                dark: true
            )
        }
        return Palette(
            windowBG: NSColor(calibratedRed: 0.96, green: 0.965, blue: 0.975, alpha: 1),
            columnBG: NSColor(calibratedWhite: 1, alpha: 0.66),
            columnHeader: NSColor(calibratedWhite: 0.25, alpha: 1),
            cardBG: NSColor(calibratedWhite: 1, alpha: 0.97),
            cardBGHover: NSColor(calibratedRed: 0.95, green: 0.97, blue: 1.0, alpha: 1),
            cardBorder: NSColor(calibratedWhite: 0.80, alpha: 1),
            title: NSColor(calibratedWhite: 0.13, alpha: 1),
            meta: NSColor(calibratedWhite: 0.42, alpha: 1),
            deadline: NSColor(calibratedRed: 0.85, green: 0.24, blue: 0.20, alpha: 1),
            scheduled: NSColor(calibratedRed: 0.11, green: 0.44, blue: 0.85, alpha: 1),
            recurring: NSColor(calibratedRed: 0.45, green: 0.33, blue: 0.82, alpha: 1),
            todayAccent: NSColor(calibratedRed: 0.05, green: 0.60, blue: 0.40, alpha: 1),
            warn: NSColor(calibratedRed: 0.80, green: 0.50, blue: 0.05, alpha: 1),
            separator: NSColor(calibratedWhite: 0.80, alpha: 1),
            badgeText: NSColor(calibratedWhite: 0.45, alpha: 1),
            dark: false
        )
    }
}

/// Preferencias persistentes (UserDefaults estándar, sin almacenamiento del navegador).
final class Prefs {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    private enum Key {
        static let weekOffset = "weekOffset"
        static let theme = "themeMode"
        static let refresh = "refreshSeconds"
        static let search = "searchText"
        static let filter = "filterMode"
        static let undated = "showUndated"
        static let density = "compactCards"
        static let launched = "hasLaunchedBefore"
        static let viewMode = "viewMode"
        static let framework = "planFramework"
        static let dayOffset = "dayOffset"
        static let calendars = "enabledCalendars"
        static let language = "uiLanguage"
        static let trayScope = "undatedScope"
    }

    var weekOffset: Int { get { d.integer(forKey: Key.weekOffset) } set { d.set(newValue, forKey: Key.weekOffset) } }
    var themeMode: ThemeMode {
        get { ThemeMode(rawValue: d.object(forKey: Key.theme) as? Int ?? 0) ?? .auto }
        set { d.set(newValue.rawValue, forKey: Key.theme) }
    }
    var refreshSeconds: Int {
        get { let v = d.integer(forKey: Key.refresh); return v == 0 ? 120 : v }
        set { d.set(newValue, forKey: Key.refresh) }
    }
    var searchText: String {
        get { d.string(forKey: Key.search) ?? "" }
        set { d.set(newValue, forKey: Key.search) }
    }
    var filterMode: BoardFilter {
        get { BoardFilter(rawValue: d.integer(forKey: Key.filter)) ?? .all }
        set { d.set(newValue.rawValue, forKey: Key.filter) }
    }
    var showUndated: Bool {
        get { d.object(forKey: Key.undated) == nil ? true : d.bool(forKey: Key.undated) }
        set { d.set(newValue, forKey: Key.undated) }
    }
    var compactCards: Bool { get { d.bool(forKey: Key.density) } set { d.set(newValue, forKey: Key.density) } }
    var hasLaunchedBefore: Bool { get { d.bool(forKey: Key.launched) } set { d.set(newValue, forKey: Key.launched) } }

    /// 0 = tablero semanal · 1 = plan diario
    var viewMode: Int { get { d.integer(forKey: Key.viewMode) } set { d.set(newValue, forKey: Key.viewMode) } }
    var framework: PlanFramework {
        get { PlanFramework(rawValue: d.object(forKey: Key.framework) as? Int ?? 0) ?? .eisenhower }
        set { d.set(newValue.rawValue, forKey: Key.framework) }
    }
    /// Días respecto a hoy en la vista diaria
    var dayOffset: Int { get { d.integer(forKey: Key.dayOffset) } set { d.set(newValue, forKey: Key.dayOffset) } }
    /// Títulos de calendarios activos. Por título y no por rowid: los rowid de
    /// cuentas iCloud/Google pueden reordenarse tras una resincronización.
    var enabledCalendars: [String]? {
        get { d.array(forKey: Key.calendars) as? [String] }
        set { d.set(newValue, forKey: Key.calendars) }
    }
    /// Idioma de la interfaz. Se resuelve al arrancar.
    var language: Lang {
        get { Lang(rawValue: d.object(forKey: Key.language) as? Int ?? 0) ?? .system }
        set { d.set(newValue.rawValue, forKey: Key.language) }
    }
    /// Qué muestra la bandeja de sin fecha.
    var trayScope: TrayScope {
        get { TrayScope(rawValue: d.object(forKey: Key.trayScope) as? Int ?? 0) ?? .week }
        set { d.set(newValue.rawValue, forKey: Key.trayScope) }
    }
}

/// Alcance de la bandeja «sin fecha».
enum TrayScope: Int, CaseIterable {
    case week = 0, inbox = 1, all = 2

    var label: String {
        switch self {
        case .week: return L.s("tray.scope.week")
        case .inbox: return L.s("tray.scope.inbox")
        case .all: return L.s("tray.scope.all")
        }
    }
}

enum BoardFilter: Int, CaseIterable {
    case all = 0, datedOnly = 1, deadlinesOnly = 2, projectsOnly = 3

    var label: String {
        switch self {
        case .all: return L.s("filter.all")
        case .datedOnly: return L.s("filter.dated")
        case .deadlinesOnly: return L.s("filter.deadlines")
        case .projectsOnly: return L.s("filter.projects")
        }
    }
}
