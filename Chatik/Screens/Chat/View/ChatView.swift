//
//  ChatView.swift
//  Chatik
//

import SwiftUI

/// Экран переписки: сообщения с подгрузкой более старых при прокрутке вверх, обновлением жестом вверх у нижнего края
/// ленты (pull-to-refresh) и поле ввода с кнопкой отправки. Тап по ленте убирает клавиатуру.
/// Черновик записывается в БД при уходе с экрана и при уходе приложения в неактивное состояние или в фон.
struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: ChatViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        MessagesListView(
            sections: viewModel.sections,
            isLoadingOlder: viewModel.isLoadingOlder,
            onAppear: viewModel.prefetchOlderIfNeeded,
            failedActionsClientId: $viewModel.failedMessageActionsClientId,
            onTapFailed: viewModel.didTapMessage,
            onRetry: { viewModel.retrySending(clientId: $0.id.clientId) },
            onDelete: { viewModel.deleteOutgoing(clientId: $0.id.clientId) }
        )
        .onTapGesture { isInputFocused = false }
        .overlay(alignment: .top) { navigationBarBackground }
        // Заглушка не перехватывает касания: потянуть ленту для обновления можно и в пустой переписке.
        .overlay { stateOverlay.allowsHitTesting(false) }
        .safeAreaInset(edge: .bottom) {
            ChatInputPanel(viewModel: viewModel, isFocused: $isInputFocused)
        }
        // Лента перевёрнута (см. `MessagesListView`), поэтому индикатор обновления появляется внизу, у новых сообщений.
        .refreshable { await viewModel.refresh() }
        // Отмена задачи при уходе с экрана останавливает ленту: синхронизация отменяется и снимает аренду очереди.
        .task { await viewModel.observeMessages() }
        .onDisappear { viewModel.saveDraft() }
        // `.inactive` — не только шторка: закрытие из переключателя приложений не гарантирует перехода в `.background`.
        // Повторное сохранение без изменений в БД не пишет.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            viewModel.saveDraft()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleView
            }
        }
        .alert(CommonStrings.errorTitle, isPresented: $viewModel.errorMessage.isPresent(), presenting: viewModel.errorMessage) { _ in
            Button(CommonStrings.ok, role: .cancel) {}
        } message: { message in
            Text(message)
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

    /// Заголовок: имя собеседника или название группы, а под ним, пока идёт синхронизация, — индикатор
    /// и «Обновление…». Лента из кэша при этом остаётся интерактивной.
    private var titleView: some View {
        VStack(spacing: 0) {
            Text(viewModel.title)
                .font(.headline)
                .lineLimit(1)
                .redacted(reason: viewModel.isTitlePlaceholder ? .placeholder : [])
            if viewModel.isSyncing {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(ChatStrings.updating)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Прелоадер, пока кэша нет и идёт синхронизация, или сообщение о пустой переписке поверх списка.
    @ViewBuilder
    private var stateOverlay: some View {
        if viewModel.isShowingLoader {
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
