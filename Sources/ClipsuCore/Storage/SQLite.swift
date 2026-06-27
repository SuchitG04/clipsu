import Foundation
import SQLite3

/// SQLite's special destructor sentinel telling the library to copy bound bytes.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)
    case message(String)

    public var description: String {
        switch self {
        case .open(let m):    return "SQLite open failed: \(m)"
        case .prepare(let m): return "SQLite prepare failed: \(m)"
        case .step(let m):    return "SQLite step failed: \(m)"
        case .message(let m): return "SQLite error: \(m)"
        }
    }
}

/// A minimal, synchronous wrapper over the C SQLite API.
///
/// Not thread-safe by itself; `Database` serialises all access through a dedicated queue.
public final class SQLiteDB {
    fileprivate var handle: OpaquePointer?

    public init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw SQLiteError.open(msg)
        }
        // Reasonable durability/perf defaults for a local app.
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try execute("PRAGMA foreign_keys = ON;")
        sqlite3_busy_timeout(handle, 3000)
    }

    deinit {
        sqlite3_close(handle)
    }

    private var errorMessage: String {
        guard let handle else { return "no connection" }
        return String(cString: sqlite3_errmsg(handle))
    }

    /// Run one or more statements that return no rows.
    public func execute(_ sql: String) throws {
        var errPtr: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &errPtr) != SQLITE_OK {
            let msg = errPtr.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(errPtr)
            throw SQLiteError.message(msg)
        }
    }

    public func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) != SQLITE_OK {
            throw SQLiteError.prepare(errorMessage)
        }
        return Statement(stmt: stmt, db: self)
    }

    public var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }
    public var changes: Int { Int(sqlite3_changes(handle)) }

    public var userVersion: Int {
        get {
            guard let stmt = try? prepare("PRAGMA user_version;") else { return 0 }
            defer { stmt.finalize() }
            return (try? stmt.step()) == true ? stmt.int(0) : 0
        }
        set {
            try? execute("PRAGMA user_version = \(newValue);")
        }
    }

    /// Returns true if the given function/module is usable (e.g. "fts5").
    public func isModuleAvailable(_ name: String) -> Bool {
        let probe: String
        switch name {
        case "fts5": probe = "CREATE VIRTUAL TABLE temp.__fts_probe USING fts5(x);"
        default:     return false
        }
        do {
            try execute(probe)
            try execute("DROP TABLE temp.__fts_probe;")
            return true
        } catch {
            return false
        }
    }

    public func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }
}

/// A prepared statement with typed binding/column helpers. Reusable via `reset()`.
public final class Statement {
    private let stmt: OpaquePointer?
    private unowned let db: SQLiteDB

    fileprivate init(stmt: OpaquePointer?, db: SQLiteDB) {
        self.stmt = stmt
        self.db = db
    }

    public func finalize() { sqlite3_finalize(stmt) }
    public func reset() { sqlite3_reset(stmt); sqlite3_clear_bindings(stmt) }

    @discardableResult
    public func step() throws -> Bool {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW { return true }
        if rc == SQLITE_DONE { return false }
        throw SQLiteError.step(String(cString: sqlite3_errmsg(db.handleForError)))
    }

    // MARK: Binding (1-based indices)

    public func bind(_ value: Int64?, at index: Int32) {
        if let value { sqlite3_bind_int64(stmt, index, value) } else { sqlite3_bind_null(stmt, index) }
    }
    public func bind(_ value: Int?, at index: Int32) { bind(value.map(Int64.init), at: index) }
    public func bind(_ value: Bool?, at index: Int32) { bind(value.map { $0 ? Int64(1) : Int64(0) }, at: index) }

    public func bind(_ value: String?, at index: Int32) {
        if let value { sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(stmt, index) }
    }

    public func bind(_ value: Double?, at index: Int32) {
        if let value { sqlite3_bind_double(stmt, index, value) } else { sqlite3_bind_null(stmt, index) }
    }

    public func bind(_ value: Data?, at index: Int32) {
        if let value {
            _ = value.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    // MARK: Column readers (0-based indices)

    public func isNull(_ index: Int32) -> Bool { sqlite3_column_type(stmt, index) == SQLITE_NULL }

    public func int(_ index: Int32) -> Int { Int(sqlite3_column_int64(stmt, index)) }
    public func int64(_ index: Int32) -> Int64 { sqlite3_column_int64(stmt, index) }
    public func bool(_ index: Int32) -> Bool { sqlite3_column_int64(stmt, index) != 0 }
    public func double(_ index: Int32) -> Double { sqlite3_column_double(stmt, index) }

    public func string(_ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    public func data(_ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return Data(bytes: bytes, count: count)
    }

    public func optInt(_ index: Int32) -> Int? { isNull(index) ? nil : int(index) }
}

private extension SQLiteDB {
    var handleForError: OpaquePointer? { handle }
}
