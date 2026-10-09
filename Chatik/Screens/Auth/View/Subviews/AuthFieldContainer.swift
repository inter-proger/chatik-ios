//
//  AuthFieldContainer.swift
//  Chatik
//

import SwiftUI

/// Обёртка поля ввода экрана авторизации: фон, рамка ошибки и текст подсказки / ошибки под полем.
/// Тап по любому месту серого блока, а не только по самому полю, вызывает `onTap` — он ставит фокус на поле.
struct AuthFieldContainer<Content: View>: View {
    let state: AuthFieldState
    let onTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture(perform: onTap)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.red, lineWidth: 1.5)
                        .opacity(state.isError ? 1 : 0)
                }

            if let message = state.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(state.isError ? Color.red : Color.secondary)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: state)
    }
}
