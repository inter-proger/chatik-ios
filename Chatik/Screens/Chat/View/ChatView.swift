//
//  ChatView.swift
//  Chatik
//

import SwiftUI

/// Экран переписки: сообщения с подгрузкой более старых при прокрутке вверх, обновлением жестом вверх у нижнего края
/// ленты (pull-to-refresh) и поле ввода с кнопкой отправки.
struct ChatView: View {
    @State private var viewModel: ChatViewModel

    init(viewModel: ChatViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        MessagesListView(
            messages: viewModel.messages,
            isLoadingNextPage: viewModel.isLoadingNextPage,
            onAppear: viewModel.prefetchNextPageIfNeeded
        )
        // Заглушка не перехватывает касания: потянуть ленту для обновления можно и в пустой переписке.
        .overlay { stateOverlay.allowsHitTesting(false) }
        .safeAreaInset(edge: .bottom) {
            ChatInputPanel(viewModel: viewModel)
        }
        // Лента перевёрнута (см. `MessagesListView`), поэтому индикатор обновления появляется внизу, у новых сообщений.
        .refreshable { await viewModel.loadFirstPage() }
        .task { await viewModel.loadFirstPage() }
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
