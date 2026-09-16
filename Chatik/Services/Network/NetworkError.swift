//
//  NetworkError.swift
//  Chatik
//

import Foundation

enum NetworkError: Error {
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
    /// Ошибка транспортного уровня (нет сети, таймаут, отмена и т.п.) — исходная `URLError` сохраняется целиком.
    case transport(URLError)
    /// Эндпоинт с таким HTTP-методом нельзя отправить выбранным способом (например, `upload` требует POST).
    /// Ошибка программиста: запрос на сервер не уходит.
    case unsupportedMethod(HTTPMethod)
    /// Не удалось собрать тело загрузки на диске: загружаемый файл не прочитан или временный файл не записан.
    /// Запрос на сервер не уходит.
    case fileAccess(String)
}

extension NetworkError: Equatable {
    /// Транспортные ошибки равны при одинаковом `URLError.Code`: `userInfo` (задача, URL) для сравнения не важен.
    static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL), (.missingResponse, .missingResponse):
            return true
        case let (.invalidResponse(lhsCode), .invalidResponse(rhsCode)):
            return lhsCode == rhsCode
        case let (.api(lhsCode), .api(rhsCode)):
            return lhsCode == rhsCode
        case let (.decoding(lhsMessage), .decoding(rhsMessage)):
            return lhsMessage == rhsMessage
        case let (.transport(lhsError), .transport(rhsError)):
            return lhsError.code == rhsError.code
        case let (.unsupportedMethod(lhsMethod), .unsupportedMethod(rhsMethod)):
            return lhsMethod == rhsMethod
        case let (.fileAccess(lhsMessage), .fileAccess(rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
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
        static let fileMissing = 3001
        static let fileTooLarge = 3002
        static let fileNotImage = 3003
        static let fileNotFound = 3004
        static let fileSaveFailed = 3005
    }
}
