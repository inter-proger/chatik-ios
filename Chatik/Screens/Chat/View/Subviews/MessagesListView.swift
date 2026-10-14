//
//  MessagesListView.swift
//  Chatik
//

import SwiftUI

/// Лента сообщений: самые новые внизу, более старые подгружаются при прокрутке вверх.
///
/// Прокрутка перевёрнута: `ScrollView` и каждая строка отражены по вертикали. Так лента начинается с самых новых
/// сообщений без ручной прокрутки, а подгруженные старые дописываются в конец данных (визуально — сверху)
/// и не сдвигают то, что сейчас на экране. Pull-to-refresh (`.refreshable` у родителя) тоже переворачивается:
/// индикатор появляется внизу ленты, а обновление запускается, если потянуть ленту вверх от самых новых сообщений.
struct MessagesListView: View {
    /// Сообщения, сначала самые новые.
    let messages: [MessageDisplayModel]
    let isLoadingOlder: Bool
    let onAppear: (MessageDisplayModel) -> Void
    /// Тап по неотправленному сообщению.
    let onTapFailed: (MessageDisplayModel) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(messages) { message in
                    MessageBubbleView(message: message, onTapFailed: { onTapFailed(message) })
                        .flippedVertically()
                        .onAppear { onAppear(message) }
                }
                if isLoadingOlder {
                    ProgressView()
                        .padding()
                        .flippedVertically()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .flippedVertically()
        .scrollEdgeEffectsHiddenIfAvailable()
        .scrollDismissesKeyboard(.interactively)
    }
}

private extension View {
    /// Скрывает эффекты краёв прокрутки iOS 26 (размытие и затемнение под панелями). Для перевёрнутой ленты они
    /// рисуются не у тех краёв: нижний эффект, высота которого — панель ввода вместе с клавиатурой, оказывается
    /// сверху и при открытой клавиатуре затемняет почти всю ленту. Подложку под панелью навигации рисует `ChatView`.
    @ViewBuilder
    func scrollEdgeEffectsHiddenIfAvailable() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }

    /// Отражает View по вертикали — для перевёрнутой ленты сообщений.
    func flippedVertically() -> some View {
        scaleEffect(x: 1, y: -1)
    }
}

#Preview {
    let ivan = MessageSenderDisplayModel(name: "Иван Петров", isPlaceholder: false, avatarURL: nil)
    let maria = MessageSenderDisplayModel(name: "Мария", isPlaceholder: false, avatarURL: nil)
    MessagesListView(
        messages: [
            MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "6"), text: "Ты где?", isUnsupported: false, isOutgoing: true, sender: nil, time: "12:07", editedLabel: nil, deliveryState: .failed, deliveryStateLabel: "Не отправлено"),
            MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "5"), text: "Я уже на месте", isUnsupported: false, isOutgoing: true, sender: ivan, time: "12:06", editedLabel: nil, deliveryState: .sending, deliveryStateLabel: "Отправляется"),
            MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "4"), text: "Отлично, до встречи!", isUnsupported: false, isOutgoing: true, sender: ivan, time: "12:05", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil),
            MessageDisplayModel(id: MessageClientKey(senderId: 2, clientId: "3"), text: "Давай в 7 у входа", isUnsupported: false, isOutgoing: false, sender: nil, time: "12:04", editedLabel: "изменено", deliveryState: .delivered, deliveryStateLabel: nil),
            MessageDisplayModel(id: MessageClientKey(senderId: 2, clientId: "2"), text: "Привет!", isUnsupported: false, isOutgoing: false, sender: maria, time: "12:03", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil),
            MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "1"), text: "Привет! Во сколько встречаемся?", isUnsupported: false, isOutgoing: true, sender: ivan, time: "12:01", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil),
        ],
        isLoadingOlder: true,
        onAppear: { _ in },
        onTapFailed: { _ in }
    )
}
