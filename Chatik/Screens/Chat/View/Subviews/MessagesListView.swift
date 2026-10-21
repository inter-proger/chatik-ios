//
//  MessagesListView.swift
//  Chatik
//

import SwiftUI

/// Лента сообщений по дням: самые новые внизу, более старые подгружаются при прокрутке вверх. Над сообщениями
/// каждого дня — заголовок с датой, а во время прокрутки поверх ленты — плавающая дата верхних сообщений
/// (`FloatingDateHeaderView`).
///
/// Прокрутка перевёрнута: `ScrollView` и каждая строка отражены по вертикали. Так лента начинается с самых новых
/// сообщений без ручной прокрутки, а подгруженные старые дописываются в конец данных (визуально — сверху)
/// и не сдвигают то, что сейчас на экране. Поэтому заголовок дня идёт в данных после сообщений своей секции —
/// визуально он над ними. Pull-to-refresh (`.refreshable` у родителя) тоже переворачивается: индикатор появляется
/// внизу ленты, а обновление запускается, если потянуть ленту вверх от самых новых сообщений.
///
/// Секции и строки — плоские `ForEach` внутри одного `LazyVStack`: обёртка дня в `VStack` выключила бы ленивую
/// загрузку внутри дня, а за день бывают сотни сообщений.
///
/// Положение относительно низа ленты меряется якорем низа (`FeedBottomTracker`). Пока лента не внизу, новое сообщение
/// её не сдвигает — видимую строку держит `FeedOffsetKeeper`; справа внизу тогда же — кнопка «вниз» со счётчиком
/// непрочитанных. Новое сообщение у нижнего края появляется с анимацией (`insertionAnimationToken`).
struct MessagesListView: View {
    /// Секции по дням, сначала самые новые.
    let sections: [MessageDaySectionDisplayModel]
    let isLoadingOlder: Bool
    let onAppear: (MessageDisplayModel) -> Void
    /// Выбрано действие с сообщением для VoiceOver.
    let onAction: (MessageAction, MessageDisplayModel) -> Void
    /// Запрошено меню сообщения (долгое нажатие или тап по неотправленному); второй параметр — пузырь как источник
    /// меню.
    var onMenuRequest: (MessageDisplayModel, MessageMenuSource) -> Void = { _, _ in }
    /// Сообщение, для которого открыто меню: его пузырь скрыт. `nil` — меню нет.
    var menuMessageId: MessageClientKey?
    /// Действия с сообщениями доступны; `false` — режим редактирования, действий нет ни у одного сообщения.
    var areActionsEnabled = true
    /// Счётчик непрочитанных в углу кнопки «вниз»; `nil` — непрочитанных нет.
    var unreadBadgeText: String?
    /// Непрочитанные для VoiceOver — значение кнопки «вниз».
    var unreadBadgeAccessibilityValue: String?
    /// Меняется, когда изменение ленты нужно анимировать: новое сообщение у нижнего края.
    var insertionAnimationToken = 0
    /// Меняется, когда ленту нужно вернуть вниз.
    var scrollToBottomRequest = 0
    /// Лента дошла до низа или ушла от него.
    var onBottomChange: (Bool) -> Void = { _ in }

    /// Анимация вставки сдвигает строки без жеста всё время анимации: трекер узнаёт о ней по `insertionAnimationToken`
    /// в кадрах строк, и плавающая дата при этом не появляется.
    @State private var tracker = FloatingDateTracker(layoutAnimationDuration: .seconds(MessagesListView.scrollAnimationSeconds))
    @State private var bottomTracker = FeedBottomTracker()
    @State private var keeper = FeedOffsetKeeper()

    /// Идентификатор якоря низа — цель прокрутки кнопки «вниз».
    private static let bottomAnchorId = "feedBottom"
    /// Длительность прокрутки кнопкой «вниз» и вставки нового сообщения, в секундах.
    private static let scrollAnimationSeconds: TimeInterval = 0.3
    /// Кривая прокрутки кнопкой «вниз» и вставки нового сообщения: вставка выглядит как та же прокрутка.
    private static let scrollAnimation: Animation = .easeOut(duration: scrollAnimationSeconds)
    /// Появление строки у нижнего края: строка выезжает из-под края вместе со сдвигом остальных строк, без
    /// прозрачности — лента выглядит программно прокрученной вверх. В отражённой ленте визуальный низ — верх
    /// содержимого, поэтому край `.top`. Удаление без анимации: под той же анимацией строка не должна уезжать.
    private static let rowInsertion: AnyTransition = .asymmetric(insertion: .move(edge: .top), removal: .identity)

    var body: some View {
        ScrollViewReader { proxy in
            feed
                .overlay(alignment: .bottomTrailing) { scrollToBottomButton(proxy: proxy) }
                .onChange(of: scrollToBottomRequest) { scrollToBottom(proxy) }
        }
        .onChange(of: bottomTracker.isAtBottom, initial: true) { _, isAtBottom in
            keeper.isHolding = !isAtBottom
            onBottomChange(isAtBottom)
        }
        .onAppear {
            // Компенсация сдвигает строки без жеста: на iOS 17 трекер иначе принял бы её за прокрутку.
            keeper.onCompensation = { [tracker] in tracker.layoutDidChange() }
        }
    }

    /// Лента: якорь низа и строки в перевёрнутом `ScrollView`.
    private var feed: some View {
        ScrollView {
            VStack(spacing: 0) {
                bottomAnchor
                rows
                    .background { FeedScrollViewLocator(keeper: keeper) }
            }
            .coordinateSpace(.named(FeedOffsetKeeper.contentSpace))
        }
        .flippedVertically()
        .scrollPhaseTracking(tracker)
        // Пространство — снаружи отражения: кадры строк в нём уже визуальные.
        .coordinateSpace(.named(FloatingDateTracker.coordinateSpace))
        // Клавиатура и поворот меняют высоту ленты и сдвигают строки без жеста.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            tracker.layoutDidChange()
            bottomTracker.viewportDidChange(height: height)
            keeper.viewportDidChange(height: height)
        }
        .overlay(alignment: .top) { FloatingDateHeaderView(tracker: tracker) }
        // Только заголовки, а не сами секции: сравнение всей ленты с сообщениями на каждом `body` шло бы на main.
        .onChange(of: sectionTitles, initial: true) { _, titles in tracker.setTitles(titles) }
        .onChange(of: isLoadingOlder) { tracker.layoutDidChange() }
        .scrollEdgeEffectsHiddenIfAvailable()
        .scrollDismissesKeyboard(.interactively)
    }

    /// Якорь низа: строка нулевой высоты у начала данных (визуально — у нижнего края) вне `LazyVStack` — выкладывается
    /// всегда и сообщает, насколько лента отлистана от низа.
    private var bottomAnchor: some View {
        Color.clear
            .frame(height: 0)
            .id(Self.bottomAnchorId)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(FloatingDateTracker.coordinateSpace)).minY
            } action: { minY in
                bottomTracker.anchorDidMove(minY: minY)
            }
    }

    /// Строки ленты: сообщения, заголовки непрочитанных и дней, индикатор подгрузки старых.
    private var rows: some View {
        LazyVStack(spacing: 2) {
            ForEach(sections) { section in
                ForEach(section.messages) { message in
                    messageRow(message, in: section)
                        .transition(Self.rowInsertion)
                    if section.unreadHeaderBefore == message.id {
                        // В данных после сообщения — визуально над ним.
                        UnreadMessagesHeaderView()
                            .padding(.vertical, 6)
                            .flippedVertically()
                            .transition(Self.rowInsertion)
                    }
                }
                DateHeaderRow(section: section, tracker: tracker, layoutAnimation: insertionAnimationToken)
                    .transition(Self.rowInsertion)
            }
            if isLoadingOlder {
                ProgressView()
                    .padding()
                    .flippedVertically()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(Self.scrollAnimation, value: insertionAnimationToken)
    }

    /// Строка сообщения: пузырь, подгрузка старых, кадр для плавающей даты и для удержания ленты.
    /// - Parameters:
    ///   - message: сообщение.
    ///   - section: секция сообщения.
    private func messageRow(_ message: MessageDisplayModel, in section: MessageDaySectionDisplayModel) -> some View {
        MessageBubbleView(
            message: message,
            onAction: { onAction($0, message) },
            onMenuRequest: { onMenuRequest(message, $0) },
            isHiddenForMenu: menuMessageId == message.id,
            areActionsEnabled: areActionsEnabled
        )
            .flippedVertically()
            .onAppear { onAppear(message) }
            .trackFrame(
                FloatingDateRow(kind: .message(message.id), section: section.id),
                in: tracker,
                layoutAnimation: insertionAnimationToken
            )
            .holdsFeedPosition(message.id, keeper: keeper)
    }

    /// Кнопка «вниз»: видна, если лента не внизу и либо отлистана дальше порога, либо есть непрочитанные.
    /// - Parameter proxy: прокрутка к якорю низа.
    @ViewBuilder
    private func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
        if !bottomTracker.isAtBottom, bottomTracker.isBeyondThreshold || unreadBadgeText != nil {
            ScrollToBottomButton(badgeText: unreadBadgeText, accessibilityValue: unreadBadgeAccessibilityValue) {
                scrollToBottom(proxy)
            }
            .padding(.trailing, 12)
            .padding(.bottom, 12)
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Возвращает ленту вниз: издалека — переходом без анимации (анимированная прокрутка через сотни ленивых строк
    /// дёргается), иначе — плавно. На время возврата удержание не компенсирует сдвиги — иначе спорило бы с прокруткой.
    /// Отметку прочтения сделает экран, когда лента окажется внизу.
    /// - Parameter proxy: прокрутка к якорю низа.
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        keeper.beginReturnToBottom()
        guard !bottomTracker.shouldJumpToBottom else {
            proxy.scrollTo(Self.bottomAnchorId, anchor: .top)
            return
        }
        withAnimation(Self.scrollAnimation) {
            proxy.scrollTo(Self.bottomAnchorId, anchor: .top)
        }
    }

    /// Заголовки секций для трекера плавающей даты.
    private var sectionTitles: [MessageDaySectionID: String] {
        Dictionary(sections.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Кадр строки для удержания ленты.
private struct FeedRowPosition: Equatable {
    /// `minY` в координатах содержимого прокрутки.
    let contentMinY: CGFloat
    /// Визуальный `minY` в координатах ленты.
    let visualMinY: CGFloat
}

/// Заголовок дня в ленте. Отдельный View: прозрачность под плашкой перерисовывает только этот заголовок, а не всю
/// ленту. Пока плашка видна и закрывает его, заголовок прозрачный — иначе на переходе были бы видны две капсулы.
private struct DateHeaderRow: View {
    let section: MessageDaySectionDisplayModel
    let tracker: FloatingDateTracker
    /// Номер анимированной смены раскладки ленты — для трекера.
    let layoutAnimation: Int

    var body: some View {
        MessageDateHeaderView(title: section.title)
            .opacity(tracker.coveredHeader == section.id ? 0 : 1)
            .flippedVertically()
            .trackFrame(FloatingDateRow(kind: .header, section: section.id), in: tracker, layoutAnimation: layoutAnimation)
            // Снаружи `trackFrame`: трекер знает кадр капсулы, и плашка встаёт ровно на место заголовка.
            .padding(.vertical, 8)
    }
}

private extension View {
    /// Сообщает удержанию ленты кадр строки: в координатах содержимого — для компенсации, визуальный — чтобы понять,
    /// видна ли строка.
    /// - Parameters:
    ///   - id: строка.
    ///   - keeper: удержание ленты.
    func holdsFeedPosition(_ id: MessageClientKey, keeper: FeedOffsetKeeper) -> some View {
        onGeometryChange(for: FeedRowPosition.self) { proxy in
            FeedRowPosition(
                contentMinY: proxy.frame(in: .named(FeedOffsetKeeper.contentSpace)).minY,
                visualMinY: proxy.frame(in: .named(FloatingDateTracker.coordinateSpace)).minY
            )
        } action: { position in
            keeper.rowDidMove(id, contentMinY: position.contentMinY, visualMinY: position.visualMinY)
        }
        .onDisappear { keeper.rowDidDisappear(id) }
    }

    /// Скрывает эффекты краёв прокрутки iOS 26 (размытие и затемнение под панелями). Для перевёрнутой ленты они
    /// рисуются не у тех краёв: нижний эффект, высота которого — панель ввода вместе с клавиатурой, оказывается
    /// сверху и при открытой клавиатуре затемняет почти всю ленту. Подложку под панелью навигации рисует `ChatView`.
    @ViewBuilder
    func scrollEdgeEffectsHiddenIfAvailable() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }

    /// Сообщает трекеру плавающей даты фазу прокрутки (iOS 18+). На iOS 17 фазы нет — трекер определяет прокрутку
    /// по кадрам строк.
    /// - Parameter tracker: трекер плавающей даты.
    @ViewBuilder
    func scrollPhaseTracking(_ tracker: FloatingDateTracker) -> some View {
        if #available(iOS 18, *) {
            onScrollPhaseChange { _, phase in
                tracker.scrollPhaseDidChange(isActive: phase != .idle)
            }
        } else {
            self
        }
    }

    /// Отражает View по вертикали — для перевёрнутой ленты сообщений.
    func flippedVertically() -> some View {
        scaleEffect(x: 1, y: -1)
    }
}

#Preview {
    let ivan = MessageSenderDisplayModel(name: "Иван Петров", isPlaceholder: false, avatarURL: nil)
    let maria = MessageSenderDisplayModel(name: "Мария", isPlaceholder: false, avatarURL: nil)
    let today = Calendar.current.startOfDay(for: .now)
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
    MessagesListView(
        sections: [
            MessageDaySectionDisplayModel(id: MessageDaySectionID(day: today, occurrence: 0), title: "Сегодня, 15 октября", messages: [
                MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "6"), text: "Ты где?", isUnsupported: false, isOutgoing: true, sender: nil, time: nil, editedLabel: nil, deliveryState: .failed, deliveryStateLabel: "Не отправлено", actions: [.retrySending, .deleteUnsent]),
                MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "5"), text: "Я уже на месте", isUnsupported: false, isOutgoing: true, sender: ivan, time: nil, editedLabel: nil, deliveryState: .sending, deliveryStateLabel: "Отправляется", actions: []),
                MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "4"), text: "Отлично, до встречи!", isUnsupported: false, isOutgoing: true, sender: ivan, time: "12:05", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil, actions: []),
                MessageDisplayModel(id: MessageClientKey(senderId: 2, clientId: "3"), text: "Давай в 7 у входа", isUnsupported: false, isOutgoing: false, sender: maria, time: "12:04", editedLabel: "Изменено", deliveryState: .delivered, deliveryStateLabel: nil, actions: []),
            ]),
            MessageDaySectionDisplayModel(id: MessageDaySectionID(day: yesterday, occurrence: 0), title: "Вчера, 14 октября", messages: [
                MessageDisplayModel(id: MessageClientKey(senderId: 2, clientId: "2"), text: "Привет!", isUnsupported: false, isOutgoing: false, sender: maria, time: "21:03", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil, actions: []),
                MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "1"), text: "Привет! Во сколько встречаемся?", isUnsupported: false, isOutgoing: true, sender: ivan, time: "21:01", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil, actions: []),
            ]),
        ],
        isLoadingOlder: true,
        onAppear: { _ in },
        onAction: { _, _ in }
    )
}
