import XCTest
@testable import ReachNews

final class CollectorIconTests: XCTestCase {
    func testIconResolvesAgainstOriginNotAPIPrefix() {
        let origin = URL(string: "https://example.test/api/v1")!
        let result = CollectorIconValidation.resourceURL(path: "/api/v1/collector-skills/s/icon.svg?v=hash", origin: origin)
        XCTAssertEqual(result?.absoluteString, "https://example.test/api/v1/collector-skills/s/icon.svg?v=hash")
        XCTAssertNil(CollectorIconValidation.resourceURL(path: "https://other.test/api/v1/collector-skills/s/icon.svg", origin: origin))
        XCTAssertNil(CollectorIconValidation.resourceURL(path: "javascript:alert(1)", origin: origin))
    }

    func testOnlyValidStaticSVGAccepted() {
        XCTAssertTrue(CollectorIconValidation.isValidSVG(Data("<svg xmlns='http://www.w3.org/2000/svg'><path d='M0 0 L10 10'/></svg>".utf8)))
        for value in ["not an SVG", "<svg><path></svg>", "<svg><script>alert(1)</script></svg>", "<svg><image href='https://evil.test/a'/></svg>"] {
            XCTAssertFalse(CollectorIconValidation.isValidSVG(Data(value.utf8)))
        }
    }
}
