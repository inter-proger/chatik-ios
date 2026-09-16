//
//  ImageMIMETypeTests.swift
//  ChatikTests
//

import UniformTypeIdentifiers
import XCTest
@testable import Chatik

final class ImageMIMETypeTests: XCTestCase {
    /// Кейс: каждый поддерживаемый формат.
    /// Ожидание: MIME-тип, расширение файла и системный тип содержимого соответствуют формату.
    func test_rawValueExtensionAndUTType_matchFormat() {
        let cases: [(type: ImageMIMEType, mime: String, ext: String, utType: UTType)] = [
            (.jpeg, "image/jpeg", "jpg", .jpeg),
            (.png, "image/png", "png", .png),
            (.webp, "image/webp", "webp", .webP),
        ]

        for testCase in cases {
            XCTAssertEqual(testCase.type.rawValue, testCase.mime)
            XCTAssertEqual(testCase.type.fileExtension, testCase.ext)
            XCTAssertEqual(testCase.type.utType, testCase.utType)
        }
        XCTAssertEqual(ImageMIMEType.allCases.count, cases.count)
    }
}
