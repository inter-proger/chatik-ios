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
    /// Фокус поля ввода: экран снимает его по тапу по ленте, чтобы убрать клавиатуру.
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        MessageInputView(
            text: $viewModel.messageText,
            isFocused: isFocused,
            hint: viewModel.inputHint,
            isSendEnabled: viewModel.isSendEnabled,
            onSend: viewModel.didTapSend
        )
    }
}
