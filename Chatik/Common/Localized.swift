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
}
