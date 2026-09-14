//
//  LocalizationService.swift
//  Chatik
//

import Foundation

@MainActor
protocol LocalizationServiceProtocol: AnyObject {
    /// Текущий язык интерфейса.
    var language: AppLanguage { get }
    /// Bundle с `.strings` текущего языка — из него читаются все строки интерфейса.
    var bundle: Bundle { get }

    /// Восстанавливает сохранённый пользователем язык при старте приложения.
    func restore() async
    /// Применяет выбранный язык и запоминает его.
    func setLanguage(_ language: AppLanguage) async
}

/// Управляет языком интерфейса независимо от системного: до выбора — системный язык
/// (или `AppLanguage.fallback`), после — сохранённый в `UserDefaults`.
@MainActor
@Observable
final class LocalizationService: LocalizationServiceProtocol {
    private(set) var language: AppLanguage
    private(set) var bundle: Bundle

    private let userDefaultsService: UserDefaultsServiceProtocol

    /// - Parameters:
    ///   - userDefaultsService: хранилище выбранного языка.
    ///   - systemLanguage: язык до восстановления сохранённого; по умолчанию определяется по настройкам системы.
    init(userDefaultsService: UserDefaultsServiceProtocol, systemLanguage: AppLanguage = .systemDefault()) {
        self.userDefaultsService = userDefaultsService
        language = systemLanguage
        bundle = Self.bundle(for: systemLanguage)
    }

    /// Применяет язык из `UserDefaults`, если пользователь его выбирал.
    func restore() async {
        guard let saved = await userDefaultsService.language() else { return }
        apply(saved)
    }

    /// Применяет язык и сохраняет выбор.
    /// - Parameter language: выбранный пользователем язык.
    func setLanguage(_ language: AppLanguage) async {
        apply(language)
        await userDefaultsService.setLanguage(language)
    }

    /// Обновляет текущий язык и bundle строк.
    private func apply(_ language: AppLanguage) {
        guard language != self.language else { return }
        self.language = language
        bundle = Self.bundle(for: language)
    }

    /// Возвращает bundle директории `<language>.lproj`; если её нет — основной bundle.
    /// - Parameter language: язык, для которого нужен bundle.
    private static func bundle(for language: AppLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
