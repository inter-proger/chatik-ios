//
//  FormURLEncoderTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class FormURLEncoderTests: XCTestCase {
    func test_encode_joinsSortedPairs() {
        XCTAssertEqual(FormURLEncoder.encode(["b": "2", "a": "1"]), "a=1&b=2")
    }

    func test_encode_escapesReservedCharactersAndSpaces() {
        XCTAssertEqual(FormURLEncoder.encode(["name": "Ivan Petrov", "p": "a&b=c+d/é"]), "name=Ivan+Petrov&p=a%26b%3Dc%2Bd%2F%C3%A9")
    }

    func test_encode_emptyParameters_returnsEmptyString() {
        XCTAssertEqual(FormURLEncoder.encode([:]), "")
    }
}
