import XCTest
@testable import SwiftSpeechCombine

final class SwiftSpeechCombineTests: XCTestCase {
    func testInstantiation() {
        XCTAssertNotNil(SpeechRecognitionSpeechEngine())
    }

    static var allTests = [
        ("testInstantiation", testInstantiation),
    ]
}
