//
//  AppConfig.swift
//  Chatik
//

import Foundation

/// Несекретная конфигурация приложения.
enum AppConfig {
    /// Адрес API. Задаётся `API_BASE_URL` в `Config/Base.xcconfig` (локально — в `Config/Local.xcconfig`)
    /// и попадает в Info.plist под ключом `APIBaseURL`.
    static let baseURL: URL = {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
              let url = URL(string: string) else {
            fatalError("В Info.plist нет корректного APIBaseURL — проверьте API_BASE_URL в Config/*.xcconfig")
        }
        return url
    }()
    static let licenseAgreementURL = baseURL.appending(path: "static/docs/license.pdf")
    static let privacyPolicyURL = baseURL.appending(path: "static/docs/privacy_policy.pdf")
}
