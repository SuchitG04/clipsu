import XCTest
@testable import ClipsuCore

final class ClassifierTests: XCTestCase {
    func testLinks() {
        XCTAssertTrue(ContentClassifier.isLink("https://apple.com"))
        XCTAssertTrue(ContentClassifier.isLink("http://example.com/path?q=1"))
        XCTAssertTrue(ContentClassifier.isLink("www.apple.com"))
        XCTAssertTrue(ContentClassifier.isLink("mailto:me@example.com"))
        XCTAssertFalse(ContentClassifier.isLink("just some text"))
        XCTAssertFalse(ContentClassifier.isLink("hello https://x.com world"))
        XCTAssertFalse(ContentClassifier.isLink(""))
    }

    func testHexColors() {
        XCTAssertTrue(ContentClassifier.isHexColor("#fff"))
        XCTAssertTrue(ContentClassifier.isHexColor("#FFAA00"))
        XCTAssertTrue(ContentClassifier.isHexColor("#11223344"))
        XCTAssertFalse(ContentClassifier.isHexColor("#xyz"))
        XCTAssertFalse(ContentClassifier.isHexColor("fff"))
        XCTAssertFalse(ContentClassifier.isHexColor("#12345"))
    }

    func testKind() {
        XCTAssertEqual(ContentClassifier.kind(forPlainText: "https://apple.com"), .link)
        XCTAssertEqual(ContentClassifier.kind(forPlainText: "#abcdef"), .color)
        XCTAssertEqual(ContentClassifier.kind(forPlainText: "regular note"), .text)
    }

    func testOpenableURL() {
        XCTAssertEqual(ContentClassifier.openableURL(from: "https://apple.com")?.absoluteString, "https://apple.com")
        XCTAssertEqual(ContentClassifier.openableURL(from: "www.apple.com")?.absoluteString, "https://www.apple.com")
        XCTAssertNil(ContentClassifier.openableURL(from: "not a url"))
    }

    func testFTSQueryBuilding() {
        XCTAssertEqual(Database.ftsQuery(from: "foo bar"), "\"foo\"* \"bar\"*")
        XCTAssertEqual(Database.ftsQuery(from: "  Hello, World! "), "\"hello\"* \"world\"*")
        XCTAssertNil(Database.ftsQuery(from: "   "))
        XCTAssertNil(Database.ftsQuery(from: "!!!"))
    }

    func testHashingDeterministic() {
        XCTAssertEqual(Hashing.sha256("abc"), Hashing.sha256("abc"))
        XCTAssertNotEqual(Hashing.sha256("abc"), Hashing.sha256("abd"))
        XCTAssertEqual(Hashing.sha256("abc").count, 64)
    }
}
