//
//  CreateGroupRootView.swift
//  Chatik
//

import SwiftUI

/// Корневой контейнер экрана создания группы: владеет роутером и NavigationStack для модального показа.
struct CreateGroupRootView: View {
    @State private var router: CreateGroupRouter

    /// - Parameter onFinish: вызывается при завершении экрана: с созданной группой или `nil` при отмене.
    ///   Закрытие модального экрана — на вызывающей стороне.
    init(onFinish: @escaping (Conversation?) -> Void) {
        _router = State(initialValue: CreateGroupRouter(onFinish: onFinish))
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            CreateGroupView(viewModel: CreateGroupViewModel(
                groupService: DIContainer.shared.groupService,
                groupInfo: DIContainer.shared.groupInfoService,
                conversationList: DIContainer.shared.conversationListService,
                filesService: DIContainer.shared.filesService,
                imageFileStore: DIContainer.shared.imageFileStore,
                notifications: DIContainer.shared.notificationService,
                router: router,
                isCameraAvailable: UIImagePickerController.isSourceTypeAvailable(.camera)
            ))
        }
    }
}
