//
//  CreateSingleConversationRootView.swift
//  Chatik
//

import SwiftUI

/// Корневой контейнер экрана создания личного диалога: владеет роутером и NavigationStack для модального показа.
struct CreateSingleConversationRootView: View {
    @State private var router: CreateSingleConversationRouter

    /// - Parameter onFinish: вызывается при завершении экрана: с созданной перепиской или `nil` при отмене.
    ///   Закрытие модального экрана — на вызывающей стороне.
    init(onFinish: @escaping (Conversation?) -> Void) {
        _router = State(initialValue: CreateSingleConversationRouter(onFinish: onFinish))
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            CreateSingleConversationView(viewModel: CreateSingleConversationViewModel(
                usersService: DIContainer.shared.usersService,
                conversationService: DIContainer.shared.conversationService,
                sessionService: DIContainer.shared.sessionService,
                router: router
            ))
        }
    }
}
