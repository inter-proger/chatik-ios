//
//  NetworkError.swift
//  Chatik
//

import Foundation

enum NetworkError: Error, Equatable {
    /// Не удалось собрать URL запроса.
    case invalidURL
    /// Ответ не является HTTP-ответом либо код вне диапазона 2xx.
    case invalidResponse(statusCode: Int?)
    /// Сервер вернул `status = 0` с кодом ошибки из API.
    case api(code: Int)
    /// Сервер вернул `status = 1`, но поле `response` отсутствует.
    case missingResponse
    /// Не удалось разобрать JSON ответа.
    case decoding(String)
    /// Ошибка транспортного уровня (нет сети, таймаут и т.п.).
    case transport(String)
}

extension NetworkError {
    /// Коды ошибок API из документации.
    enum Code {
        static let invalidLogin = 1001
        static let invalidPassword = 1002
        static let invalidName = 1003
        static let loginAlreadyTaken = 2001
        static let wrongCredentials = 2002
        static let unauthorized = 2003
    }
}
