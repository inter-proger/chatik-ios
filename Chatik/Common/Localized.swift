//
//  Localized.swift
//  Chatik
//

import Foundation

/// Точка чтения строк интерфейса. Все `XxxStrings` обращаются сюда, а не к `String(localized:)`,
/// чтобы язык приложения переключался независимо от системного.
///
/// Обращается к `DIContainer.shared` напрямую — единственное разрешённое исключение из правила
/// «сервисы только через инжекцию»: строки читаются из статических хелперов, куда инжекция невозможна.
/// Чтение `bundle` регистрируется системой Observation, поэтому View, использующие строки в `body`,
/// перерисовываются при смене языка автоматически.
enum Localized {
    /// Возвращает строку текущего языка по ключу из указанной таблицы.
    /// - Parameters:
    ///   - key: ключ в `.strings`.
    ///   - table: имя таблицы (файла `.strings` без расширения).
    @MainActor
    static func string(_ key: String, table: String) -> String {
        DIContainer.shared.localizationService.bundle.localizedString(forKey: key, value: nil, table: table)
    }

    /// Возвращает строку текущего языка с числом в нужной форме множественного числа (`.stringsdict` той же таблицы).
    /// Число подставляется с локалью языка приложения: иначе форма выбиралась бы по системному языку.
    /// - Parameters:
    ///   - key: ключ в `.stringsdict`.
    ///   - table: имя таблицы.
    ///   - count: число.
    @MainActor
    static func plural(_ key: String, table: String, count: Int) -> String {
        let localization = DIContainer.shared.localizationService
        return plural(key, table: table, count: count, bundle: localization.bundle, locale: localization.language.locale)
    }

    /// Строка с числом в нужной форме множественного числа из `.stringsdict` указанного бандла языка.
    /// - Parameters:
    ///   - key: ключ в `.stringsdict`.
    ///   - table: имя таблицы.
    ///   - count: число.
    ///   - bundle: бандл языка (`<lang>.lproj`).
    ///   - locale: локаль того же языка — по ней выбирается форма.
    static func plural(_ key: String, table: String, count: Int, bundle: Bundle, locale: Locale) -> String {
        let format = bundle.localizedString(forKey: key, value: nil, table: table)
        return String(format: format, locale: locale, count)
    }
}
