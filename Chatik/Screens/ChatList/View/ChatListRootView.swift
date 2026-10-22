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
    @Environment(\.inAppNotificationSceneId) private var sceneId

    init() {
        let router = ChatListRouter()
        _router = State(initialValue: router)
        _viewModel = State(initialValue: ChatListViewModel(
            conversationList: DIContainer.shared.conversationListService,
            sessionService: DIContainer.shared.sessionService,
            userCache: DIContainer.shared.userCache,
            draftService: DIContainer.shared.messageDraftService,
            unsentMessages: DIContainer.shared.messageSendQueue,
            localizationService: DIContainer.shared.localizationService,
            notifications: DIContainer.shared.notificationService,
            navigator: DIContainer.shared.conversationNavigator,
            messageNotifications: DIContainer.shared.messageNotificationService,
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
                            authService: DIContainer.shared.authService,
                            notifications: DIContainer.shared.notificationService,
                            isCameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera)
                        ))
                    case let .conversation(conversation):
                        // `.id`: смена переписки из уведомления заменяет элемент стека на той же позиции — экран
                        // должен пересоздаться с новой ViewModel, а прежний уйти через `onDisappear` (черновик).
                        ChatView(viewModel: ChatViewModel(
                            conversation: conversation,
                            messagesList: DIContainer.shared.makeMessagesListService(conversationId: conversation.conversationId),
                            messageSendQueue: DIContainer.shared.messageSendQueue,
                            editService: DIContainer.shared.messageEditService,
                            sessionService: DIContainer.shared.sessionService,
                            draftService: DIContainer.shared.messageDraftService,
                            userCache: DIContainer.shared.userCache,
                            localizationService: DIContainer.shared.localizationService,
                            messageTextValidator: DIContainer.shared.messageTextValidator,
                            dateHeaderFormatterProvider: DIContainer.shared.messageDateHeaderFormatterProvider,
                            timeChangeService: DIContainer.shared.significantTimeChangeService,
                            notifications: DIContainer.shared.notificationService,
                            readStates: DIContainer.shared.conversationListService,
                            memberReads: DIContainer.shared.memberReadService
                        ))
                        .id(conversation.id)
                    }
                }
        }
        .onAppear { viewModel.didAppear(sceneId: sceneId) }
        .onDisappear { viewModel.didDisappear() }
        .onChange(of: router.openedConversationId) { _, conversationId in
            viewModel.openedConversationDidChange(conversationId)
        }
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
