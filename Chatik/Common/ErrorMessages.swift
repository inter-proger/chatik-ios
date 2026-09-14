//
//  ErrorMessages.swift
//  Chatik
//

import Foundation

/// Преобразует ошибки сервисов в текст для показа пользователю.
enum ErrorMessages {
    /// Возвращает понятное пользователю сообщение об ошибке.
    /// - Parameter error: любая ошибка; для не-`NetworkError` возвращается общий текст.
    static func message(for error: Error) -> String {
        guard let networkError = error as? NetworkError else { return CommonStrings.errorUnknown }
        switch networkError {
        case .api(let code): return message(forAPICode: code)
        case .transport: return CommonStrings.errorNoConnection
        case .invalidURL, .invalidResponse, .missingResponse, .decoding: return CommonStrings.errorUnknown
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
        default: return CommonStrings.errorUnknown
        }
    }
}
