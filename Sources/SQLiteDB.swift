import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Minimal sqlite3 wrapper for reading (and for opening temporary copies).
final class SQLiteDB {
    enum Error: LocalizedError {
        case cannotOpen(String)
        case prepare(String, String)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let p): return L.f("err.dbOpen", p)
            case .prepare(let sql, let msg): return L.f("err.sql", msg, sql)
            }
        }
    }

    private var handle: OpaquePointer?
    let path: String

    init(path: String, readOnly: Bool = false) throws {
        self.path = path
        var flags = SQLITE_OPEN_READWRITE
        if readOnly { flags = SQLITE_OPEN_READONLY }
        let rc = sqlite3_open_v2(path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "rc=\(rc)"
            sqlite3_close(handle)
            handle = nil
            throw Error.cannotOpen(msg)
        }
        sqlite3_busy_timeout(handle, 2000)
    }

    deinit {
        if let h = handle { sqlite3_close_v2(h) }
    }

    /// Runs a query and returns each row as a name→value dictionary.
    func rows(_ sql: String) throws -> [[String: Any?]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw Error.prepare(sql, msg)
        }
        defer { sqlite3_finalize(stmt) }

        var out: [[String: Any?]] = []
        let cols = Int(sqlite3_column_count(stmt))
        var names: [String] = []
        for i in 0..<cols { names.append(String(cString: sqlite3_column_name(stmt, Int32(i)))) }

        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                var row: [String: Any?] = [:]
                for i in 0..<cols {
                    switch sqlite3_column_type(stmt, Int32(i)) {
                    case SQLITE_INTEGER:
                        row[names[i]] = Int(sqlite3_column_int64(stmt, Int32(i)))
                    case SQLITE_FLOAT:
                        row[names[i]] = sqlite3_column_double(stmt, Int32(i))
                    case SQLITE_NULL:
                        row[names[i]] = nil
                    default:
                        if let c = sqlite3_column_text(stmt, Int32(i)) {
                            row[names[i]] = String(cString: c)
                        } else {
                            row[names[i]] = nil
                        }
                    }
                }
                out.append(row)
            } else if rc == SQLITE_DONE {
                break
            } else {
                let msg = String(cString: sqlite3_errmsg(handle))
                throw Error.prepare(sql, msg)
            }
        }
        return out
    }

    func int(_ sql: String) -> Int? {
        guard let r = try? rows(sql), let first = r.first else { return nil }
        for (_, v) in first { if let i = v as? Int { return i } }
        return nil
    }
}

private func value(_ row: [String: Any?], _ key: String) -> Any? { row[key] ?? nil }

extension Dictionary where Key == String, Value == Any? {
    func str(_ key: String) -> String? { value(self, key) as? String }
    func intg(_ key: String) -> Int? { value(self, key) as? Int }
}
