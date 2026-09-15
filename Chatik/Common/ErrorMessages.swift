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
        case .invalidURL, .invalidResponse, .missingResponse, .decoding, .unsupportedMethod: return CommonStrings.errorUnknown
        }
    }

    /// Сопоставляет код ошибки API с текстом. Неизвестный код — общий текст.
    /// - Parameter code: код из поля `errorCode` ответа сервера.
    private static func message(forAPICode code: Int) -> String {
        switch code {
        case NetworkError.Code.invalidLogin: return CommonStrings.errorInvalidLogin
        case NetworkError.Code.invalidPassword: return CommonStrings.errorInvalidPassword
        case NetworkError.Code.invalidName: return CommonStrings.errorInvalidName
        case NetworkError.Code.loginAlreadyTaken: return CommonStrings.errorLoginAlreadyTaken
        case NetworkError.Code.wrongCredentials: return CommonStrings.errorWrongCredentials
        case NetworkError.Code.unauthorized: return CommonStrings.errorUnauthorized
        case NetworkError.Code.fileMissing: return CommonStrings.errorFileMissing
        case NetworkError.Code.fileTooLarge: return CommonStrings.errorFileTooLarge
        case NetworkError.Code.fileNotImage: return CommonStrings.errorFileNotImage
        case NetworkError.Code.fileNotFound: return CommonStrings.errorFileNotFound
        case NetworkError.Code.fileSaveFailed: return CommonStrings.errorFileSaveFailed
        default: return CommonStrings.errorUnknown
        }
    }
}
