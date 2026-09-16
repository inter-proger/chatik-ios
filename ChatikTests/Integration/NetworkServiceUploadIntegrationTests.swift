//
//  NetworkServiceUploadIntegrationTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

/// Интеграционные проверки загрузки против реального сервера. Выполняются только при заданной
/// переменной окружения `CHATIK_SERVER_URL` (например, `http://localhost:8080`; из `xcodebuild` — с префиксом
/// `TEST_RUNNER_`, в схеме Xcode — в Arguments → Environment Variables), иначе пропускаются:
/// `URLProtocol`-стаб не генерирует прогресс отправки, а по умолчанию тесты не должны зависеть от сервера.
final class NetworkServiceUploadIntegrationTests: XCTestCase {
    /// Кейс: multipart-загрузка файла 2 МБ через `URLSession.shared` (как в приложении) с делегатом прогресса уровня задачи.
    /// Ожидание: прогресс сообщён хотя бы раз и последнее значение — 1; ответ сервера — `api(2003)` (без cookie сессии).
    func test_upload_viaSharedSession_reportsProgress() async throws {
        let baseURL = try serverURL()
        let sut = NetworkService(session: .shared, baseURL: baseURL)
        let fileURL = try TemporaryFile.make(Data(count: 2_000_000), fileExtension: "jpg")
        defer { TemporaryFile.remove([fileURL]) }
        let file = MultipartFile(fieldName: "file", filename: "a.jpg", mimeType: "image/jpeg", fileURL: fileURL)
        let recorder = ProgressRecorder()

        do {
            let _: RemoteFile = try await sut.upload(FilesEndpoint.uploadImage, file: file, onProgress: { recorder.append($0) })
            XCTFail("Expected api(2003) without session cookie")
        } catch {
            XCTAssertEqual(error as? NetworkError, .api(code: NetworkError.Code.unauthorized))
        }
        XCTAssertFalse(recorder.values.isEmpty)
        XCTAssertEqual(recorder.values.last, 1)
    }

    /// Адрес сервера из окружения; без него тест пропускается.
    private func serverURL() throws -> URL {
        let value = ProcessInfo.processInfo.environment["CHATIK_SERVER_URL"]
        try XCTSkipUnless(value != nil, "CHATIK_SERVER_URL не задан — интеграционный тест пропущен")
        return try XCTUnwrap(value.flatMap(URL.init(string:)))
    }
}
