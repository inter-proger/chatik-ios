//
//  FormURLEncoder.swift
//  Chatik
//

import Foundation

/// Кодирует параметры в строку формата `application/x-www-form-urlencoded`.
enum FormURLEncoder {
    /// Символы, которые не нужно экранировать в ключах и значениях формы.
    private static let allowedCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._*")
        return set
    }()

    /// Собирает тело запроса вида `key1=value1&key2=value2`.
    /// Ключи сортируются для детерминированного результата, значения percent-кодируются,
    /// пробел кодируется как `+`.
    /// - Parameter parameters: параметры запроса.
    static func encode(_ parameters: [String: String]) -> String {
        parameters
            .sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
    }

    /// Percent-кодирует строку по правилам форм: пробел → `+`, остальное → `%XX`.
    private static func escape(_ string: String) -> String {
        let escaped = string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? ""
        return escaped.replacingOccurrences(of: "%20", with: "+")
    }
}
