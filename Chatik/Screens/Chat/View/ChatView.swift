//
//  ChatView.swift
//  Chatik
//

import SwiftUI
import UIKit

/// Экран переписки: сообщения с подгрузкой более старых при прокрутке вверх, обновлением жестом вверх у нижнего края
/// ленты (pull-to-refresh) и поле ввода с кнопкой отправки. Тап по ленте убирает клавиатуру.
/// Черновик (или текст правки в режиме редактирования) записывается в БД при уходе с экрана и при уходе приложения
/// в неактивное состояние или в фон. Долгое нажатие на своё сообщение открывает меню с «Редактировать».
///
/// Пока меню сообщения нажато или открыто, лента с панелью ввода держат высоту, что была при нажатии
/// (`ChatLayoutFreeze`): меню прячет клавиатуру, и без этого сообщение уехало бы из-под своего превью.
struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @State private var layoutFreeze = ChatLayoutFreeze()
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: ChatViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Область над клавиатурой: её высоту фиксирует `layoutFreeze`, пока открыто меню сообщения.
            Color.clear
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { layoutFreeze.setAvailableHeight($0) }
            feed
                .frame(height: layoutFreeze.frozenHeight)
                // Прокрутка рисует сообщения и за нижним краем рамки: зафиксированная прокрученная лента показывала бы
                // их под панелью, пока снизу поднимается клавиатура.
                .clipShape(BottomEdgeClip(isActive: layoutFreeze.frozenHeight != nil))
                .frame(maxHeight: .infinity, alignment: .top)
                // Зафиксированная лента не следует за клавиатурой: клавиатура, спрятанная меню, её не сдвигает.
                .ignoresSafeArea(layoutFreeze.frozenHeight == nil ? [] : .keyboard, edges: .bottom)
        }
        // Если клавиатура после меню не вернулась, лента опускается плавно, а не скачком.
        .animation(.default, value: layoutFreeze.frozenHeight == nil)
        // Клавиатура, спрятанная меню, поднялась до конца — лента снова следует за ней.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            layoutFreeze.keyboardDidShow()
        }
        // Лента перевёрнута (см. `MessagesListView`), поэтому индикатор обновления появляется внизу, у новых сообщений.
        .refreshable { await viewModel.refresh() }
        // Отмена задачи при уходе с экрана останавливает ленту: синхронизация отменяется и снимает аренду очереди.
        .task { await viewModel.observeMessages() }
        // Запрос правки, начатый на прошлом открытии экрана: его успех возвращает в поле черновик, ошибка показывается.
        .task { await viewModel.observeEditSubmission() }
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

    /// Лента с панелью ввода.
    private var feed: some View {
        MessagesListView(
            sections: viewModel.sections,
            isLoadingOlder: viewModel.isLoadingOlder,
            onAppear: viewModel.prefetchOlderIfNeeded,
            failedActionsClientId: $viewModel.failedMessageActionsClientId,
            onTapFailed: viewModel.didTapMessage,
            onRetry: { viewModel.retrySending(clientId: $0.id.clientId) },
            onDelete: { viewModel.deleteOutgoing(clientId: $0.id.clientId) },
            onAction: viewModel.didSelectAction,
            onMenuPhaseChange: { layoutFreeze.setMenuPhase($0) }
        )
        .onTapGesture { isInputFocused = false }
        .overlay(alignment: .top) { navigationBarBackground }
        // Заглушка не перехватывает касания: потянуть ленту для обновления можно и в пустой переписке.
        .overlay { stateOverlay.allowsHitTesting(false) }
        .safeAreaInset(edge: .bottom) {
            ChatInputPanel(viewModel: viewModel, isFocused: $isInputFocused)
        }
        // Плашка редактирования меняет высоту панели: лента сдвигается в той же анимации, что и плашка, а не скачком
        // до её конца. Анимация здесь, а не в панели: иначе анимировалась бы только панель.
        .animation(.default, value: viewModel.isEditing)
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

/// Обрезка только по нижнему краю: верх и бока продлены далеко за рамку, чтобы лента по-прежнему уходила
/// под панель навигации. Выключенная обрезка ничего не режет — форма та же, и идентичность View не меняется.
private struct BottomEdgeClip: Shape {
    /// `false` — обрезки нет.
    let isActive: Bool

    /// Насколько форма выходит за рамку сверху и по бокам (и снизу, когда обрезка выключена).
    private static let overhang: CGFloat = 10_000

    /// Прямоугольник рамки, продлённый вверх и в стороны; снизу — по краю рамки, если обрезка включена.
    /// - Parameter rect: рамка View.
    func path(in rect: CGRect) -> Path {
        let bottom = isActive ? rect.maxY : rect.maxY + Self.overhang
        return Path(CGRect(
            x: rect.minX - Self.overhang,
            y: rect.minY - Self.overhang,
            width: rect.width + 2 * Self.overhang,
            height: bottom - rect.minY + Self.overhang
        ))
    }
}
