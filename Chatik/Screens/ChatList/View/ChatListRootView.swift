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
    }
}

#Preview {
    ChatListRootView()
}
