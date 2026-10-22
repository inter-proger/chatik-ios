//
//  MessageReadersRequest.swift
//  Chatik
//

import Foundation

/// Сообщение, для которого открыт лист «Кем прочитано».
struct MessageReadersRequest: Identifiable, Equatable, Sendable {
    let conversationId: Int
    let messageId: Int
    /// Автор сообщения: его указатель двигается отправкой, поэтому в список прочитавших он не попадает.
    let senderId: Int

    var id: Int { messageId }
}
