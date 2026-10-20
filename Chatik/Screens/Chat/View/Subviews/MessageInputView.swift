//
//  MessageInputView.swift
//  Chatik
//

import SwiftUI

/// Панель ввода сообщения: многострочное поле и кнопка отправки. Отправка не блокирует ввод: сообщение сразу
/// уходит в ленту, а поле очищается для следующего. Сохранение правки блокирует: пока идёт запрос, поле только
/// для чтения (текст правки должен совпадать с отправленным), а на месте значка кнопки — индикатор того же размера.
///
/// Только для чтения — не `disabled`: недоступное поле теряет фокус, и клавиатура уехала бы на время запроса.
/// Поле остаётся в фокусе и показывает локальную копию текста (`fieldText`): набранное во время запроса в модель
/// не попадает, а копия откатывается к тексту модели. Отбросить изменение прямо в привязке нельзя — многострочное
/// поле не перерисовывается, если значение привязки не изменилось, и показывает набранное.
struct MessageInputView: View {
    @Binding var text: String
    /// Фокус поля ввода — им управляет экран (например, убирает клавиатуру по тапу по ленте).
    var isFocused: FocusState<Bool>.Binding
    /// Подсказка под полем (например, о превышении длины); `nil` — подсказки нет.
    let hint: String?
    let isSendEnabled: Bool
    /// Идёт запрос правки: поле только для чтения, на кнопке индикатор.
    let isSubmitting: Bool
    /// Значок кнопки: отправка или сохранение правки.
    let sendIcon: String
    /// Подпись кнопки для VoiceOver; `nil` — «Отправить».
    let sendLabel: String?
    let onSend: () -> Void

    /// Текст, который показывает поле: копия `text`, изменения переносятся в модель, если не идёт запрос.
    @State private var fieldText: String

    /// - Parameters:
    ///   - text: текст поля в модели.
    ///   - isFocused: фокус поля ввода.
    ///   - hint: подсказка под полем.
    ///   - isSendEnabled: доступна ли кнопка.
    ///   - isSubmitting: идёт запрос правки — поле только для чтения.
    ///   - sendIcon: значок кнопки.
    ///   - sendLabel: подпись кнопки для VoiceOver; `nil` — «Отправить».
    ///   - onSend: нажата кнопка.
    init(
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        hint: String?,
        isSendEnabled: Bool,
        isSubmitting: Bool = false,
        sendIcon: String = "arrow.up.circle.fill",
        sendLabel: String? = nil,
        onSend: @escaping () -> Void
    ) {
        _text = text
        self.isFocused = isFocused
        self.hint = hint
        self.isSendEnabled = isSendEnabled
        self.isSubmitting = isSubmitting
        self.sendIcon = sendIcon
        self.sendLabel = sendLabel
        self.onSend = onSend
        _fieldText = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 8) {
                textField
                sendButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Поле ввода, растущее до пяти строк.
    private var textField: some View {
        TextField(ChatStrings.inputPlaceholder, text: $fieldText, axis: .vertical)
            .lineLimit(1...5)
            .focused(isFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            // Модель → поле: подстановка черновика или правки, очистка после отправки.
            .onChange(of: text) { _, newText in
                guard newText != fieldText else { return }
                fieldText = newText
            }
            .onChange(of: fieldText) { _, newText in
                fieldDidChange(newText)
            }
    }

    /// Поле → модель: набранное переносится в модель, а во время запроса откатывается к тексту модели. Откат —
    /// отдельным обновлением, а не в этом же: изменение и откат в одном обновлении SwiftUI склеивает, значение
    /// состояния не меняется, и поле продолжает показывать набранное (проверено: удаление символа оставалось в поле).
    /// Цена — набранный символ виден на экране 1–3 кадра.
    /// - Parameter newText: текст поля.
    private func fieldDidChange(_ newText: String) {
        guard newText != text else { return }
        guard isSubmitting else {
            text = newText
            return
        }
        Task { @MainActor in fieldText = text }
    }

    /// Кнопка отправки или сохранения правки. Во время запроса значок скрыт прозрачностью, а не убран: размер
    /// кнопки не меняется.
    private var sendButton: some View {
        Button(action: onSend) {
            Image(systemName: sendIcon)
                .font(.system(size: 32))
                .opacity(isSubmitting ? 0 : 1)
                .overlay {
                    if isSubmitting {
                        ProgressView()
                    }
                }
        }
        .disabled(!isSendEnabled)
        .accessibilityLabel(sendLabel ?? ChatStrings.send)
    }
}

#Preview {
    @Previewable @FocusState var isFocused: Bool
    VStack {
        Spacer()
        MessageInputView(text: .constant("Привет!"), isFocused: $isFocused, hint: nil, isSendEnabled: true, onSend: {})
        MessageInputView(text: .constant(""), isFocused: $isFocused, hint: "Сообщение не должно быть длиннее 4096 символов", isSendEnabled: false, onSend: {})
        MessageInputView(text: .constant("Исправленный текст"), isFocused: $isFocused, hint: nil, isSendEnabled: false, isSubmitting: true, sendIcon: "checkmark.circle.fill", onSend: {})
    }
    .background(.bar)
}
