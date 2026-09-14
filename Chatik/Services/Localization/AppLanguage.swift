//
//  AppLanguage.swift
//  Chatik
//

import Foundation

/// Языки интерфейса, поддерживаемые приложением.
enum AppLanguage: String, CaseIterable, Identifiable {
    case ru
    case en

    /// Язык по умолчанию, если системный не поддерживается.
    static let fallback: AppLanguage = .en

    var id: String { rawValue }

    /// Название языка на нём самом — не локализуется намеренно, чтобы пользователь узнал свой язык в любом интерфейсе.
    var displayName: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    /// Определяет язык по системным настройкам: первый предпочитаемый язык, если он поддерживается, иначе `fallback`.
    /// - Parameter preferredLanguages: список предпочитаемых языков системы (`Locale.preferredLanguages`).
    static func systemDefault(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard let first = preferredLanguages.first,
              let code = Locale(identifier: first).language.languageCode?.identifier,
              let language = AppLanguage(rawValue: code) else {
            return fallback
        }
        return language
    }
}
