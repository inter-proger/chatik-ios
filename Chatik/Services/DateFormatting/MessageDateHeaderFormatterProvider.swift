//
//  MessageDateHeaderFormatterProvider.swift
//  Chatik
//

import Foundation

/// Выдаёт форматтер заголовков для языка: реализацию для этого языка, если она есть, иначе общую на ICU.
protocol MessageDateHeaderFormatterProviding: Sendable {
    /// Форматтер заголовков дней.
    /// - Parameters:
    ///   - locale: язык приложения.
    ///   - calendar: календарь с часовым поясом устройства.
    func formatter(locale: Locale, calendar: Calendar) -> any MessageDateHeaderFormatting
}

/// Выбирает реализацию заголовков по коду языка. Чтобы добавить реализацию для языка, достаточно дописать её
/// в `languageSpecific` — код экранов не меняется.
struct MessageDateHeaderFormatterProvider: MessageDateHeaderFormatterProviding {
    typealias Factory = @Sendable (Locale, Calendar) -> any MessageDateHeaderFormatting

    /// Реализации для отдельных языков по коду языка (`Locale.Language.LanguageCode`).
    let languageSpecific: [String: Factory]

    /// Набор приложения: русский — `RussianMessageDateHeaderFormatter`, остальные — `LocaleMessageDateHeaderFormatter`.
    static let `default` = MessageDateHeaderFormatterProvider(languageSpecific: [
        "ru": { _, calendar in RussianMessageDateHeaderFormatter(calendar: calendar) },
    ])

    /// Форматтер для языка локали; регион не учитывается.
    /// - Parameters:
    ///   - locale: язык приложения.
    ///   - calendar: календарь с часовым поясом устройства.
    func formatter(locale: Locale, calendar: Calendar) -> any MessageDateHeaderFormatting {
        guard let code = locale.language.languageCode?.identifier, let factory = languageSpecific[code] else {
            return LocaleMessageDateHeaderFormatter(locale: locale, calendar: calendar)
        }
        return factory(locale, calendar)
    }
}
