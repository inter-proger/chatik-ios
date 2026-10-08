//
//  ChatView.swift
//  Chatik
//

import SwiftUI

/// Экран переписки: сообщения с подгрузкой более старых при прокрутке вверх, обновлением жестом вверх у нижнего края
/// ленты (pull-to-refresh) и поле ввода с кнопкой отправки. Тап по ленте убирает клавиатуру.
struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    init(viewModel: ChatViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        MessagesListView(
            messages: viewModel.messages,
            isLoadingNextPage: viewModel.isLoadingNextPage,
            onAppear: viewModel.prefetchNextPageIfNeeded,
            onTapFailed: viewModel.didTapMessage
        )
        .onTapGesture { isInputFocused = false }
        .overlay(alignment: .top) { navigationBarBackground }
        // Заглушка не перехватывает касания: потянуть ленту для обновления можно и в пустой переписке.
        .overlay { stateOverlay.allowsHitTesting(false) }
        .safeAreaInset(edge: .bottom) {
            ChatInputPanel(viewModel: viewModel, isFocused: $isInputFocused)
        }
        // Лента перевёрнута (см. `MessagesListView`), поэтому индикатор обновления появляется внизу, у новых сообщений.
        .refreshable { await viewModel.loadFirstPage() }
        .task { await viewModel.loadFirstPage() }
        .task { await viewModel.observeSentMessages() }
        .task { await viewModel.observeRealtimeEvents() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.title)
                    .font(.headline)
                    .lineLimit(1)
                    .redacted(reason: viewModel.isTitlePlaceholder ? .placeholder : [])
            }
        }
        .alert(CommonStrings.errorTitle, isPresented: $viewModel.errorMessage.isPresent(), presenting: viewModel.errorMessage) { _ in
            Button(CommonStrings.ok, role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .confirmationDialog(
            ChatStrings.failedActionsTitle,
            isPresented: $viewModel.failedMessageActionsClientId.isPresent(),
            titleVisibility: .visible,
            presenting: viewModel.failedMessageActionsClientId
        ) { clientId in
            Button(ChatStrings.failedActionsRetry) { viewModel.retrySending(clientId: clientId) }
            Button(ChatStrings.failedActionsDelete, role: .destructive) { viewModel.deleteOutgoing(clientId: clientId) }
        }
    }

    /// Подложка под панелью навигации. У ленты скрыты эффекты краёв прокрутки (см. `MessagesListView`), а на iOS 26
    /// фон панели рисуют именно они — без подложки заголовок ложился бы прямо на сообщения. View нулевой высоты
    /// стоит у верхнего края безопасной области, а её фон уходит вверх под панель навигации и строку состояния.
    /// До iOS 26 фон панели рисует она сама — вторая подложка сделала бы его плотнее, поэтому там её нет.
    /// Касаний подложка не принимает.
    @ViewBuilder
    private var navigationBarBackground: some View {
        if #available(iOS 26, *) {
            Color.clear
                .frame(height: 0)
                .background(.bar)
                .allowsHitTesting(false)
        }
    }

    /// Прелоадер первой загрузки или сообщение о пустой переписке поверх списка.
    @ViewBuilder
    private var stateOverlay: some View {
        if viewModel.isLoadingFirstPage && viewModel.messages.isEmpty {
            ProgressView()
        } else if viewModel.isEmpty {
            ContentUnavailableView(ChatStrings.empty, systemImage: "bubble.left")
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ChatView(viewModel: PreviewDependencies.chatViewModel())
    }
}
#endif
