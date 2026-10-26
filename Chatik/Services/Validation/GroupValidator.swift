//
//  GroupValidator.swift
//  Chatik
//

import Foundation

/// Ошибка поля группы.
enum GroupFieldError: Equatable {
    /// Пусто после обрезки (только для названия).
    case empty
    /// Длиннее лимита (в кодовых точках Unicode).
    case tooLong(maxLength: Int)
}

/// Проверка названия и описания группы по правилам сервера (`Request::normalizeText` в ServerAi): по краям
/// обрезаются пробелы и переводы строк, разделители Unicode (`\p{Z}`), zero-width (U+200B–U+200D), U+2060 и BOM,
/// а длина считается в кодовых точках Unicode (`mb_strlen`), а не в графемах: эмодзи из нескольких кодовых точек
/// сервер считает за несколько символов (`docs/group-chats.md`, решение 10).
enum GroupValidator {
    /// Символы, которые сервер обрезает по краям.
    private static let trimmedCharacters: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.formUnion(.init(charactersIn: "\u{200B}\u{200C}\u{200D}\u{2060}\u{FEFF}"))
        // `\p{Z}`: пробельные разделители, разделители строк и абзацев.
        set.formUnion(.init(charactersIn: "\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}"))
        return set
    }()

    /// Текст в том виде, в каком его сохранит сервер: без обрезаемых символов по краям.
    /// - Parameter text: введённый текст.
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: trimmedCharacters)
    }

    /// Длина текста по правилу сервера — в кодовых точках Unicode.
    /// - Parameter text: обрезанный текст.
    static func length(_ text: String) -> Int {
        text.unicodeScalars.count
    }

    /// Проверяет название: после обрезки от 1 до `GroupLimits.nameMaxLength` кодовых точек.
    /// - Parameter name: введённое название.
    /// - Returns: `nil` — название подходит.
    static func validateName(_ name: String) -> GroupFieldError? {
        let normalized = normalized(name)
        guard !normalized.isEmpty else { return .empty }
        guard length(normalized) <= GroupLimits.nameMaxLength else { return .tooLong(maxLength: GroupLimits.nameMaxLength) }
        return nil
    }

    /// Проверяет описание: после обрезки не длиннее `GroupLimits.descriptionMaxLength`; пустое допустимо.
    /// - Parameter description: введённое описание.
    /// - Returns: `nil` — описание подходит.
    static func validateDescription(_ description: String) -> GroupFieldError? {
        guard length(normalized(description)) <= GroupLimits.descriptionMaxLength else {
            return .tooLong(maxLength: GroupLimits.descriptionMaxLength)
        }
        return nil
    }
}
