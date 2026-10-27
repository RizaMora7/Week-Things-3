import Foundation

/// Idioma de la interfaz. `system` sigue el idioma del sistema.
enum Lang: Int, CaseIterable {
    case system = 0, spanish = 1, english = 2

    /// `nil` en `.system`: hay que preguntar al sistema.
    var fixedCode: String? {
        switch self {
        case .system: return nil
        case .spanish: return "es"
        case .english: return "en"
        }
    }

    /// "English" se escribe "English" también en español: es el nombre del idioma, no
    /// una traducción.
    var label: String {
        switch self {
        case .system: return L.s("lang.system")
        case .spanish: return L.s("lang.es")
        case .english: return L.s("lang.en")
        }
    }
}

/// Todos los textos que ve el usuario pasan por aquí. `es` es el idioma base del
/// proyecto; `en` se añadió después, así que cada clave vive en la misma fila para
/// que añadir un tercero sea escribir una columna más, no reescribir la app.
enum L {
    /// "es" | "en". Se resuelve al arrancar y al cambiar de idioma.
    static private(set) var code = "es"

    static func apply(_ pref: Lang) {
        if let c = pref.fixedCode {
            code = c
        } else {
            // `Locale.languageCode` está deprecada desde macOS 14, pero el reemplazo
            // (`language.languageCode`) exige SDK 14 y esta app apunta a 13: se queda así.
            let raw = Locale.current.languageCode ?? Locale.current.identifier
            code = raw.hasPrefix("es") ? "es" : "en"
        }
        DateFormat.rebuild()
    }

    static func s(_ key: String) -> String {
        guard let row = table[key] else { return key }
        return code == "en" ? row.1 : row.0
    }

    /// Formato con `%@` / `%d`. Los argumentos salen ya en el idioma activo.
    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), arguments: args)
    }

    static func f(_ key: String, _ args: [CVarArg]) -> String {
        String(format: s(key), arguments: args)
    }

    /// Sustantivo en singular o plural según el conteo. `%@` dentro de las frases.
    static func n(_ key: String, _ count: Int) -> String {
        guard let row = plurals[key] else { return key }
        if code == "en" { return count == 1 ? row.2 : row.3 }
        return count == 1 ? row.0 : row.1
    }

    /// (uno ES, varios ES, uno EN, varios EN)
    private static let plurals: [String: (String, String, String, String)] = [
        "u.event":   ("evento", "eventos", "event", "events"),
        "u.block":   ("bloque", "bloques", "block", "blocks"),
        "u.task":    ("tarea", "tareas", "task", "tasks"),
        "u.overdue": ("vencida", "vencidas", "overdue", "overdue"),
        "u.item":    ("ítem", "ítems", "item", "items"),
    ]

    // swiftlint:disable:next type_contents_order
    private static let table: [String: (String, String)] = [
        // MARK: menú de aplicación
        "menu.about":       ("Acerca de Semana", "About Semana"),
        "menu.login":       ("Abrir al iniciar sesión", "Launch at login"),
        "menu.hide":        ("Ocultar Semana", "Hide Semana"),
        "menu.hideOthers":  ("Ocultar a las demás", "Hide Others"),
        "menu.quit":        ("Salir de Semana", "Quit Semana"),
        "menu.week":        ("Semana", "Week"),
        "menu.prevWeek":    ("Semana anterior", "Previous week"),
        "menu.nextWeek":    ("Semana siguiente", "Next week"),
        "menu.thisWeek":    ("Ir a esta semana", "Go to this week"),
        "menu.today":       ("Ir a hoy", "Go to today"),
        "menu.reload":      ("Recargar ahora", "Reload now"),
        "menu.view":        ("Vista", "View"),
        "menu.theme":       ("Tema: %@", "Theme: %@"),
        "menu.filter":      ("Filtro: %@", "Filter: %@"),
        "menu.language":    ("Idioma", "Language"),
        "menu.edit":        ("Edición", "Edit"),
        "menu.cut":         ("Cortar", "Cut"),
        "menu.copy":        ("Copiar", "Copy"),
        "menu.paste":       ("Pegar", "Paste"),
        "menu.selectAll":   ("Seleccionar todo", "Select All"),
        "menu.window":      ("Ventana", "Window"),
        "menu.minimize":    ("Minimizar", "Minimize"),
        "menu.zoom":        ("Zoom", "Zoom"),
        "menu.calendars":   ("Calendarios…", "Calendars…"),

        // MARK: opciones
        "theme.auto":       ("Automático (por hora)", "Auto (by hour)"),
        "theme.light":      ("Claro", "Light"),
        "theme.dark":       ("Oscuro", "Dark"),
        "lang.system":      ("Sistema", "System"),
        "lang.es":          ("Español", "Spanish"),
        "lang.en":          ("English", "English"),
        "filter.all":       ("Todas", "All"),
        "filter.dated":     ("Solo con fecha", "Dated only"),
        "filter.deadlines": ("Solo plazos", "Deadlines only"),
        "filter.projects":  ("Solo proyectos", "Projects only"),
        "refresh.off":      ("Apagado", "Off"),
        "refresh.30":       ("Cada 30 s", "Every 30 s"),
        "refresh.2m":       ("Cada 2 min", "Every 2 min"),
        "refresh.5m":       ("Cada 5 min", "Every 5 min"),
        "refresh.15m":      ("Cada 15 min", "Every 15 min"),

        // MARK: barra superior
        "bar.search":       ("Buscar título, proyecto o etiqueta", "Search title, project or tag"),
        "bar.loading":      ("Cargando…", "Loading…"),
        "bar.today":        ("Hoy", "Today"),
        "bar.week":         ("Semana", "Week"),
        "bar.day":          ("Día", "Day"),
        "bar.calendars":    ("Calendarios ▾", "Calendars ▾"),
        "bar.reload":       ("Recargar", "Reload"),
        "tip.prev":         ("Anterior (⌘←)", "Previous (⌘←)"),
        "tip.next":         ("Siguiente (⌘→)", "Next (⌘→)"),
        "tip.today":        ("Volver a esta semana o a hoy (⌘T)", "Back to this week or today (⌘T)"),
        "tip.mode":         ("Tablero semanal o plan del día elegido", "Weekly board or the plan for a chosen day"),
        "tip.framework":    ("Marco metodológico del plan diario", "Framework used for the day plan"),
        "tip.filter":       ("Filtrar tareas del tablero", "Filter board tasks"),
        "tip.theme":        ("Claro, oscuro o según la hora", "Light, dark or by hour"),
        "tip.refresh":      ("Cada cuánto releer Things", "How often to re-read Things"),
        "tip.calendars":    ("Elige qué calendarios entran en la vista", "Choose which calendars show up"),
        "tip.reload":       ("Volver a leer la base de Things (⌘R)", "Re-read the Things database (⌘R)"),

        // MARK: títulos de ventana y cabeceras
        "win.week":         ("Semana · Things 3", "Week · Things 3"),
        "win.day":          ("Plan del día · Things 3", "Day plan · Things 3"),
        "win.weekOffset":   ("Semana %@ · Things 3", "Week %@ · Things 3"),
        "title.weekRange":  ("%1$@ %2$@ – %3$@ %4$@ %5$@", "%1$@ %2$@ – %3$@ %4$@ %5$@"),
        "title.dayHoy":     ("%@ · hoy", "%@ · today"),
        "day.hoyShort":     ("hoy", "today"),
        "col.overdue":      ("Atrasadas", "Overdue"),
        "col.previous":     ("Anteriores", "Earlier"),
        /// Aviso en la tarjeta cuando el plazo cae en otro día del que la muestra.
        "card.vence":       ("vence %@", "due %@"),
        "tray.undated":     ("Sin fecha", "Undated"),
        "tray.scope":       ("Alcance ▾", "Scope ▾"),
        "tray.scope.week":  ("Relevantes a esta semana", "Relevant to this week"),
        "tray.scope.inbox": ("Bandeja y cualquier momento", "Inbox and anytime"),
        "tray.scope.all":   ("Todas sin fecha", "All undated"),
        "start.inbox":      ("Bandeja", "Inbox"),
        "start.anytime":    ("En cualquier momento", "Anytime"),
        "start.someday":    ("Alguna vez", "Someday"),
        "start.unknown":    ("—", "—"),

        // MARK: barra de estado
        "st.open":          ("Abiertas", "Open"),
        "st.dated":         ("con fecha", "dated"),
        "st.overdue":       ("atrasadas", "overdue"),
        "st.inWeek":        ("en esta semana", "this week"),
        "st.undated":       ("sin fecha", "undated"),
        "st.recurring":     ("recurrentes", "recurring"),
        "st.projects":      ("proyectos", "projects"),
        "st.legend":        ("banda: rojo plazo · azul programada · morado recurrente · gris proyecto",
                             "strip: red deadline · blue scheduled · purple recurring · grey project"),
        "st.read":          ("leído", "read"),
        "st.at":            ("a las", "at"),
        "st.refreshOff":    ("Refresco automático apagado. Usa Recargar (⌘R).",
                             "Auto-refresh is off. Use Reload (⌘R)."),
        "st.item":          ("tarea", "task"),
        "st.items":         ("tareas", "tasks"),
        "mode.live":        ("base viva, solo lectura", "live database, read-only"),
        "mode.mirror":      ("espejo temporal", "temporary mirror"),

        // MARK: plan del día
        "day.timeline":     ("Timeline 08:00–18:00", "Timeline 08:00–18:00"),
        "day.legend":       ("barras: azul = calendario · rojo = profundo · verde = administrativo · " +
                             "morado = energía baja · gris = buffer · claro = pausa",
                             "bars: blue = calendar · red = deep work · green = admin · " +
                             "purple = low energy · grey = buffer · light = break"),
        "day.tasks":        ("Tareas del día (%d)", "Tasks for the day (%d)"),
        "day.directives":   ("Directrices del día", "Directives"),
        "day.matrix":       ("Matriz de Eisenhower", "Eisenhower matrix"),
        "day.energy":       ("Bloques de energía", "Energy blocks"),
        "day.top3":         ("Pareto · las 3 que mueven el día", "Pareto · the 3 that move the day"),
        "day.trio":         ("1 · 3 · 5", "1 · 3 · 5"),
        "day.big":          ("1 grande", "1 big"),
        "day.medium":       ("3 medianas", "3 medium"),
        "day.small":        ("5 chicas", "5 small"),
        "day.noBig":        ("— ninguna de 60+ min estimada", "— none estimated at 60+ min"),
        "day.overCapacity": ("Fuera de la capacidad: %d tareas", "Over capacity: %d tasks"),
        "day.first":        ("Primero: %@ (%d min)", "First: %@ (%d min)"),
        "day.noBlocks":     ("Sin bloques asignados.", "No blocks assigned."),
        "day.none":         ("vacío", "empty"),
        "day.more":         ("… %d más", "… %d more"),
        "day.noTasks":      ("Sin tareas para este día.", "No tasks for this day."),
        "day.emptyDay":     ("Nada con plazo ni agenda en este día. Prueba otra fecha o mira la vista semanal.",
                             "Nothing with a deadline or date on this day. Try another date or check the week view."),
        "day.emptyBlock":   ("Nada agendado: el día está libre o no hay tareas con fecha.",
                             "Nothing scheduled: the day is clear or has no dated tasks."),
        "day.demand":       ("Demanda %1$d min · capacidad %2$d min · %3$d %4$@ · %5$d %6$@",
                             "Demand %1$d min · capacity %2$d min · %3$d %4$@ · %5$d %6$@"),
        "day.status":       ("Marco: %1$@ · demanda %2$d min vs capacidad %3$d min · %4$d %5$@ · "
                             + "%6$d %7$@ · %8$@ %9$@ a las %10$@",
                             "Framework: %1$@ · demand %2$d min vs capacity %3$d min · %4$d %5$@ · "
                             + "%6$d %7$@ · %8$@ %9$@ at %10$@"),
        "day.min":          ("%d min", "%d min"),
        "day.overdueTag":   ("vencida %d d", "overdue %d d"),
        "day.priority":     ("%1$@ · %2$d min", "%1$@ · %2$d min"),
        "day.urgCal":       ("urgente por calendario", "urgent by calendar"),

        // MARK: marcos
        "fw.eisenhower":    ("Matriz de Eisenhower", "Eisenhower matrix"),
        "fw.timeBlock":     ("Time blocking por energía", "Time blocking by energy"),
        "fw.frog":          ("Eat the Frog + 2 min + Parkinson", "Eat the Frog + 2 min + Parkinson"),
        "fw.moscow":        ("MoSCoW", "MoSCoW"),
        "fw.135":           ("1-3-5", "1-3-5"),
        "fw.pareto":        ("Pareto · Top 3", "Pareto · Top 3"),
        "fwS.eisenhower":   ("Eisenhower", "Eisenhower"),
        "fwS.timeBlock":    ("Time blocking", "Time blocking"),
        "fwS.frog":         ("Frog", "Frog"),
        "fwS.moscow":       ("MoSCoW", "MoSCoW"),
        "fwS.135":          ("1-3-5", "1-3-5"),
        "fwS.pareto":       ("Top 3", "Top 3"),
        "fx.eisenhower":    ("Urgencia = tag Urgent, plazo vencido o que cae mañana, o fecha programada ya " +
                             "pasada. Importancia = tag Important o High; Medium, Low o sin etiqueta no puntúan.",
                             "Urgent = tagged Urgent, overdue, or due tomorrow, or its programmed date has " +
                             "passed. Important = tagged Important or High; Medium, Low or no tag don't count."),
        "fx.timeBlock":     ("Reparte el día en bloques según energía: profundo 90–120 min, administrativo " +
                             "30–60, baja energía 30, buffers 15.",
                             "Splits the day into energy-based blocks: deep 90–120 min, admin 30–60, " +
                             "low energy 30, buffers 15."),
        "fx.frog":          ("Lo más difícil primero (frog), lo de 2 minutos suelto, y cada tarea se encoge " +
                             "al tiempo que le des (Parkinson).",
                             "Hardest thing first (frog), 2-minute items done on the spot, and every task " +
                             "shrinks to the time you give it (Parkinson)."),
        "fx.moscow":        ("Must ocupa ~55% de la capacidad libre del día, Should hasta ~85%, Could lo " +
                             "importante que ya no cabe, Won't el desborde real.",
                             "Must fills ~55% of the day's free capacity, Should up to ~85%, Could the " +
                             "important overflow, Won't what today genuinely won't reach."),
        "fx.135":           ("Capacidad fija del día: 1 grande, 3 medianas, 5 chicas. Lo que sobre, queda fuera.",
                             "Fixed capacity: 1 big, 3 medium, 5 small. Whatever doesn't fit stays out."),
        "fx.pareto":        ("Las 3 tareas que explican la mayor parte del avance; el resto es relleno.",
                             "The 3 tasks behind most of the progress; the rest is filler."),

        // MARK: cuadrantes, MoSCoW, bloques
        "q1.title":         ("Hazlo ahora", "Do it now"),
        "q1.hint":          ("urgente + importante", "urgent + important"),
        "q2.title":         ("Agenda", "Schedule it"),
        "q2.hint":          ("importante, sin urgencia", "important, not urgent"),
        "q3.title":         ("Delega o limita", "Delegate or cap it"),
        "q3.hint":          ("urgente, poca importancia", "urgent, not important"),
        "q4.title":         ("Suéltalo", "Drop it"),
        "q4.hint":          ("ni urgente ni importante", "neither urgent nor important"),
        "m.must":           ("Must · tiene que salir hoy", "Must · has to happen today"),
        "m.should":         ("Should · importa pero puede esperar", "Should · matters but can wait"),
        "m.could":          ("Could · si sobra tiempo", "Could · if there's room"),
        "m.wont":           ("Won't · hoy no (decisión explícita)", "Won't · not today (explicit call)"),
        "k.calendar":       ("Calendario", "Calendar"),
        "k.deep":           ("Energía alta", "High energy"),
        "k.admin":          ("Administrativo", "Admin"),
        "k.lowEnergy":      ("Energía baja", "Low energy"),
        "k.buffer":         ("Buffer", "Buffer"),
        "k.rest":           ("Pausa", "Break"),
        "b.buffer":         ("Buffer", "Buffer"),
        "b.longBreak":      ("Pausa larga", "Long break"),

        // MARK: directrices
        "d.frog":           ("Frog: «%@»%@. Sin notificaciones hasta cerrarla.",
                             "Frog: “%@”%@. No notifications until it's done."),
        "d.at":             (" a las %@", " at %@"),
        "d.twoMin":         ("Regla de 2 minutos: %d sueltas se hacen ya, no se agendan (%@).",
                             "2-minute rule: %d loose ones get done now, not scheduled (%@)."),
        "d.q1q3":           ("Q1 %d para ejecutar ya; Q3 %d urgentes pero poco importantes: delega, " +
                             "responde corto o baja de prioridad.",
                             "Q1 %d to run now; Q3 %d urgent but unimportant: delegate, answer short, " +
                             "or drop the priority."),
        "d.wont":           ("Won't de hoy: %d tareas. Es una decisión, no un olvido.",
                             "Today's Won't: %d tasks. That's a decision, not an oversight."),
        "d.135":            ("Capacidad 1-3-5 llena: %d grande + %d medianas + %d chicas; %d quedan fuera.",
                             "1-3-5 capacity full: %d big + %d medium + %d small; %d stay out."),
        "d.top3":           ("Top 3 por impacto: %@.", "Top 3 by impact: %@."),
        "d.overload":       ("Carga: pides %d min y el día da ~%d. Recorta Q4/Won't o alarga el día, " +
                             "pero no finjas que entra.",
                             "Load: you ask for %d min and the day has ~%d. Cut Q4/Won't or lengthen " +
                             "the day, but don't pretend it fits."),
        "d.fits":           ("Carga: %d min de trabajo contra ~%d disponibles. Cabe, así que el margen " +
                             "es para lo que aparezca.",
                             "Load: %d min of work against ~%d available. It fits, so the slack is for " +
                             "whatever shows up."),
        "d.parkinson":      ("Parkinson: cada bloque tiene hora de término. Si sobra tiempo, se cierra " +
                             "antes, no se estira.",
                             "Parkinson: every block has an end time. If time is left, it closes early, " +
                             "it doesn't stretch."),

        // MARK: menú contextual de tarjetas
        "ctx.open":         ("Abrir en Things", "Open in Things"),
        "ctx.complete":     ("Completar", "Complete"),
        "ctx.copyTitle":    ("Copiar título", "Copy title"),
        "ctx.copyUUID":     ("Copiar UUID", "Copy UUID"),
        "ctx.show":         ("Mostrar en Things", "Show in Things"),

        // MARK: calendarios
        "cal.all":          ("Todos", "All"),
        "cal.mine":         ("Solo los míos", "Only mine"),
        "cal.none":         ("Ninguno", "None"),
        "cal.allDay":       ("Todo el día", "All day"),
        "cal.suffix":       ("  ·  %@", "  ·  %@"),
        "cal.provider.local":      ("En este Mac", "On this Mac"),
        "cal.provider.subscribed": ("Suscritos", "Subscribed"),

        // MARK: errores y avisos
        "err.notFound":     ("No encontré la base de Things 3. ¿Está instalado y con datos?",
                             "Couldn't find the Things 3 database. Is Things installed and populated?"),
        "err.permission":   ("No pude leer la base de Things, ni en modo solo lectura ni por espejo. " +
                             "Revisa Acceso Total al Disco.",
                             "I couldn't read the Things database, neither read-only nor through a mirror. " +
                             "Check Full Disk Access."),
        "err.calendar":     ("Sin acceso al calendario (Acceso Total al Disco)",
                             "No calendar access (Full Disk Access)"),
        "err.query":        ("La consulta a la base falló: %@",
                             "The database query failed: %@"),
        "err.noData":       ("Sin datos", "no data"),
        "alert.fda.title":  ("Semana necesita Acceso Total al Disco", "Semana needs Full Disk Access"),
        "alert.fda.body":   ("Things 3 no expone una API de lectura, así que la app lee su base SQLite " +
                             "en modo solo lectura.\n\nSi la ventana sale vacía con un aviso de permisos:\n" +
                             "1. Ajustes del Sistema → Privacidad y seguridad → Acceso Total al Disco\n" +
                             "2. Activa «Semana» (o añádela con «+»)\n3. Cierra y vuelve a abrir la app\n\n" +
                             "La app nunca escribe ni borra nada en tu biblioteca de Things.",
                             "Things 3 exposes no read API, so the app reads its SQLite database in " +
                             "read-only mode.\n\nIf the window comes up empty with a permission warning:\n" +
                             "1. System Settings → Privacy & Security → Full Disk Access\n" +
                             "2. Turn on “Semana” (or add it with “+”)\n3. Quit and reopen the app\n\n" +
                             "The app never writes to or deletes anything in your Things library."),
        "alert.ok":         ("Entendido", "Got it"),
        "alert.loginFail":  ("No se pudo cambiar el arranque automático", "Couldn't change launch at login"),
        "alert.loginBody":  ("%@\n\nAbre Ajustes del Sistema → General → Elementos de inicio y activa o " +
                             "desactiva «Semana» a mano.",
                             "%@\n\nOpen System Settings → General → Login Items and toggle “Semana” by hand."),
        "about.credits":    ("Vista semanal de Things 3 y plan diario con seis marcos.\n\n" +
                             "Lee la base de Things y la de Calendario en modo solo lectura. Nunca " +
                             "escribe: completar y abrir usan el esquema de URL oficial de Things.\n\n" +
                             "Fechas decodificadas del formato empaquetado en bits de Things " +
                             "(año << 16 | mes << 12 | día << 7), verificado contra la UI de Things.",
                             "Weekly board for Things 3 plus a daily plan with six frameworks.\n\n" +
                             "Reads the Things and Calendar databases read-only. It never writes: completing " +
                             "and opening go through Things' official URL scheme.\n\n" +
                             "Dates decoded from Things' bit-packed format (year << 16 | month << 12 | " +
                             "day << 7), verified against the Things UI."),
    ]
}
