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
                    }
                }
        }
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .createSingleConversation:
                // Переход в переписку появится вместе с её экраном; пока созданная переписка просто
                // добавляется в список чатов, а лист закрывается — как и при отмене.
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
