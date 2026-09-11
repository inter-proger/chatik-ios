//
//  FormURLEncoderTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class FormURLEncoderTests: XCTestCase {
    /// Кейс: несколько параметров в произвольном порядке.
    /// Ожидание: пары отсортированы по ключу и соединены `&` (детерминированное тело запроса).
    func test_encode_joinsSortedPairs() {
        XCTAssertEqual(FormURLEncoder.encode(["b": "2", "a": "1"]), "a=1&b=2")
    }

    /// Кейс: значения с пробелами, зарезервированными символами (`& = + /`) и не-ASCII.
    /// Ожидание: пробел → `+`, остальное percent-encoded по правилам form-urlencoded.
    func test_encode_escapesReservedCharactersAndSpaces() {
        XCTAssertEqual(FormURLEncoder.encode(["name": "Ivan Petrov", "p": "a&b=c+d/é"]), "name=Ivan+Petrov&p=a%26b%3Dc%2Bd%2F%C3%A9")
    }

    /// Кейс: пустой словарь параметров.
    /// Ожидание: пустая строка.
    func test_encode_emptyParameters_returnsEmptyString() {
        XCTAssertEqual(FormURLEncoder.encode([:]), "")
    }
}
