//
//  CreateSingleConversationRouter.swift
//  Chatik
//

import SwiftUI

/// Роутер экрана создания личного диалога. Экран показывается модально и своих внутренних переходов пока не имеет,
/// поэтому роутер отвечает за его завершение: отмену и созданную переписку. Результат уходит тому, кто открыл
/// экран (`ChatListRootView`) — он закрывает лист и решает, куда переходить дальше.
@MainActor
@Observable
final class CreateSingleConversationRouter {
    var path = NavigationPath()

    private let onFinish: (Conversation?) -> Void

    /// - Parameter onFinish: вызывается при завершении экрана: с созданной перепиской или `nil` при отмене.
    init(onFinish: @escaping (Conversation?) -> Void) {
        self.onFinish = onFinish
    }

    /// Завершает экран без создания переписки.
    func cancel() {
        onFinish(nil)
    }

    /// Завершает экран, сообщая созданную (или уже существовавшую) переписку.
    /// - Parameter conversation: переписка из ответа сервера.
    func finish(with conversation: Conversation) {
        onFinish(conversation)
    }
}
