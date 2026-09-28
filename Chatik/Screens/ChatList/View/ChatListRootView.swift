//
//  ChatListRootView.swift
//  Chatik
//

import SwiftUI

/// Корневой контейнер экрана списка чатов: владеет роутером и NavigationStack.
struct ChatListRootView: View {
    @State private var router = ChatListRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            ChatListView(viewModel: ChatListViewModel(
                authService: DIContainer.shared.authService,
                sessionService: DIContainer.shared.sessionService,
                router: router
            ))
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
                // Пока и отмена, и создание просто закрывают лист; переход в переписку появится вместе с её экраном.
                CreateSingleConversationRootView(onFinish: { _ in router.dismissSheet() })
            }
        }
    }
}

#Preview {
    ChatListRootView()
}
