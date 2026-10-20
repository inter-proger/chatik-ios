//
//  DebugLoginView.swift
//  Chatik
//

#if DEBUG
import SwiftUI

/// Стартовый экран debug-входа по аргументам запуска. Намеренно не похож на splash — без логотипа и названия:
/// по нему видно, что запуск идёт по debug-сценарию. Состояние и действие принадлежат `AppRouter`.
struct DebugLoginView: View {
    let state: DebugLoginState
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            switch state {
            case .inProgress(let login):
                progress(login: login)
            case .failed(let message):
                failure(message: message)
            }
        }
    }

    /// Индикатор входа с логином, если он известен.
    /// - Parameter login: логин из аргументов запуска.
    private func progress(login: String?) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            if let login {
                Text(DebugLoginStrings.progress(login: login))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Текст ошибки и кнопка перехода к обычному старту.
    /// - Parameter message: текст ошибки входа или разбора аргументов.
    private func failure(message: String) -> some View {
        VStack(spacing: 16) {
            Text(DebugLoginStrings.title)
                .font(.headline)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(DebugLoginStrings.skip, action: onSkip)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}

#Preview("Вход") {
    DebugLoginView(state: .inProgress(login: "anna_smirnova"), onSkip: {})
}

#Preview("Ошибка") {
    DebugLoginView(state: .failed(message: "Неверный пароль"), onSkip: {})
}
#endif
