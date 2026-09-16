//
//  UploadProgressDelegateTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class UploadProgressDelegateTests: XCTestCase {
    private let session = URLSession.shared
    private var task: URLSessionTask!

    override func setUp() {
        super.setUp()
        task = session.dataTask(with: URL(string: "http://localhost")!)
    }

    /// Кейс: сессия сообщает об отправленных байтах при известном размере тела.
    /// Ожидание: обработчик получает долю отправленного — отношение отправленных байтов к ожидаемым.
    func test_didSendBodyData_reportsFractionOfExpected() {
        let cases: [(sent: Int64, expected: Int64, progress: Double)] = [
            (0, 200, 0),
            (50, 200, 0.25),
            (200, 200, 1),
        ]

        for testCase in cases {
            let recorder = ProgressRecorder()
            let sut = UploadProgressDelegate(onProgress: { recorder.append($0) })

            sut.urlSession(session, task: task, didSendBodyData: 0, totalBytesSent: testCase.sent, totalBytesExpectedToSend: testCase.expected)

            XCTAssertEqual(recorder.values, [testCase.progress], "\(testCase)")
        }
    }

    /// Кейс: размер тела неизвестен (`totalBytesExpectedToSend <= 0`).
    /// Ожидание: обработчик не вызывается — долю посчитать нельзя.
    func test_didSendBodyData_unknownTotal_doesNotReport() {
        let totals: [Int64] = [
            0,
            NSURLSessionTransferSizeUnknown,
        ]

        for total in totals {
            let recorder = ProgressRecorder()
            let sut = UploadProgressDelegate(onProgress: { recorder.append($0) })

            sut.urlSession(session, task: task, didSendBodyData: 10, totalBytesSent: 10, totalBytesExpectedToSend: total)

            XCTAssertTrue(recorder.values.isEmpty, "\(total)")
        }
    }

    /// Кейс: отправлено больше байтов, чем ожидалось.
    /// Ожидание: доля ограничена единицей.
    func test_didSendBodyData_overshoot_clampsToOne() {
        let recorder = ProgressRecorder()
        let sut = UploadProgressDelegate(onProgress: { recorder.append($0) })

        sut.urlSession(session, task: task, didSendBodyData: 0, totalBytesSent: 300, totalBytesExpectedToSend: 200)

        XCTAssertEqual(recorder.values, [1])
    }
}
