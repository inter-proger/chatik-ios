//
//  ErrorMessagesTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class ErrorMessagesTests: XCTestCase {
    /// Кейс: известные коды ошибок API.
    /// Ожидание: каждому коду соответствует свой локализованный текст.
    func test_message_knownAPICodes_returnSpecificTexts() {
        let cases: [(code: Int, expected: String)] = [
            (NetworkError.Code.invalidLogin, CommonStrings.errorInvalidLogin),
            (NetworkError.Code.invalidPassword, CommonStrings.errorInvalidPassword),
            (NetworkError.Code.invalidName, CommonStrings.errorInvalidName),
            (NetworkError.Code.invalidParameters, CommonStrings.errorInvalidParameters),
            (NetworkError.Code.invalidText, CommonStrings.errorInvalidText),
            (NetworkError.Code.loginAlreadyTaken, CommonStrings.errorLoginAlreadyTaken),
            (NetworkError.Code.wrongCredentials, CommonStrings.errorWrongCredentials),
            (NetworkError.Code.unauthorized, CommonStrings.errorUnauthorized),
            (NetworkError.Code.fileMissing, CommonStrings.errorFileMissing),
            (NetworkError.Code.fileTooLarge, CommonStrings.errorFileTooLarge),
            (NetworkError.Code.fileNotImage, CommonStrings.errorFileNotImage),
            (NetworkError.Code.fileNotFound, CommonStrings.errorFileNotFound),
            (NetworkError.Code.fileSaveFailed, CommonStrings.errorFileSaveFailed),
            (NetworkError.Code.userNotFound, CommonStrings.errorUserNotFound),
            (NetworkError.Code.conversationWithSelf, CommonStrings.errorConversationWithSelf),
            (NetworkError.Code.conversationNotFound, CommonStrings.errorConversationNotFound),
            (NetworkError.Code.invalidDescription, CommonStrings.errorInvalidDescription),
            (NetworkError.Code.notGroup, CommonStrings.errorNotGroup),
            (NetworkError.Code.groupOwnerOnly, CommonStrings.errorGroupOwnerOnly),
            (NetworkError.Code.groupMemberLimitReached, CommonStrings.errorGroupMemberLimit),
            (NetworkError.Code.alreadyGroupMember, CommonStrings.errorAlreadyGroupMember),
            (NetworkError.Code.notGroupMember, CommonStrings.errorNotGroupMember),
            (NetworkError.Code.groupOwnerNotApplicable, CommonStrings.errorGroupOwnerNotApplicable),
            (NetworkError.Code.messageNotFound, CommonStrings.errorMessageNotFound),
            (NetworkError.Code.messageBlockNotFound, CommonStrings.errorMessageBlockNotFound),
            (NetworkError.Code.messageEditForbidden, CommonStrings.errorMessageEditForbidden),
            (NetworkError.Code.internalServerError, CommonStrings.errorInternalServer),
        ]

        for testCase in cases {
            XCTAssertEqual(ErrorMessages.message(for: NetworkError.api(code: testCase.code)), testCase.expected, "\(testCase.code)")
        }
    }

    /// Кейс: транспортная ошибка.
    /// Ожидание: текст про отсутствие соединения.
    func test_message_transportError_returnsNoConnection() {
        XCTAssertEqual(ErrorMessages.message(for: NetworkError.transport(URLError(.notConnectedToInternet))), CommonStrings.errorNoConnection)
    }

    /// Кейс: локальная проверка размера файла отклонила загрузку.
    /// Ожидание: тот же текст, что и для серверного кода 3002.
    func test_message_fileTooLarge_returnsFileTooLargeText() {
        XCTAssertEqual(ErrorMessages.message(for: FilesServiceError.fileTooLarge(maxSize: 1)), CommonStrings.errorFileTooLarge)
    }

    /// Кейс: неизвестный код API, ошибки разбора / формата ответа, ошибка программиста, ошибки файлов
    /// на диске, не-`NetworkError`.
    /// Ожидание: общий текст «что-то пошло не так».
    func test_message_otherErrors_returnUnknown() {
        let errors: [Error] = [
            NetworkError.api(code: 9999),
            NetworkError.decoding("bad json"),
            NetworkError.missingResponse,
            NetworkError.invalidResponse(statusCode: 500),
            NetworkError.unsupportedMethod(.get),
            NetworkError.fileAccess("no such file"),
            FilesServiceError.fileUnreadable,
            URLError(.badURL),
        ]

        for error in errors {
            XCTAssertEqual(ErrorMessages.message(for: error), CommonStrings.errorUnknown, "\(error)")
        }
    }
}
