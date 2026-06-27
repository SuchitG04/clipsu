import Foundation

/// The clipboard history store. Owns the SQLite connection, schema/migrations,
/// CRUD, full-text search (FTS5 with a LIKE fallback) and retention pruning.
///
/// All access is serialised through a private serial queue, so it is safe to call
/// from the clipboard timer, OCR completion handlers and the UI alike.
public final class Database: @unchecked Sendable {
    private let db: SQLiteDB
    private let queue = DispatchQueue(label: "ai.clipsu.db")
    public let ftsAvailable: Bool

    private static let columns = """
        id, kind, plain_text, rich_data, ocr_text, image_path, thumb_path,
        image_width, image_height, file_urls, source_bundle_id, source_app_name,
        content_hash, byte_size, pinned, copy_count, created_at, last_used_at
        """

    public init(path: String) throws {
        self.db = try SQLiteDB(path: path)
        self.ftsAvailable = db.isModuleAvailable("fts5")
        try migrate()
    }

    /// Convenience initializer pointing at the standard Application Support location.
    public convenience init() throws {
        try self.init(path: AppPaths.databaseURL.path)
    }

    // MARK: - Migrations

    private func migrate() throws {
        try queue.sync {
            if db.userVersion < 1 {
                try db.transaction {
                    try db.execute("""
                        CREATE TABLE IF NOT EXISTS items (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            kind TEXT NOT NULL,
                            plain_text TEXT,
                            rich_data BLOB,
                            ocr_text TEXT,
                            image_path TEXT,
                            thumb_path TEXT,
                            image_width INTEGER,
                            image_height INTEGER,
                            file_urls TEXT,
                            source_bundle_id TEXT,
                            source_app_name TEXT,
                            content_hash TEXT NOT NULL,
                            byte_size INTEGER NOT NULL,
                            pinned INTEGER NOT NULL DEFAULT 0,
                            copy_count INTEGER NOT NULL DEFAULT 1,
                            created_at REAL NOT NULL,
                            last_used_at REAL NOT NULL
                        );
                        """)
                    try db.execute("CREATE INDEX IF NOT EXISTS idx_items_last_used ON items(last_used_at DESC);")
                    try db.execute("CREATE INDEX IF NOT EXISTS idx_items_hash ON items(content_hash);")

                    if ftsAvailable {
                        try db.execute("""
                            CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
                                plain_text, ocr_text, source_app_name,
                                content='items', content_rowid='id', tokenize='unicode61'
                            );
                            """)
                        try db.execute("""
                            CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
                                INSERT INTO items_fts(rowid, plain_text, ocr_text, source_app_name)
                                VALUES (new.id, new.plain_text, new.ocr_text, new.source_app_name);
                            END;
                            """)
                        try db.execute("""
                            CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
                                INSERT INTO items_fts(items_fts, rowid, plain_text, ocr_text, source_app_name)
                                VALUES ('delete', old.id, old.plain_text, old.ocr_text, old.source_app_name);
                            END;
                            """)
                        try db.execute("""
                            CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE ON items BEGIN
                                INSERT INTO items_fts(items_fts, rowid, plain_text, ocr_text, source_app_name)
                                VALUES ('delete', old.id, old.plain_text, old.ocr_text, old.source_app_name);
                                INSERT INTO items_fts(rowid, plain_text, ocr_text, source_app_name)
                                VALUES (new.id, new.plain_text, new.ocr_text, new.source_app_name);
                            END;
                            """)
                    }
                }
                db.userVersion = 1
            }
        }
    }

    // MARK: - Row mapping

    private func map(_ s: Statement) -> ClipboardItem {
        let fileURLs: [String]? = s.string(9).flatMap { json in
            (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String]
        }
        return ClipboardItem(
            id: s.int64(0),
            kind: ClipKind(rawValue: s.string(1) ?? "text") ?? .text,
            plainText: s.string(2),
            richData: s.data(3),
            ocrText: s.string(4),
            imagePath: s.string(5),
            thumbPath: s.string(6),
            imageWidth: s.optInt(7),
            imageHeight: s.optInt(8),
            fileURLs: fileURLs,
            sourceBundleID: s.string(10),
            sourceAppName: s.string(11),
            contentHash: s.string(12) ?? "",
            byteSize: s.int(13),
            pinned: s.bool(14),
            copyCount: s.int(15),
            createdAt: Date(timeIntervalSince1970: s.double(16)),
            lastUsedAt: Date(timeIntervalSince1970: s.double(17))
        )
    }

    // MARK: - Insert / update

    /// Inserts an item and returns it with the assigned id.
    @discardableResult
    public func insert(_ item: ClipboardItem) throws -> ClipboardItem {
        try queue.sync {
            let stmt = try db.prepare("""
                INSERT INTO items
                (kind, plain_text, rich_data, ocr_text, image_path, thumb_path,
                 image_width, image_height, file_urls, source_bundle_id, source_app_name,
                 content_hash, byte_size, pinned, copy_count, created_at, last_used_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
                """)
            defer { stmt.finalize() }
            bindBody(stmt, item, startingAt: 1)
            try stmt.step()
            var result = item
            result.id = db.lastInsertRowID
            return result
        }
    }

    /// Binds the 17 mutable columns (everything except `id`) starting at `index`.
    private func bindBody(_ stmt: Statement, _ item: ClipboardItem, startingAt index: Int32) {
        let urlsJSON: String? = item.fileURLs.flatMap { urls in
            (try? JSONSerialization.data(withJSONObject: urls)).map { String(decoding: $0, as: UTF8.self) }
        }
        stmt.bind(item.kind.rawValue, at: index)
        stmt.bind(item.plainText, at: index + 1)
        stmt.bind(item.richData, at: index + 2)
        stmt.bind(item.ocrText, at: index + 3)
        stmt.bind(item.imagePath, at: index + 4)
        stmt.bind(item.thumbPath, at: index + 5)
        stmt.bind(item.imageWidth, at: index + 6)
        stmt.bind(item.imageHeight, at: index + 7)
        stmt.bind(urlsJSON, at: index + 8)
        stmt.bind(item.sourceBundleID, at: index + 9)
        stmt.bind(item.sourceAppName, at: index + 10)
        stmt.bind(item.contentHash, at: index + 11)
        stmt.bind(item.byteSize, at: index + 12)
        stmt.bind(item.pinned, at: index + 13)
        stmt.bind(item.copyCount, at: index + 14)
        stmt.bind(item.createdAt.timeIntervalSince1970, at: index + 15)
        stmt.bind(item.lastUsedAt.timeIntervalSince1970, at: index + 16)
    }

    public func updatePlainText(id: Int64, text: String) throws {
        try queue.sync {
            let stmt = try db.prepare("UPDATE items SET plain_text = ? WHERE id = ?;")
            defer { stmt.finalize() }
            stmt.bind(text, at: 1)
            stmt.bind(id, at: 2)
            try stmt.step()
        }
    }

    public func updateOCR(id: Int64, text: String?) throws {
        try queue.sync {
            let stmt = try db.prepare("UPDATE items SET ocr_text = ? WHERE id = ?;")
            defer { stmt.finalize() }
            stmt.bind(text, at: 1)
            stmt.bind(id, at: 2)
            try stmt.step()
        }
    }

    public func setPinned(id: Int64, _ pinned: Bool) throws {
        try queue.sync {
            let stmt = try db.prepare("UPDATE items SET pinned = ? WHERE id = ?;")
            defer { stmt.finalize() }
            stmt.bind(pinned, at: 1)
            stmt.bind(id, at: 2)
            try stmt.step()
        }
    }

    /// Marks an item as freshly used: bumps `copy_count` and `last_used_at`.
    public func bumpUsage(id: Int64, at date: Date = Date()) throws {
        try queue.sync {
            let stmt = try db.prepare("UPDATE items SET copy_count = copy_count + 1, last_used_at = ? WHERE id = ?;")
            defer { stmt.finalize() }
            stmt.bind(date.timeIntervalSince1970, at: 1)
            stmt.bind(id, at: 2)
            try stmt.step()
        }
    }

    // MARK: - Delete

    public func delete(id: Int64) throws {
        try queue.sync {
            let stmt = try db.prepare("DELETE FROM items WHERE id = ?;")
            defer { stmt.finalize() }
            stmt.bind(id, at: 1)
            try stmt.step()
        }
    }

    public func deleteAll() throws {
        try queue.sync { try db.execute("DELETE FROM items;") }
    }

    // MARK: - Queries

    public func item(id: Int64) throws -> ClipboardItem? {
        try queue.sync {
            let stmt = try db.prepare("SELECT \(Self.columns) FROM items WHERE id = ?;")
            defer { stmt.finalize() }
            stmt.bind(id, at: 1)
            return try stmt.step() ? map(stmt) : nil
        }
    }

    /// Most recent item by `last_used_at` (used for last-item dedup).
    public func mostRecent() throws -> ClipboardItem? {
        try queue.sync {
            let stmt = try db.prepare("SELECT \(Self.columns) FROM items ORDER BY last_used_at DESC LIMIT 1;")
            defer { stmt.finalize() }
            return try stmt.step() ? map(stmt) : nil
        }
    }

    /// Finds the newest item with a matching content hash (for whole-history dedup).
    public func findByHash(_ hash: String) throws -> ClipboardItem? {
        try queue.sync {
            let stmt = try db.prepare("SELECT \(Self.columns) FROM items WHERE content_hash = ? ORDER BY last_used_at DESC LIMIT 1;")
            defer { stmt.finalize() }
            stmt.bind(hash, at: 1)
            return try stmt.step() ? map(stmt) : nil
        }
    }

    public func count() throws -> Int {
        try queue.sync {
            let stmt = try db.prepare("SELECT COUNT(*) FROM items;")
            defer { stmt.finalize() }
            return try stmt.step() ? stmt.int(0) : 0
        }
    }

    /// Fetches items filtered by category and optional search text, newest first (pinned float to top).
    public func fetch(filter: ClipFilter = .all, search: String? = nil, limit: Int = 500) throws -> [ClipboardItem] {
        let trimmed = (search ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return try queue.sync {
            var clauses: [String] = []

            // Category filter
            switch filter {
            case .pinned:
                clauses.append("items.pinned = 1")
            case .all:
                break
            default:
                if let kinds = filter.kinds {
                    let placeholders = kinds.map { _ in "?" }.joined(separator: ",")
                    clauses.append("items.kind IN (\(placeholders))")
                }
            }

            // Search
            var useFTS = false
            if !trimmed.isEmpty {
                if ftsAvailable, Self.ftsQuery(from: trimmed) != nil {
                    useFTS = true
                    clauses.append("items.id IN (SELECT rowid FROM items_fts WHERE items_fts MATCH ?)")
                } else {
                    // LIKE fallback: every token must appear in the combined text.
                    let tokens = trimmed.lowercased().split(separator: " ").map(String.init)
                    for _ in tokens {
                        clauses.append("lower(coalesce(items.plain_text,'') || ' ' || coalesce(items.ocr_text,'') || ' ' || coalesce(items.source_app_name,'')) LIKE ?")
                    }
                }
            }

            let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
            let sql = "SELECT \(Self.columns) FROM items \(whereSQL) ORDER BY items.pinned DESC, items.last_used_at DESC LIMIT \(limit);"
            let stmt = try db.prepare(sql)
            defer { stmt.finalize() }

            // Bind in declaration order: kinds first, then search.
            var bindIndex: Int32 = 1
            if case .pinned = filter {
                // no binds
            } else if filter != .all, let kinds = filter.kinds {
                for k in kinds { stmt.bind(k.rawValue, at: bindIndex); bindIndex += 1 }
            }
            if !trimmed.isEmpty {
                if useFTS, let q = Self.ftsQuery(from: trimmed) {
                    stmt.bind(q, at: bindIndex); bindIndex += 1
                } else {
                    let tokens = trimmed.lowercased().split(separator: " ").map(String.init)
                    for t in tokens { stmt.bind("%\(t)%", at: bindIndex); bindIndex += 1 }
                }
            }

            var result: [ClipboardItem] = []
            while try stmt.step() { result.append(map(stmt)) }
            return result
        }
    }

    // MARK: - Retention

    /// Prunes history per the retention policy. Pinned items are always kept.
    /// Returns the file paths (image/thumb) of deleted rows so the caller can clean up disk.
    @discardableResult
    public func pruneRetention(mode: RetentionMode, count: Int, days: Int) throws -> [String] {
        try queue.sync {
            var deletedPaths: [String] = []
            try db.transaction {
                let condition: String
                let binder: (Statement) -> Void
                switch mode {
                case .keepAll:
                    return
                case .count:
                    // Keep the newest `count` non-pinned items; delete the rest.
                    condition = """
                        id IN (
                            SELECT id FROM items WHERE pinned = 0
                            ORDER BY last_used_at DESC
                            LIMIT -1 OFFSET ?
                        )
                        """
                    binder = { stmt in stmt.bind(max(0, count), at: 1) }
                case .days:
                    let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
                    condition = "pinned = 0 AND last_used_at < ?"
                    binder = { stmt in stmt.bind(cutoff, at: 1) }
                }

                // Collect file paths to delete first.
                let sel = try db.prepare("SELECT image_path, thumb_path FROM items WHERE \(condition);")
                defer { sel.finalize() }
                binder(sel)
                while try sel.step() {
                    if let p = sel.string(0) { deletedPaths.append(p) }
                    if let t = sel.string(1) { deletedPaths.append(t) }
                }

                let del = try db.prepare("DELETE FROM items WHERE \(condition);")
                defer { del.finalize() }
                binder(del)
                try del.step()
            }
            return deletedPaths
        }
    }

    /// All image/thumb paths currently referenced (for orphan cleanup).
    public func allReferencedPaths() throws -> Set<String> {
        try queue.sync {
            let stmt = try db.prepare("SELECT image_path, thumb_path FROM items WHERE image_path IS NOT NULL OR thumb_path IS NOT NULL;")
            defer { stmt.finalize() }
            var set = Set<String>()
            while try stmt.step() {
                if let p = stmt.string(0) { set.insert(p) }
                if let t = stmt.string(1) { set.insert(t) }
            }
            return set
        }
    }

    // MARK: - FTS query building

    /// Turns user input into a safe FTS5 prefix query: `foo bar` → `"foo"* "bar"*`.
    /// Returns nil if nothing usable remains.
    static func ftsQuery(from input: String) -> String? {
        let tokens = input
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}
