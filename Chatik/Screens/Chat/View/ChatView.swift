//
//  ChatView.swift
//  Chatik
//

import SwiftUI
import UIKit

/// Экран переписки: сообщения с подгрузкой более старых при прокрутке вверх, обновлением жестом вверх у нижнего края
/// ленты (pull-to-refresh) и поле ввода с кнопкой отправки. Тап по ленте убирает клавиатуру.
/// Черновик (или текст правки в режиме редактирования) записывается в БД при уходе с экрана и при уходе приложения
/// в неактивное состояние или в фон. Долгое нажатие на своё сообщение открывает меню с «Редактировать», долгое
/// нажатие или тап по неотправленному — меню с «Повторить отправку» и «Удалить».
///
/// Меню сообщения показывает `MessageMenuController`: при открытой клавиатуре сначала прячет её, затем показывает
/// меню над пузырём, уже сдвинувшимся вместе с лентой.
struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    /// Создаётся при первом появлении экрана, а не значением по умолчанию `@State`: `init` экрана SwiftUI вызывает
    /// при каждой перерисовке родителя, и значение по умолчанию создавалось бы каждый раз, чтобы быть отброшенным.
    @State private var menuController: MessageMenuController?
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: ChatViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        feed
        // Клавиатура: меню сообщения показывается только после того, как она спрячется.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            menuController?.keyboardWillShow()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            menuController?.keyboardDidHide()
        }
        // Сообщение открытого меню изменилось или пропало — меню закрывается.
        .onChange(of: viewModel.sections) { _, sections in
            menuController?.feedDidChange(sections)
        }
        .onAppear {
            guard menuController == nil else { return }
            menuController = MessageMenuController(presenter: MessageMenuWindowPresenter())
        }
        // Лента перевёрнута (см. `MessagesListView`), поэтому индикатор обновления появляется внизу, у новых сообщений.
        .refreshable { await viewModel.refresh() }
        // Отмена задачи при уходе с экрана останавливает ленту: синхронизация отменяется и снимает аренду очереди.
        .task { await viewModel.observeMessages() }
        // Запрос правки, начатый на прошлом открытии экрана: его успех возвращает в поле черновик, ошибка показывается.
        .task { await viewModel.observeEditSubmission() }
        // Меню закрывается: с экрана можно уйти при открытом меню — нажатием на уведомление о сообщении.
        .onDisappear {
            viewModel.saveDraft()
            menuController?.dismiss()
        }
        // `.inactive` — не только шторка: закрытие из переключателя приложений не гарантирует перехода в `.background`.
        // Повторное сохранение без изменений в БД не пишет.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            viewModel.saveDraft()
        }
        // Прочтение — только в активной сцене этого экрана: шторка, фон и неактивная сцена iPad его не дают.
        .onChange(of: scenePhase, initial: true) { _, phase in
            viewModel.setSceneActive(phase == .active)
        }
        // Экран может уйти и вернуться без смены `scenePhase`: при появлении активность берётся заново.
        .onAppear { viewModel.setSceneActive(scenePhase == .active) }
        .onDisappear { viewModel.setSceneActive(false) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleView
            }
        }
        // Правка не сохранилась: клавиатура пряталась на время запроса и возвращается, чтобы исправить текст.
        .onChange(of: viewModel.inputFocusRequest) {
            isInputFocused = true
        }
    }

    /// Долгое нажатие на сообщение или тап по неотправленному: меню действий; открытую клавиатуру контроллер
    /// сначала прячет.
    /// - Parameters:
    ///   - message: сообщение.
    ///   - source: пузырь.
    private func showMenu(for message: MessageDisplayModel, source: MessageMenuSource) {
        guard viewModel.areMessageActionsEnabled else { return }
        menuController?.request(
            message: message,
            source: source,
            hideKeyboard: { isInputFocused = false },
            onAction: { viewModel.didSelectAction($0, for: message) }
        )
    }

    /// Лента с панелью ввода.
    private var feed: some View {
        MessagesListView(
            sections: viewModel.sections,
            isLoadingOlder: viewModel.isLoadingOlder,
            onAppear: viewModel.prefetchOlderIfNeeded,
            onAction: viewModel.didSelectAction,
            onMenuRequest: showMenu,
            menuMessageId: menuController?.menuMessageId,
            areActionsEnabled: viewModel.areMessageActionsEnabled,
            unreadBadgeText: viewModel.unreadBadgeText,
            unreadBadgeAccessibilityValue: viewModel.unreadBadgeAccessibilityValue,
            insertionAnimationToken: viewModel.insertionAnimationToken,
            scrollToBottomRequest: viewModel.scrollToBottomRequest,
            onBottomChange: viewModel.setAtBottom
        )
        .onTapGesture { isInputFocused = false }
        .overlay(alignment: .top) { navigationBarBackground }
        // Заглушка не перехватывает касания: потянуть ленту для обновления можно и в пустой переписке.
        .overlay { stateOverlay.allowsHitTesting(false) }
        .safeAreaInset(edge: .bottom) {
            ChatInputPanel(viewModel: viewModel, isFocused: $isInputFocused)
        }
        // Плашка редактирования меняет высоту панели: лента сдвигается в той же анимации, что и плашка, а не скачком
        // до её конца. Анимация здесь, а не в панели: иначе анимировалась бы только панель. Секции ленты смена режима
        // не меняет (действия скрывает `areActionsEnabled`), поэтому в анимацию попадают только отступ и плашка.
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
