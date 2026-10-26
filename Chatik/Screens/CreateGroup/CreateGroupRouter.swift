//
//  CreateGroupRouter.swift
//  Chatik
//

import SwiftUI

/// Роутер экрана создания группы. Экран показывается модально и своих переходов не имеет: роутер отвечает за его
/// завершение — отмену и созданную группу. Результат уходит тому, кто открыл экран (`ChatListRootView`).
@MainActor
@Observable
final class CreateGroupRouter {
    var path = NavigationPath()

    private let onFinish: (Conversation?) -> Void

    /// - Parameter onFinish: вызывается при завершении экрана: с созданной группой или `nil` при отмене.
    init(onFinish: @escaping (Conversation?) -> Void) {
        self.onFinish = onFinish
    }

    /// Завершает экран без создания группы.
    func cancel() {
        onFinish(nil)
    }

    /// Завершает экран, сообщая созданную группу.
    /// - Parameter conversation: группа из ответа сервера.
    func finish(with conversation: Conversation) {
        onFinish(conversation)
    }
}
