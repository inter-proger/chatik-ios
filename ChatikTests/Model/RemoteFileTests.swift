//
//  RemoteFileTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class RemoteFileTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: JSON изображения из документации с `data.small_url`.
    /// Ожидание: все поля разобраны, `smallURL` взят из вложенного `data`.
    func test_decode_image_readsAllFieldsAndSmallURL() throws {
        let json = """
        {
          "file_id": 1,
          "type": "image",
          "url": "http://localhost:8080/static/uploads/a.jpg",
          "size": 8293,
          "filename": "photo.jpg",
          "extension": "jpg",
          "data": { "small_url": "http://localhost:8080/static/uploads/a_small.jpg" }
        }
        """

        let file = try decoder.decode(RemoteFile.self, from: Data(json.utf8))

        XCTAssertEqual(file, RemoteFile(
            fileId: 1,
            type: .image,
            url: URL(string: "http://localhost:8080/static/uploads/a.jpg")!,
            size: 8293,
            filename: "photo.jpg",
            fileExtension: "jpg",
            smallURL: URL(string: "http://localhost:8080/static/uploads/a_small.jpg")
        ))
    }

    /// Кейс: файл типа `other` с пустым `data`.
    /// Ожидание: разобран без ошибок, `smallURL == nil`.
    func test_decode_other_emptyData_hasNoSmallURL() throws {
        let json = #"{"file_id":2,"type":"other","url":"http://h/f","size":10,"filename":"doc","extension":"file","data":{}}"#

        let file = try decoder.decode(RemoteFile.self, from: Data(json.utf8))

        XCTAssertEqual(file.type, .other)
        XCTAssertEqual(file.fileExtension, "file")
        XCTAssertNil(file.smallURL)
    }

    /// Кейс: сервер прислал новый, неизвестный клиенту тип и не прислал `data`.
    /// Ожидание: тип читается как `.other`, отсутствие `data` не считается ошибкой.
    func test_decode_unknownTypeWithoutData_fallsBackToOther() throws {
        let json = #"{"file_id":3,"type":"gif","url":"http://h/f.gif","size":10,"filename":"a.gif","extension":"gif"}"#

        let file = try decoder.decode(RemoteFile.self, from: Data(json.utf8))

        XCTAssertEqual(file.type, .other)
        XCTAssertNil(file.smallURL)
    }

    /// Кейс: сервер прислал `"data": null`.
    /// Ожидание: разобран без ошибок, `smallURL == nil`.
    func test_decode_nullData_hasNoSmallURL() throws {
        let json = #"{"file_id":4,"type":"other","url":"http://h/f","size":10,"filename":"doc","extension":"file","data":null}"#

        let file = try decoder.decode(RemoteFile.self, from: Data(json.utf8))

        XCTAssertNil(file.smallURL)
    }

    /// Кейс: `data` есть, но это не объект (строка / массив).
    /// Ожидание: ошибка декодирования — некорректный ответ не должен молча превращаться в файл без превью.
    func test_decode_dataNotObject_throws() {
        let jsons = [
            #"{"file_id":5,"type":"image","url":"http://h/f","size":10,"filename":"a","extension":"jpg","data":"oops"}"#,
            #"{"file_id":5,"type":"image","url":"http://h/f","size":10,"filename":"a","extension":"jpg","data":[]}"#,
        ]

        for json in jsons {
            XCTAssertThrowsError(try decoder.decode(RemoteFile.self, from: Data(json.utf8)), json)
        }
    }

    /// Кейс: в JSON нет обязательного поля `url`.
    /// Ожидание: ошибка декодирования.
    func test_decode_missingRequiredField_throws() {
        let json = #"{"file_id":3,"type":"image","size":10,"filename":"a","extension":"jpg","data":{}}"#

        XCTAssertThrowsError(try decoder.decode(RemoteFile.self, from: Data(json.utf8)))
    }
}
