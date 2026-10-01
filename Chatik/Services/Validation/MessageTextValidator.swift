//
//  MessageTextValidator.swift
//  Chatik
//

import Foundation

protocol MessageTextValidatorProtocol {
    /// Проверяет текст сообщения: после обрезки пробелов и переводов строк — от 1 до 4096 символов в счёте сервера.
    func validate(_ text: String) -> MessageTextValidationError?
}

final class MessageTextValidator: MessageTextValidatorProtocol {
    /// Лимит длины на стороне сервера: при превышении `/messages/send` и `/messages/edit` отвечают кодом 1005.
    static let maxLength = 4096

    /// Проверяет текст сообщения так же, как сервер: краевые пробелы и переводы строк отсекаются.
    ///
    /// Длина считается в Unicode code points, а не в `Character`: сервер считает символы по code points,
    /// а `String.count` — по графемам. Эмодзи с модификаторами, флаги и буквы с комбинируемыми диакритиками —
    /// одна графема, но несколько code points: со счётом по графемам текст прошёл бы проверку на клиенте,
    /// а сервер отклонил бы его с кодом 1005.
    /// - Parameter text: введённый текст.
    /// - Returns: `nil`, если текст можно отправить.
    func validate(_ text: String) -> MessageTextValidationError? {
        let length = text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
        guard length > 0 else { return .empty }
        guard length <= Self.maxLength else { return .tooLong(maxLength: Self.maxLength) }
        return nil
    }
}
