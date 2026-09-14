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
    /// Подстановка текстовая, а не через `String(format:)`: ошибка в переводе (потерянный или лишний
    /// плейсхолдер) не должна ронять приложение — она видна в UI и ловится тестом на `.strings`.
    /// - Parameters:
    ///   - format: шаблон с позиционными плейсхолдерами `%1$@`, `%2$@`, … на месте адресов ссылок.
    ///   - urls: адреса; `urls[i]` подставляется вместо `%<i+1>$@`.
    private static func makeMarkdownText(format: String, urls: [URL]) -> AttributedString {
        let markdown = urls.enumerated().reduce(into: format) { markdown, item in
            markdown = markdown.replacingOccurrences(of: "%\(item.offset + 1)$@", with: item.element.absoluteString)
        }
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}
