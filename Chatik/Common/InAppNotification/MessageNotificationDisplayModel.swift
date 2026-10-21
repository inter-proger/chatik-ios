//
//  MessageNotificationDisplayModel.swift
//  Chatik
//

import SwiftUI

/// Уведомление о новом сообщении в готовом для показа виде.
struct MessageNotificationDisplayModel: Equatable {
    let conversationId: Int
    let messageId: Int
    /// Название группы либо имя отправителя личной переписки.
    let title: String
    /// Аватар отправителя — уменьшенная копия, если она есть; `nil` — изображение по умолчанию.
    let avatarURL: URL?
    /// Текст сообщения в одну строку. В группе — с префиксом «Имя:» основным цветом, сам текст — второстепенным.
    let text: AttributedString
}

extension MessageNotificationDisplayModel {
    /// Сколько первых символов сообщения попадает в уведомление: показывается одна строка.
    static let textLength = 200

    /// Собирает уведомление: у личной переписки заголовок — имя отправителя, у остальных — название переписки,
    /// а перед текстом — имя отправителя. Аватар — всегда отправителя.
    /// - Parameters:
    ///   - message: новое сообщение.
    ///   - conversation: переписка сообщения.
    ///   - sender: отправитель из кэша; `.pending` — не загрузился, вместо имени заглушка.
    @MainActor
    init(message: Message, conversation: Conversation, sender: CachedUser) {
        let senderName = Self.senderName(for: sender)
        let isSingle = conversation.type == .single
        let title = isSingle ? senderName : conversation.name ?? InAppNotificationStrings.messageUntitled
        self.init(
            conversationId: conversation.conversationId,
            messageId: message.messageId,
            title: title,
            avatarURL: Self.avatarURL(for: sender),
            text: Self.text(for: message, senderPrefix: isSingle ? nil : senderName)
        )
    }

    /// Имя отправителя для показа.
    /// - Parameter sender: отправитель из кэша.
    @MainActor
    private static func senderName(for sender: CachedUser) -> String {
        switch sender {
        case let .loaded(user): user.name
        case .pending: InAppNotificationStrings.messageUnknownSender
        case .notFound: InAppNotificationStrings.messageDeletedSender
        }
    }

    /// Аватар отправителя: уменьшенная копия, если она есть.
    /// - Parameter sender: отправитель из кэша.
    private static func avatarURL(for sender: CachedUser) -> URL? {
        guard case let .loaded(user) = sender, let avatar = user.avatar else { return nil }
        return avatar.smallURL ?? avatar.url
    }

    /// Текст сообщения в одну строку; для неизвестного типа — «Сообщение».
    /// - Parameters:
    ///   - message: сообщение.
    ///   - senderPrefix: имя отправителя перед текстом; `nil` — без префикса.
    @MainActor
    private static func text(for message: Message, senderPrefix: String?) -> AttributedString {
        let line = message.type == .unknown
            ? InAppNotificationStrings.messageUnsupported
            : SingleLineText.make(message.text, maxLength: textLength)
        var body = AttributedString(line)
        body.foregroundColor = .secondary
        guard let senderPrefix else { return body }
        var prefix = AttributedString(senderPrefix + ": ")
        prefix.foregroundColor = .primary
        return prefix + body
    }
}
