import XCTest
@testable import SucclippyCore

final class DatabaseTests: XCTestCase {
    private var dbPath: String!
    private var db: Database!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
        dbPath = dir.appendingPathComponent("succ-\(UUID().uuidString).sqlite").path
        db = try Database(path: dbPath)
    }

    override func tearDownWithError() throws {
        db = nil
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func text(_ s: String, at seconds: TimeInterval = 0, pinned: Bool = false) -> ClipboardItem {
        let date = Date(timeIntervalSince1970: 1_000_000 + seconds)
        return ClipboardItem(kind: .text, plainText: s, sourceAppName: "TestApp",
                             contentHash: Hashing.sha256(s), byteSize: s.utf8.count,
                             pinned: pinned, createdAt: date, lastUsedAt: date)
    }

    func testInsertAndFetch() throws {
        _ = try db.insert(text("hello"))
        _ = try db.insert(text("world"))
        let items = try db.fetch()
        XCTAssertEqual(items.count, 2)
    }

    func testFetchOrdersByRecency() throws {
        _ = try db.insert(text("older", at: 0))
        _ = try db.insert(text("newer", at: 100))
        let items = try db.fetch()
        XCTAssertEqual(items.first?.plainText, "newer")
    }

    func testPinnedFloatToTop() throws {
        _ = try db.insert(text("newest", at: 100))
        _ = try db.insert(text("pinned-old", at: 0, pinned: true))
        let items = try db.fetch()
        XCTAssertEqual(items.first?.plainText, "pinned-old")
    }

    func testFindByHashDedup() throws {
        let item = try db.insert(text("dup"))
        let found = try db.findByHash(item.contentHash)
        XCTAssertEqual(found?.id, item.id)
        XCTAssertNil(try db.findByHash("nope"))
    }

    func testBumpUsageReordersAndCounts() throws {
        let a = try db.insert(text("A", at: 0))
        _ = try db.insert(text("B", at: 100))
        try db.bumpUsage(id: a.id, at: Date(timeIntervalSince1970: 2_000_000))
        let items = try db.fetch()
        XCTAssertEqual(items.first?.plainText, "A")
        XCTAssertEqual(items.first?.copyCount, 2)
    }

    func testSetPinnedAndDelete() throws {
        let a = try db.insert(text("x"))
        try db.setPinned(id: a.id, true)
        XCTAssertEqual(try db.item(id: a.id)?.pinned, true)
        try db.delete(id: a.id)
        XCTAssertNil(try db.item(id: a.id))
    }

    func testRetentionByCountKeepsPinned() throws {
        for i in 0..<5 { _ = try db.insert(text("n\(i)", at: TimeInterval(i))) }
        _ = try db.insert(text("keepme", at: -100, pinned: true)) // oldest but pinned
        _ = try db.pruneRetention(mode: .count, count: 3, days: 0)
        let remaining = try db.fetch()
        // 3 newest non-pinned + 1 pinned == 4
        XCTAssertEqual(remaining.count, 4)
        XCTAssertTrue(remaining.contains { $0.plainText == "keepme" })
    }

    func testSearchMatchesPlainText() throws {
        _ = try db.insert(text("the quick brown fox"))
        _ = try db.insert(text("lazy dog"))
        let hits = try db.fetch(search: "quick")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.plainText, "the quick brown fox")
    }

    func testSearchPrefix() throws {
        _ = try db.insert(text("internationalization"))
        let hits = try db.fetch(search: "intern")
        XCTAssertEqual(hits.count, 1)
    }

    func testSearchMatchesOCRText() throws {
        let img = ClipboardItem(kind: .image, plainText: nil,
                                contentHash: "imghash", byteSize: 10)
        let inserted = try db.insert(img)
        try db.updateOCR(id: inserted.id, text: "Invoice Total 4200")
        let hits = try db.fetch(search: "invoice")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.kind, .image)
    }

    func testFilterByKind() throws {
        _ = try db.insert(text("plain"))
        _ = try db.insert(ClipboardItem(kind: .link, plainText: "https://apple.com",
                                        contentHash: "h", byteSize: 5))
        let links = try db.fetch(filter: .links)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.kind, .link)
    }

    func testFTSAvailable() {
        // Informative: system SQLite should ship FTS5. If this fails, search uses the LIKE fallback.
        XCTAssertTrue(db.ftsAvailable, "FTS5 not available — search falls back to LIKE")
    }
}
