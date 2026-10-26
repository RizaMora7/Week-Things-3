import Foundation

/// Codificación de fechas de Things 3.
///
/// Things NO guarda fechas como epoch: usa un entero con bits empaquetados
/// `YYYYYYYYYYYMMMMDDDDD0000000` (año, mes, día y 7 bits bajos sin usar).
/// Por eso un "día extra" aparece en cada cambio de mes, y cualquier intento
/// de tratar el valor como segundos o días desde 1970 deriva.
///
/// Máscaras verificadas contra la librería `things-py` (la que usa el MCP de
/// Things instalado) y contra 8 fechas leídas desde la propia UI de Things.
enum ThingsDate {
    static let yearMask = 0b111111111110000000000000000
    static let monthMask = 0b000000000001111000000000000
    static let dayMask = 0b000000000000000111110000000

    /// Decodifica un valor de Things a fecha local. `nil` si está ausente o es inválida.
    static func components(from value: Int) -> DateComponents? {
        guard value != 0 else { return nil }
        let year = (value & yearMask) >> 16
        let month = (value & monthMask) >> 12
        let day = (value & dayMask) >> 7
        guard year > 1900, year < 4000, month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 12              // mediodía: inmune a cambios de hora al restar días
        c.calendar = Calendar(identifier: .gregorian)
        return c
    }

    static func date(from value: Int) -> Date? {
        guard let c = components(from: value) else { return nil }
        return c.calendar?.date(from: c)
    }

    /// Diferencia en días calendario entre el valor de Things y una fecha de referencia.
    static func dayOffset(_ value: Int, from reference: Date, calendar: Calendar = .current) -> Int? {
        guard let d = date(from: value) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: reference),
                                       to: calendar.startOfDay(for: d)).day
    }
}

/// Etiqueta corta del bucket de inicio de Things.
enum StartBucket: Int {
    case inbox = 0
    case anytime = 1
    case someday = 2
    case unknown = -1

    init(raw: Int) { self = StartBucket(rawValue: raw) ?? .unknown }

    var label: String {
        switch self {
        case .inbox: return L.s("start.inbox")
        case .anytime: return L.s("start.anytime")
        case .someday: return L.s("start.someday")
        case .unknown: return L.s("start.unknown")
        }
    }
}
