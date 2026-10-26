import Foundation

/// Lee Things 3 sin escribir nunca en su base.
///
/// Dos rutas, en este orden:
/// 1. **Base viva en modo solo lectura** (`SQLITE_OPEN_READONLY`). SQLite atiende la
///    lectura por MVCC desde el WAL: no bloquea a Things ni modifica nada. Es la misma
///    vía que usa el MCP de Things instalado, y evita copiar 31 MB en cada refresco.
/// 2. **Espejo temporal** (`main.sqlite` + `-wal` + `-shm` copiados a un directorio
///    propio), validado con `PRAGMA quick_check` antes de fiarnos de él. La copia se
///    abre en lectura-escritura *solo sobre la copia*, para que SQLite pueda rehacer
///    su índice WAL si hace falta.
///
/// En ningún caso se abre la base original con un handle de escritura. Las acciones
/// (abrir, completar) se delegan al esquema de URL oficial de Things.
final class ThingsStore {
    enum StoreError: LocalizedError {
        case notFound
        case permissionDenied(String)
        case query(String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return L.s("err.notFound")
            case .permissionDenied(let hint):
                return hint
            case .query(let msg):
                return L.f("err.query", msg)
            }
        }
    }

    private static let groupContainer = "JLMPQHK86H.com.culturedcode.ThingsMac"
    private static let tagSeparator = "\u{1f}"

    private let fm = FileManager.default
    private var cachedSourceURL: URL?
    private var cacheDate = Date.distantPast

    /// Aviso no fatal (por ejemplo, falta de permisos) que la UI muestra.
    private(set) var lastNotice: String?
    /// Modo de lectura usado en la última instantánea: token "live" / "mirror" que la
    /// UI traduce. Es independiente del idioma de la interfaz.
    private(set) var lastReadMode: String = "—"

    // MARK: - Descubrimiento de la base

    /// Busca `main.sqlite` bajo el group container. Prefiere el layout moderno
    /// `ThingsData-XXXX/…` y, entre iguales, la copia modificada más reciente.
    /// Caminada manual a propósito: un rechazo de permisos debe distinguirse de
    /// "la base no existe", para no reportar un FDA ausente como biblioteca perdida.
    func locateDatabase() -> URL? {
        // `SEMANA_THINGS_DB` permite apuntar a otra base (el modo demo del repo, o
        // una copia para pruebas). Si el archivo no existe, se ignora y se sigue con
        // el descubrimiento normal: una ruta mal escrita no debe parecer "Things no
        // está instalado".
        if let override = ProcessInfo.processInfo.environment["SEMANA_THINGS_DB"],
           !override.isEmpty, fm.fileExists(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        if let cached = cachedSourceURL, Date().timeIntervalSince(cacheDate) < 60,
           fm.fileExists(atPath: cached.path) { return cached }

        let root = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(Self.groupContainer)")
        var candidates: [URL] = []
        var permissionDenied = false
        var stack: [URL] = [root]

        while let dir = stack.popLast() {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]) else {
                if fm.fileExists(atPath: dir.path) { permissionDenied = true }
                continue
            }
            for entry in entries {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue {
                    stack.append(entry)
                } else if entry.lastPathComponent == "main.sqlite" {
                    candidates.append(entry)
                }
            }
        }

        let ranked = candidates.sorted { a, b in
            let aModern = a.path.contains("ThingsData-")
            let bModern = b.path.contains("ThingsData-")
            if aModern != bModern { return aModern && !bModern }
            return modificationDate(a) > modificationDate(b)
        }
        cachedSourceURL = ranked.first
        cacheDate = Date()
        if ranked.first == nil && permissionDenied {
            lastNotice = "macOS bloqueó el acceso a la base de Things. Concede Acceso Total al Disco a «Semana» " +
                "(Ajustes del Sistema → Privacidad y seguridad → Acceso Total al Disco) y reinicia la app."
        }
        return ranked.first
    }

    private func modificationDate(_ url: URL) -> Date {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
    }

    /// Modificación de la base original: permite saltarse refrescos sin cambios.
    func sourceModificationDate() -> Date? {
        guard let url = locateDatabase() else { return nil }
        return modificationDate(url)
    }

    // MARK: - Instantánea

    func snapshot() -> Result<Board, StoreError> {
        guard let source = locateDatabase() else { return .failure(.notFound) }

        if let board = tryLiveRead(source) { return .success(board) }
        if let board = tryMirrorRead(source) { return .success(board) }

        return .failure(.permissionDenied(L.s("err.permission")))
    }

    private func tryLiveRead(_ source: URL) -> Board? {
        do {
            let db = try SQLiteDB(path: source.path, readOnly: true)
            _ = try db.rows("SELECT count(*) AS n FROM TMTask LIMIT 1")
            var board = Board()
            board.databasePath = source.path
            lastReadMode = "live"
            try fill(&board, db)
            return board
        } catch {
            return nil
        }
    }

    private func tryMirrorRead(_ source: URL) -> Board? {
        let dir = fm.temporaryDirectory.appendingPathComponent("ThingsWeek.read", isDirectory: true)
        try? fm.removeItem(at: dir)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { return nil }
        defer { try? fm.removeItem(at: dir) }

        let copy = dir.appendingPathComponent("main.sqlite")
        do {
            try fm.copyItem(at: source, to: copy)
            for suffix in ["-wal", "-shm"] {
                let side = source.deletingLastPathComponent()
                    .appendingPathComponent(source.lastPathComponent + suffix)
                if fm.fileExists(atPath: side.path) {
                    try? fm.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
                }
            }
        } catch { return nil }

        do {
            // Lectura-escritura sobre nuestra copia: SQLite puede reconstruir el -shm.
            let db = try SQLiteDB(path: copy.path)
            let check = try db.rows("PRAGMA quick_check")
            guard firstValue(check) == "ok" else { return nil }   // espejo roto: no lo mostramos
            var board = Board()
            board.databasePath = source.path
            lastReadMode = "mirror"
            try fill(&board, db)
            return board
        } catch {
            return nil
        }
    }

    /// Primer valor textual de la primera fila (para `PRAGMA quick_check`).
    private func firstValue(_ rows: [[String: Any?]]) -> String? {
        guard let row = rows.first else { return nil }
        for (_, v) in row { if let s = v as? String { return s } }
        return nil
    }

    // MARK: - Relleno del tablero

    private func fill(_ board: inout Board, _ db: SQLiteDB) throws {
        board.generatedAt = Date()
        board.readMode = lastReadMode
        board.tasks = try readTasks(db)
        board.counts.open = board.tasks.count
        board.counts.dated = board.tasks.filter { $0.hasDate }.count
        board.counts.recurring = board.tasks.filter { $0.recurring }.count
        board.counts.projects = board.tasks.filter { $0.isProject }.count
        let today = Calendar.current.startOfDay(for: Date())
        board.counts.overdue = board.tasks.filter {
            guard let p = $0.placement else { return false }
            return Calendar.current.startOfDay(for: p) < today
        }.count
        board.counts.undated = board.counts.open - board.counts.dated
    }

    private func readTasks(_ db: SQLiteDB) throws -> [TaskItem] {
        let sql = """
        SELECT
            T.uuid AS uuid,
            T.title AS title,
            T.notes AS notes,
            T.type AS type,
            T.start AS start,
            T.startDate AS startDate,
            T.deadline AS deadline,
            CASE WHEN T.deadlineSuppressionDate THEN 1 ELSE 0 END AS suppressed,
            CASE WHEN T.rt1_recurrenceRule IS NOT NULL THEN 1 ELSE 0 END AS recurring,
            CASE WHEN T.rt1_instanceCreationPaused THEN 1 ELSE 0 END AS paused,
            T.rt1_nextInstanceStartDate AS nextStart,
            T.openChecklistItemsCount AS openCheck,
            T.checklistItemsCount AS totalCheck,
            P.title AS projTitle,
            A.title AS areaTitle,
            H.title AS headTitle,
            (SELECT group_concat(TAG.title, '\(Self.tagSeparator)')
               FROM TMTaskTag TT JOIN TMTag TAG ON TT.tags = TAG.uuid
              WHERE TT.tasks = T.uuid) AS tagTitles,
            T."index" AS sortIndex,
            T.creationDate AS creationDate
        FROM TMTask T
        LEFT JOIN TMTask P ON T.project = P.uuid
        LEFT JOIN TMArea A ON T.area = A.uuid
        LEFT JOIN TMTask H ON T.heading = H.uuid
        WHERE T.trashed = 0
          AND T.status = 0
          AND T.type IN (0, 1)
        ORDER BY T."index"
        """
        let rows = try db.rows(sql)
        var items: [TaskItem] = []
        items.reserveCapacity(rows.count)

        for r in rows {
            let recurring = (r.intg("recurring") ?? 0) == 1
            let paused = (r.intg("paused") ?? 0) == 1
            if recurring && paused { continue }        // Things no las muestra

            var startRaw = r.intg("startDate")
            // En las recurrentes, startDate guarda el ancla original; la próxima
            // ocurrencia real está en rt1_nextInstanceStartDate.
            if recurring { startRaw = r.intg("nextStart") ?? startRaw }

            let rawTags = r.str("tagTitles") ?? ""
            let tags = rawTags.split(separator: Self.tagSeparator, omittingEmptySubsequences: true)
                .map(String.init)

            items.append(TaskItem(
                id: r.str("uuid") ?? "",
                title: r.str("title") ?? "(sin título)",
                notes: r.str("notes") ?? "",
                isProject: (r.intg("type") ?? 0) == 1,
                start: StartBucket(raw: r.intg("start") ?? -1),
                startRaw: startRaw,
                deadlineRaw: r.intg("deadline"),
                deadlineSuppressed: (r.intg("suppressed") ?? 0) == 1,
                recurring: recurring,
                openChecklist: r.intg("openCheck") ?? 0,
                totalChecklist: r.intg("totalCheck") ?? 0,
                project: r.str("projTitle"),
                area: r.str("areaTitle"),
                heading: r.str("headTitle"),
                tags: tags,
                sortIndex: r.intg("sortIndex") ?? 0,
                created: (r["creationDate"] as? Double).map { Date(timeIntervalSince1970: $0) }
            ))
        }
        return items
    }

    // MARK: - Acciones por esquema de URL (nunca escribimos en la base)

    static func showURL(uuid: String) -> URL? { URL(string: "things:///show?id=\(uuid)") }
    static func completeURL(uuid: String) -> URL? { URL(string: "things:///complete?id=\(uuid)") }
}
