//
//  SingleLineText.swift
//  Chatik
//

import Foundation

/// Сведение текста сообщения в одну строку для превью: строка списка чатов, уведомление о новом сообщении.
enum SingleLineText {
    /// Текст в одну строку: начало обрезано по `MessageTextValidator.trimmedCharacters` (как при решении, пуст ли
    /// черновик), берутся первые `maxLength` символов, переводы строк и повторяющиеся пробельные символы заменены
    /// одним пробелом, края обрезаны. Иначе в одной строке был бы виден только первый абзац, а длинный текст
    /// обрабатывался бы целиком при каждой пересборке.
    /// - Parameters:
    ///   - text: исходный текст.
    ///   - maxLength: сколько первых символов после обрезки начала обрабатывается.
    /// - Returns: текст в одну строку; пустая строка, если в тексте только пробельные символы.
    static func make(_ text: String, maxLength: Int) -> String {
        let trimmed = MessageTextValidator.trimmedCharacters
        return text.drop { $0.unicodeScalars.allSatisfy(trimmed.contains) }
            .prefix(maxLength)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: trimmed)
    }
}
