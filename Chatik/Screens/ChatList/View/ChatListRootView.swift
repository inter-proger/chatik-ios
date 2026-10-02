//
//  ChatListRootView.swift
//  Chatik
//

import SwiftUI

/// Корневой контейнер экрана списка чатов: владеет роутером, ViewModel списка и NavigationStack.
/// ViewModel вынесена сюда (а не создаётся внутри `ChatListView`), чтобы созданная переписка из модального
/// экрана могла попасть в тот же список, что показан на экране.
struct ChatListRootView: View {
    @State private var router: ChatListRouter
    @State private var viewModel: ChatListViewModel

    init() {
        let router = ChatListRouter()
        _router = State(initialValue: router)
        _viewModel = State(initialValue: ChatListViewModel(
            authService: DIContainer.shared.authService,
            sessionService: DIContainer.shared.sessionService,
            conversationService: DIContainer.shared.conversationService,
            conversationStorage: DIContainer.shared.conversationStorage,
            userCache: DIContainer.shared.userCache,
            realtimeService: DIContainer.shared.realtimeService,
            router: router
        ))
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            ChatListView(viewModel: viewModel)
                .navigationDestination(for: ChatListRoute.self) { route in
                    switch route {
                    case .profile:
                        ProfileView(viewModel: ProfileViewModel(
                            profileService: DIContainer.shared.profileService,
                            filesService: DIContainer.shared.filesService,
                            imageFileStore: DIContainer.shared.imageFileStore,
                            sessionService: DIContainer.shared.sessionService,
                            isCameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera)
                        ))
                    case let .conversation(conversation):
                        ChatView(viewModel: ChatViewModel(
                            conversation: conversation,
                            messageService: DIContainer.shared.messageService,
                            messageStorage: DIContainer.shared.messageStorage,
                            sessionService: DIContainer.shared.sessionService,
                            userCache: DIContainer.shared.userCache,
                            localizationService: DIContainer.shared.localizationService,
                            messageTextValidator: DIContainer.shared.messageTextValidator,
                            realtimeService: DIContainer.shared.realtimeService
                        ))
                    }
                }
        }
        // События слушает корневой контейнер, а не экран списка: экран «исчезает», пока поверх открыта переписка,
        // а список должен оставаться актуальным.
        .task { await viewModel.observeRealtimeEvents() }
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .createSingleConversation:
                // Созданная переписка добавляется в список чатов и открывается; при отмене лист просто закрывается.
                CreateSingleConversationRootView(onFinish: { conversation in
                    if let conversation {
                        viewModel.didCreateConversation(conversation)
                    }
                    router.dismissSheet()
                })
            }
        }
    }
}

#Preview {
    ChatListRootView()
}
