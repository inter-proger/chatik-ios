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
    /// Поле было в фокусе, когда начался запрос правки: на время запроса поле недоступно и теряет фокус,
    /// а после запроса фокус возвращается — правку можно продолжить набирать без лишнего тапа.
    @State private var restoresFocusAfterSubmit = false

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
                onSend: didTapSend
            )
        }
        .background(.bar)
        // Включение редактирования ставит фокус в поле: правку сразу можно набирать.
        .onChange(of: viewModel.isEditing) { _, isEditing in
            guard isEditing else { return }
            isFocused.wrappedValue = true
        }
        .onChange(of: viewModel.isEditSubmitting) { _, isSubmitting in
            guard !isSubmitting, restoresFocusAfterSubmit else { return }
            restoresFocusAfterSubmit = false
            isFocused.wrappedValue = true
        }
    }

    /// Кнопка под полем ввода. Фокус запоминается до нажатия: в режиме редактирования запрос сделает поле
    /// недоступным, и оно потеряет фокус.
    private func didTapSend() {
        restoresFocusAfterSubmit = viewModel.isEditing && isFocused.wrappedValue
        viewModel.didTapSend()
        guard !viewModel.isEditSubmitting else { return }
        restoresFocusAfterSubmit = false
    }
}
