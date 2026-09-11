//
//  AuthViewModel.swift
//  Chatik
//

import Foundation

/// Состояние экрана регистрации / входа. Сетевая логика будет добавлена отдельно.
@MainActor
@Observable
final class AuthViewModel {
    private(set) var mode: AuthMode

    var name = ""
    var login = ""
    var password = ""
    var isPasswordVisible = false

    private let authService: AuthServiceProtocol
    private let router: AuthRouter

    init(mode: AuthMode = .signup, authService: AuthServiceProtocol, router: AuthRouter) {
        self.mode = mode
        self.authService = authService
        self.router = router
    }

    var isSignup: Bool { mode == .signup }

    var title: String {
        isSignup ? AuthStrings.titleSignup : AuthStrings.titleLogin
    }

    var primaryButtonTitle: String {
        isSignup ? AuthStrings.buttonSignup : AuthStrings.buttonLogin
    }

    /// Служебный URL, по которому в тексте `switchModeText` распознаётся ссылка переключения режима.
    static let switchModeURL = URL(string: "chatik://auth/switch-mode")!

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

    /// Переключает экран между режимами регистрации и входа.
    func switchMode() {
        mode = mode.toggled
    }

    /// Переключает отображение пароля между секьюрным и открытым текстом.
    func togglePasswordVisibility() {
        isPasswordVisible.toggle()
    }

    /// Обработчик кнопки «Регистрация» / «Вход». Логика будет добавлена отдельно.
    func didTapPrimaryButton() {
        // TODO: вызов authService.signup / authService.login и переход через router.
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
