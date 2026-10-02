//
//  ChatInputPanel.swift
//  Chatik
//

import SwiftUI

/// Панель ввода экрана переписки, связанная с `ChatViewModel`.
///
/// Вынесена из `ChatView`, чтобы состояние ввода читалось только здесь: Observation перерисовывает View,
/// в `body` которой читалось изменившееся свойство, и при наборе текста перерисовывается только панель,
/// а не весь экран с пересборкой ленты сообщений.
struct ChatInputPanel: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        MessageInputView(
            text: $viewModel.messageText,
            hint: viewModel.inputHint,
            isSending: viewModel.isSending,
            isSendEnabled: viewModel.isSendEnabled,
            onSend: viewModel.didTapSend
        )
    }
}
