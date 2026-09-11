//
//  AppConfig.swift
//  Chatik
//

import Foundation

/// Несекретная конфигурация приложения.
enum AppConfig {
    static let baseURL = URL(string: "http://localhost:8080")!
    static let licenseAgreementURL = URL(string: "http://localhost:8080/static/docs/license.pdf")!
    static let privacyPolicyURL = URL(string: "http://localhost:8080/static/docs/privacy_policy.pdf")!
}
