import XCTest
@testable import FocusGuardCore
import FocusGuardShared

final class DomainValidationTests: XCTestCase {
    func testValidDomains() {
        for d in ["youtube.com", "m.youtube.com", "sub.example.co.uk", "a-b.example.com"] {
            XCTAssertEqual(try? DomainValidation.validate(d).get(), d, "expected \(d) valid")
        }
    }

    func testNormalizeStripsSchemeWwwPathPort() {
        XCTAssertEqual(DomainValidation.normalize("https://www.YouTube.com/watch?v=1"), "youtube.com")
        XCTAssertEqual(DomainValidation.normalize("http://example.com:8080/path"), "example.com")
        XCTAssertEqual(DomainValidation.normalize("  Example.COM  "), "example.com")
    }

    func testRejectsNoDot() {
        XCTAssertEqual(DomainValidation.validate("localhostish"), .failure(.noDot))
    }

    func testRejectsLeadingTrailingDot() {
        XCTAssertEqual(DomainValidation.validate(".example.com"), .failure(.leadingTrailingDot))
        XCTAssertEqual(DomainValidation.validate("example.com."), .failure(.leadingTrailingDot))
        XCTAssertEqual(DomainValidation.validate("a..b.com"), .failure(.leadingTrailingDot))
    }

    func testRejectsNewlineInjection() {
        // A hand-edited blocklist line trying to inject a second hosts entry.
        let injected = "evil.com 0.0.0.0 apple.com"
        if case .success = DomainValidation.validate(injected) {
            XCTFail("space/injection payload must be rejected")
        }
        XCTAssertEqual(DomainValidation.validate("evil.com\n127.0.0.1"), .failure(.invalidCharacter))
    }

    func testRejectsIDN() {
        XCTAssertEqual(DomainValidation.validate("münchen.de"), .failure(.nonASCII))
        XCTAssertEqual(DomainValidation.validate("例え.jp"), .failure(.nonASCII))
    }

    func testRejectsOverLongLabelAndTotal() {
        let longLabel = String(repeating: "a", count: 64) + ".com"
        XCTAssertEqual(DomainValidation.validate(longLabel), .failure(.labelTooLong))
        let longTotal = (0..<10).map { _ in String(repeating: "a", count: 25) }.joined(separator: ".") + ".com"
        XCTAssertEqual(DomainValidation.validate(longTotal), .failure(.tooLong))
    }

    func testReservedDomains() {
        for d in ["localhost", "broadcasthost", "apple.com", "push.apple.com", "myhost.local", "icloud.com"] {
            XCTAssertEqual(DomainValidation.validate(d), .failure(.reserved), "expected \(d) reserved")
        }
    }

    func testReservedMapsToCommandError() {
        XCTAssertEqual(DomainValidationError.reserved.commandError, .reservedDomain)
        XCTAssertEqual(DomainValidationError.noDot.commandError, .invalidDomain)
    }

    func testHyphenEdges() {
        XCTAssertEqual(DomainValidation.validate("-bad.com"), .failure(.invalidCharacter))
        XCTAssertEqual(DomainValidation.validate("bad-.com"), .failure(.invalidCharacter))
    }
}
