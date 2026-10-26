//
//  ErrorMessages.swift
//  Chatik
//

import Foundation

/// Преобразует ошибки сервисов в текст для показа пользователю.
@MainActor
enum ErrorMessages {
    /// Возвращает понятное пользователю сообщение об ошибке.
    /// - Parameter error: любая ошибка; для неизвестных типов возвращается общий текст.
    static func message(for error: Error) -> String {
        switch error {
        case let networkError as NetworkError: return message(for: networkError)
        case FilesServiceError.fileTooLarge: return CommonStrings.errorFileTooLarge
        default: return CommonStrings.errorUnknown
        }
    }

    /// Сопоставляет ошибку сетевого слоя с текстом.
    /// - Parameter error: ошибка `NetworkService`.
    private static func message(for error: NetworkError) -> String {
        switch error {
        case .api(let code): return message(forAPICode: code)
        case .transport: return CommonStrings.errorNoConnection
        case .invalidURL, .invalidResponse, .missingResponse, .decoding, .unsupportedMethod, .fileAccess: return CommonStrings.errorUnknown
        }
    }

    /// Сопоставляет код ошибки API с текстом. Неизвестный код — общий текст.
    /// - Parameter code: код из поля `errorCode` ответа сервера.
    private static func message(forAPICode code: Int) -> String {
        switch code {
        case NetworkError.Code.invalidLogin: return CommonStrings.errorInvalidLogin
        case NetworkError.Code.invalidPassword: return CommonStrings.errorInvalidPassword
        case NetworkError.Code.invalidName: return CommonStrings.errorInvalidName
        case NetworkError.Code.invalidParameters: return CommonStrings.errorInvalidParameters
        case NetworkError.Code.invalidText: return CommonStrings.errorInvalidText
        case NetworkError.Code.loginAlreadyTaken: return CommonStrings.errorLoginAlreadyTaken
        case NetworkError.Code.wrongCredentials: return CommonStrings.errorWrongCredentials
        case NetworkError.Code.unauthorized: return CommonStrings.errorUnauthorized
        case NetworkError.Code.fileMissing: return CommonStrings.errorFileMissing
        case NetworkError.Code.fileTooLarge: return CommonStrings.errorFileTooLarge
        case NetworkError.Code.fileNotImage: return CommonStrings.errorFileNotImage
        case NetworkError.Code.fileNotFound: return CommonStrings.errorFileNotFound
        case NetworkError.Code.fileSaveFailed: return CommonStrings.errorFileSaveFailed
        case NetworkError.Code.userNotFound: return CommonStrings.errorUserNotFound
        case NetworkError.Code.conversationWithSelf: return CommonStrings.errorConversationWithSelf
        case NetworkError.Code.conversationNotFound: return CommonStrings.errorConversationNotFound
        case NetworkError.Code.invalidDescription: return CommonStrings.errorInvalidDescription
        case NetworkError.Code.notGroup: return CommonStrings.errorNotGroup
        case NetworkError.Code.groupOwnerOnly: return CommonStrings.errorGroupOwnerOnly
        case NetworkError.Code.groupMemberLimitReached: return CommonStrings.errorGroupMemberLimit
        case NetworkError.Code.alreadyGroupMember: return CommonStrings.errorAlreadyGroupMember
        case NetworkError.Code.notGroupMember: return CommonStrings.errorNotGroupMember
        case NetworkError.Code.groupOwnerNotApplicable: return CommonStrings.errorGroupOwnerNotApplicable
        case NetworkError.Code.messageNotFound: return CommonStrings.errorMessageNotFound
        case NetworkError.Code.messageBlockNotFound: return CommonStrings.errorMessageBlockNotFound
        case NetworkError.Code.messageEditForbidden: return CommonStrings.errorMessageEditForbidden
        case NetworkError.Code.internalServerError: return CommonStrings.errorInternalServer
        default: return CommonStrings.errorUnknown
        }
    }
}
