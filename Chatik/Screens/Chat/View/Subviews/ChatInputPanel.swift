//
//  ChatInputPanel.swift
//  Chatik
//

import SwiftUI

/// Панель ввода экрана переписки, связанная с `ChatViewModel`. В режиме редактирования над полем — плашка
/// с редактируемым сообщением; плашка и поле — один блок у нижнего края с общим фоном.
///
/// Вынесена из `ChatView`, чтобы состояние ввода читалось только здесь: Observation перерисовывает View,
/// в `body` которой читалось изменившееся свойство, и при наборе текста перерисовывается только панель,
/// а не весь экран с пересборкой ленты сообщений.
struct ChatInputPanel: View {
    @Bindable var viewModel: ChatViewModel
    /// Фокус поля ввода: экран снимает его по тапу по ленте, чтобы убрать клавиатуру.
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isEditing {
                MessageEditBanner(
                    text: viewModel.editBannerText,
                    isSubmitting: viewModel.isEditSubmitting,
                    onCancel: viewModel.cancelEditing
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            MessageInputView(
                text: $viewModel.messageText,
                isFocused: isFocused,
                hint: viewModel.inputHint,
                isSendEnabled: viewModel.isSendEnabled,
                isSubmitting: viewModel.isEditSubmitting,
                sendIcon: viewModel.sendButtonIcon,
                sendLabel: viewModel.sendButtonLabel,
                onSend: viewModel.didTapSend
            )
        }
        .background(.bar)
        // Включение редактирования ставит фокус в поле: правку сразу можно набирать.
        .onChange(of: viewModel.isEditing) { _, isEditing in
            guard isEditing else { return }
            isFocused.wrappedValue = true
        }
        // Запрос правки закончился (успехом или ошибкой) — клавиатура прячется. Пока он шёл, поле было только
        // для чтения, но в фокусе: клавиатура оставалась на месте.
        .onChange(of: viewModel.isEditSubmitting) { _, isSubmitting in
            guard !isSubmitting else { return }
            isFocused.wrappedValue = false
        }
    }
}
