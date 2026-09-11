//
//  AuthModeSwitchView.swift
//  Chatik
//

import SwiftUI

/// Строка вида «Уже зарегистрированы? Войти», где действие — inline-ссылка внутри текста.
/// Ссылка может стоять в любом месте, состоять из нескольких слов и переноситься вместе с текстом.
struct AuthModeSwitchView: View {
    let text: AttributedString
    let actionURL: URL
    let onTap: () -> Void

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .environment(\.openURL, OpenURLAction(handler: handleURL))
    }

    /// Перехватывает тап по служебной ссылке переключения режима; остальные URL отдаёт системе.
    /// - Parameter url: адрес нажатой ссылки.
    private func handleURL(_ url: URL) -> OpenURLAction.Result {
        guard url == actionURL else { return .systemAction }
        onTap()
        return .handled
    }
}

#Preview {
    VStack(spacing: 24) {
        AuthModeSwitchView(
            text: try! AttributedString(markdown: "Уже зарегистрированы? **[Войти](chatik://switch)**"),
            actionURL: URL(string: "chatik://switch")!,
            onTap: {}
        )
        AuthModeSwitchView(
            text: try! AttributedString(markdown: "**[Создать новый аккаунт](chatik://switch)**, если у вас его ещё нет — это займёт меньше минуты"),
            actionURL: URL(string: "chatik://switch")!,
            onTap: {}
        )
    }
    .padding()
}
