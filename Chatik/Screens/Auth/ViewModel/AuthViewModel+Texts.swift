//
//  AuthViewModel+Texts.swift
//  Chatik
//

import Foundation

/// Тексты экрана, зависящие от режима: заголовок, кнопка, ссылки.
extension AuthViewModel {
    /// Служебный URL, по которому в тексте `switchModeText` распознаётся ссылка переключения режима.
    static let switchModeURL = URL(string: "chatik://auth/switch-mode")!

    var title: String {
        isSignup ? AuthStrings.titleSignup : AuthStrings.titleLogin
    }

    var primaryButtonTitle: String {
        isSignup ? AuthStrings.buttonSignup : AuthStrings.buttonLogin
    }

    /// Текст вида «Уже зарегистрированы? Войти», где действие — inline-ссылка на `switchModeURL`.
    var switchModeText: AttributedString {
        let format = isSignup ? AuthStrings.switchToLoginFormat : AuthStrings.switchToSignupFormat
        return Self.makeMarkdownText(format: format, urls: [Self.switchModeURL])
    }

    /// Текст соглашения с кликабельными ссылками на лицензию и политику конфиденциальности.
    var agreementText: AttributedString {
        Self.makeMarkdownText(
            format: AuthStrings.agreementFormat,
            urls: [AppConfig.licenseAgreementURL, AppConfig.privacyPolicyURL]
        )
    }

    /// Собирает атрибутированный текст из локализованного markdown-шаблона, подставляя URL ссылок.
    /// - Parameters:
    ///   - format: шаблон с `%@` на месте адресов ссылок.
    ///   - urls: адреса в порядке следования плейсхолдеров.
    private static func makeMarkdownText(format: String, urls: [URL]) -> AttributedString {
        let markdown = String(format: format, arguments: urls.map(\.absoluteString))
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}
