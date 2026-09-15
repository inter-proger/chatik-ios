//
//  ImageMIMETypeTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ImageMIMETypeTests: XCTestCase {
    /// Кейс: каждый поддерживаемый формат.
    /// Ожидание: MIME-тип и расширение файла соответствуют формату.
    func test_rawValueAndExtension_matchFormat() {
        let cases: [(type: ImageMIMEType, mime: String, ext: String)] = [
            (.jpeg, "image/jpeg", "jpg"),
            (.png, "image/png", "png"),
            (.webp, "image/webp", "webp"),
        ]

        for testCase in cases {
            XCTAssertEqual(testCase.type.rawValue, testCase.mime)
            XCTAssertEqual(testCase.type.fileExtension, testCase.ext)
        }
        XCTAssertEqual(ImageMIMEType.allCases.count, cases.count)
    }
}
