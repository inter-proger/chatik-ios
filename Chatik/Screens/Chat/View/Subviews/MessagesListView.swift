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
    let isLoadingNextPage: Bool
    let onAppear: (MessageDisplayModel) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(messages) { message in
                    MessageBubbleView(message: message)
                        .flippedVertically()
                        .onAppear { onAppear(message) }
                }
                if isLoadingNextPage {
                    ProgressView()
                        .padding()
                        .flippedVertically()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .flippedVertically()
        .scrollDismissesKeyboard(.interactively)
    }
}

private extension View {
    /// Отражает View по вертикали — для перевёрнутой ленты сообщений.
    func flippedVertically() -> some View {
        scaleEffect(x: 1, y: -1)
    }
}

#Preview {
    MessagesListView(
        messages: [
            MessageDisplayModel(id: 3, text: "Отлично, до встречи!", isUnsupported: false, isOutgoing: true, senderName: nil, isSenderPlaceholder: false, time: "12:05", editedLabel: nil),
            MessageDisplayModel(id: 2, text: "Давай в 7 у входа", isUnsupported: false, isOutgoing: false, senderName: nil, isSenderPlaceholder: false, time: "12:04", editedLabel: "изменено"),
            MessageDisplayModel(id: 1, text: "Привет! Во сколько встречаемся?", isUnsupported: false, isOutgoing: true, senderName: nil, isSenderPlaceholder: false, time: "12:01", editedLabel: nil),
        ],
        isLoadingNextPage: true,
        onAppear: { _ in }
    )
}
