import Foundation

/// Reads Things 3 without ever writing to its database.
///
/// Two paths, in this order:
/// 1. **Live database in read-only mode** (`SQLITE_OPEN_READONLY`). SQLite serves the
///    read via MVCC from the WAL: it doesn't block Things or modify anything. It's the same
///    path the installed Things MCP uses, and it avoids copying 31 MB on every refresh.
/// 2. **Temporary mirror** (`main.sqlite` + `-wal` + `-shm` copied to a directory of
///    our own), validated with `PRAGMA quick_check` before trusting it. The copy is
///    opened read-write *on the copy only*, so SQLite can rebuild
///    its WAL index if needed.
///
/// The original database is never opened with a write handle. Actions
/// (open, complete) are delegated to Things' official URL scheme.
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

    /// Non-fatal notice (e.g. missing permissions) shown by the UI.
    private(set) var lastNotice: String?
    /// Read mode used for the last snapshot: a "live" / "mirror" token that the
    /// UI translates. Independent of the interface language.
    private(set) var lastReadMode: String = "—"

    // MARK: - Database discovery

    /// Looks for `main.sqlite` under the group container. Prefers the modern
    /// `ThingsData-XXXX/…` layout and, among equals, the most recently modified copy.
    /// Walked by hand on purpose: a permission denial must be told apart from
    /// "the database doesn't exist", so a missing FDA isn't reported as a lost library.
    func locateDatabase() -> URL? {
        // `SEMANA_THINGS_DB` lets you point at another database (the repo's demo mode, or
        // a copy for testing). If the file doesn't exist it's ignored and normal
        // discovery continues: a mistyped path shouldn't look like "Things isn't
        // installed".
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
            lastNotice = L.s("err.fdaBlocked")
        }
        return ranked.first
    }

    private func modificationDate(_ url: URL) -> Date {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
    }

    /// Modification date of the original database: lets unchanged refreshes be skipped.
    func sourceModificationDate() -> Date? {
        guard let url = locateDatabase() else { return nil }
        return modificationDate(url)
    }

    // MARK: - Snapshot

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
            // Read-write on our copy: SQLite can rebuild the -shm.
            let db = try SQLiteDB(path: copy.path)
            let check = try db.rows("PRAGMA quick_check")
            guard firstValue(check) == "ok" else { return nil }   // broken mirror: don't show it
            var board = Board()
            board.databasePath = source.path
            lastReadMode = "mirror"
            try fill(&board, db)
            return board
        } catch {
            return nil
        }
    }

    /// First text value of the first row (for `PRAGMA quick_check`).
    private func firstValue(_ rows: [[String: Any?]]) -> String? {
        guard let row = rows.first else { return nil }
        for (_, v) in row { if let s = v as? String { return s } }
        return nil
    }

    // MARK: - Board fill

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
        board.authToken = readAuthToken(db)
    }

    /// URL-scheme token. Its absence is tolerated (the demo database has no
    /// `TMSettings`): without a token, the Complete action warns instead of failing.
    private func readAuthToken(_ db: SQLiteDB) -> String? {
        guard let rows = try? db.rows("SELECT uriSchemeAuthenticationToken AS t FROM TMSettings LIMIT 1"),
              let token = rows.first?.str("t"), !token.isEmpty else { return nil }
        return token
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
            if recurring && paused { continue }        // Things doesn't show them

            var startRaw = r.intg("startDate")
            // For repeating to-dos, startDate holds the original anchor; the next
            // real occurrence is in rt1_nextInstanceStartDate.
            if recurring { startRaw = r.intg("nextStart") ?? startRaw }

            let rawTags = r.str("tagTitles") ?? ""
            let tags = rawTags.split(separator: Self.tagSeparator, omittingEmptySubsequences: true)
                .map(String.init)

            items.append(TaskItem(
                id: r.str("uuid") ?? "",
                title: r.str("title") ?? L.s("task.untitled"),
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

    // MARK: - URL-scheme actions (we never write to the database)

    static func showURL(uuid: String) -> URL? { URL(string: "things:///show?id=\(uuid)") }

    /// `things:///complete` doesn't exist in the official scheme: completing is `update`
    /// (or `update-project`) with `completed=true` and the authorization token.
    static func completeURL(item: TaskItem, authToken: String) -> URL? {
        var c = URLComponents()
        c.scheme = "things"
        c.host = ""
        c.path = item.isProject ? "/update-project" : "/update"
        // Strict encoding: URLComponents lets '+' through, which the receiver may
        // read as a space, breaking the token.
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s }
        c.percentEncodedQueryItems = [
            URLQueryItem(name: "id", value: enc(item.id)),
            URLQueryItem(name: "completed", value: "true"),
            URLQueryItem(name: "auth-token", value: enc(authToken)),
        ]
        return c.url
    }
}
