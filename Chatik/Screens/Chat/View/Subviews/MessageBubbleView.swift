//
//  MessageBubbleView.swift
//  Chatik
//

import SwiftUI

/// Сообщение в ленте: входящие — слева с аватаром слева, свои — справа на фоне `OutgoingBubble` (акцентный синий,
/// в тёмной теме приглушённый) без аватара и имени. У входящих аватар и имя отправителя есть только у первого
/// сообщения серии; у остальных на месте аватара пустой отступ, чтобы пузыри серии стояли ровно. Ширина пузыря
/// подстраивается под содержимое. Входящий пузырь — от аватара до 32 pt от правого края экрана; свой — в той же
/// полосе, сдвинутой на `outgoingShift` вправо: не ближе 68 pt к левому краю экрана и 16 pt к правому.
///
/// В подвале пузыря — время (дату показывает заголовок дня), а у своего серверного сообщения ещё и галочки: одна —
/// доставлено, две — прочитано хотя бы одним собеседником. У отправляющегося сообщения на месте времени
/// часы, у неотправленного — светло-розовое «Не отправлено» и красный значок слева от пузыря. Высота подвала одна
/// при любом состоянии — пузырь не прыгает при смене статуса.
///
/// Долгое нажатие на пузырь у сообщения с действиями (`MessageDisplayModel.actions`) сообщает экрану
/// `onMenuRequest`: меню показывает экран (`MessageMenuController`). У неотправленного сообщения меню («повторить /
/// удалить») открывает и тап по пузырю или по красному значку рядом с ним. Тапы по остальным сообщениям
/// не перехватываются — их обрабатывает лента (убирает клавиатуру). Пока меню открыто, пузырь скрыт — на его месте
/// копия в меню. Те же действия доступны VoiceOver списком действий элемента; неотправленное сообщение для VoiceOver —
/// кнопка, двойной тап открывает меню, как тап.
/// Пока экран выключил действия (`areActionsEnabled`, режим редактирования), нет ни меню, ни действий VoiceOver.
struct MessageBubbleView: View {
    let message: MessageDisplayModel
    /// Выбрано действие для VoiceOver.
    var onAction: (MessageAction) -> Void = { _ in }
    /// Долгое нажатие на пузырь или тап по неотправленному; параметр — источник меню с текущим кадром пузыря
    /// на экране.
    var onMenuRequest: (MessageMenuSource) -> Void = { _ in }
    /// Для сообщения открыто меню: пузырь скрыт, на его месте — копия в меню.
    var isHiddenForMenu = false
    /// Экран принимает действия с сообщениями; `false` — режим редактирования, действия скрыты у всех сообщений.
    var areActionsEnabled = true

    /// Источник меню для двойного тапа VoiceOver: его записывает детектор жестов пузыря.
    @State private var menuSourceReference = MessageMenuSourceReference()

    private static let avatarSize: CGFloat = 32
    /// Промежуток между аватаром и входящим пузырём.
    private static let avatarSpacing: CGFloat = 8
    /// Отступ пузыря от края ленты со стороны аватара входящих: аватар и промежуток. Ближе к этому краю не подходят
    /// и свои пузыри.
    private static let avatarSideInset: CGFloat = avatarSize + avatarSpacing
    /// Наименьший отступ пузыря от края ленты с другой стороны. Вместе с полем ленты по бокам (12) пузырь
    /// не подходит к краю экрана ближе чем на 32 pt.
    private static let freeSideInset: CGFloat = 20
    /// Сдвиг своих пузырей вправо относительно полосы входящих — с обеих сторон.
    private static let outgoingShift: CGFloat = 16
    /// Промежуток между значком неотправленного сообщения и пузырём.
    private static let failedMarkSpacing: CGFloat = 6
    /// Полоса касания слева от неотправленного пузыря: промежуток и значок с запасом под палец.
    private static let failedMarkHitInset: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isOutgoing {
                Spacer(minLength: Self.avatarSideInset + Self.outgoingShift)
                bubbleWithMenu
                    // Значок — снаружи пузыря, у его нижнего края: ширина пузыря не меняется при смене статуса.
                    .overlay(alignment: .bottomLeading) {
                        failedMark
                            .alignmentGuide(.leading) { $0[.trailing] + Self.failedMarkSpacing }
                    }
                    .padding(.trailing, Self.freeSideInset - Self.outgoingShift)
            } else {
                avatar
                bubbleWithMenu
                    .padding(.leading, Self.avatarSpacing)
                Spacer(minLength: Self.freeSideInset)
            }
        }
        // Отступ отделяет серии друг от друга; внутри серии пузыри идут плотно.
        .padding(.top, message.sender == nil ? 0 : 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(opensMenuOnTap ? .isButton : [])
        .accessibilityAction { openMenuForAccessibility() }
        .accessibilityActions {
            ForEach(actions, id: \.self) { action in
                actionButton(action)
            }
        }
    }

    private var isFailed: Bool {
        message.deliveryState == .failed
    }

    /// Действия, доступные сейчас: действия сообщения, если экран их принимает.
    private var actions: [MessageAction] {
        areActionsEnabled ? message.actions : []
    }

    /// Меню открывает и тап: неотправленное сообщение, пока действия доступны.
    private var opensMenuOnTap: Bool {
        isFailed && !actions.isEmpty
    }

    /// Значок неотправленного сообщения слева от пузыря.
    @ViewBuilder
    private var failedMark: some View {
        if isFailed {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.red)
                // Касание значка получает детектор жестов пузыря под ним.
                .allowsHitTesting(false)
                // Состояние читается из подвала — значок не повторяет его для VoiceOver.
                .accessibilityHidden(true)
        }
    }

    /// Аватар отправителя входящего сообщения у первого сообщения серии, иначе пустое место того же размера.
    @ViewBuilder
    private var avatar: some View {
        if let sender = message.sender {
            AvatarView(url: sender.avatarURL)
                .frame(width: Self.avatarSize, height: Self.avatarSize)
        } else {
            Color.clear
                .frame(width: Self.avatarSize, height: 0)
        }
    }

    /// Пузырь с распознаванием долгого нажатия — только у сообщений с действиями. Условие — в содержимом `overlay`,
    /// а не вокруг пузыря, поэтому его идентичность не меняется.
    private var bubbleWithMenu: some View {
        MessageBubble(message: message)
            .opacity(isHiddenForMenu ? 0 : 1)
            // Без анимации: пузырь сменяет копию в меню сразу. Иначе он проявлялся бы вместе с анимацией режима
            // редактирования, которую включает выбранное «Редактировать», и на месте пузыря мелькала бы пустота.
            .transaction(value: isHiddenForMenu) { $0.animation = nil }
            .overlay {
                if !actions.isEmpty {
                    MessageLongPressDetector(
                        opensOnTap: opensMenuOnTap,
                        leadingHitInset: opensMenuOnTap ? Self.failedMarkHitInset : 0,
                        sourceReference: menuSourceReference,
                        onMenuRequest: onMenuRequest
                    )
                    // У неотправленного детектор заходит влево на значок: тап по значку тоже открывает меню.
                    .padding(.leading, opensMenuOnTap ? -Self.failedMarkHitInset : 0)
                }
            }
    }

    /// Двойной тап VoiceOver: у неотправленного сообщения открывает меню, как тап.
    private func openMenuForAccessibility() {
        guard opensMenuOnTap, let source = menuSourceReference.source else { return }
        onMenuRequest(source)
    }

    /// Действие с сообщением для VoiceOver.
    /// - Parameter action: действие.
    private func actionButton(_ action: MessageAction) -> some View {
        Button(action.title, systemImage: action.systemImage, role: action.isDestructive ? .destructive : nil) {
            onAction(action)
        }
    }
}

/// Пузырь сообщения без окружения: имя отправителя (только у входящих), текст, время и пометка о редактировании.
/// Его же копию показывает меню сообщения.
struct MessageBubble: View {
    let message: MessageDisplayModel

    /// Радиус скругления пузыря.
    static let cornerRadius: CGFloat = 16

    var body: some View {
        MessageBubbleLayout(spacing: 4) {
            // У своих сообщений `sender` нужен только для отступа между сериями: своё имя не показывается.
            if !message.isOutgoing, let sender = message.sender {
                Text(sender.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .redacted(reason: sender.isPlaceholder ? .placeholder : [])
            }
            Text(message.text)
                .italic(message.isUnsupported)
            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(message.isOutgoing ? Color.white : Color.primary)
        .background(message.isOutgoing ? Color.outgoingBubble : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }

    /// Подвал пузыря: время или состояние доставки. Выводится всегда и последним элементом раскладки — к правому
    /// краю прижат он, а не текст. Размер задаёт невидимый образец того же шрифта: высота одна и та же у времени,
    /// часов и «Не отправлено», а у своих сообщений в образце есть и две галочки — переходы «отправляется →
    /// доставлено → прочитано» не меняют ширину пузыря.
    private var footer: some View {
        ZStack(alignment: .trailing) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: "00:00")
                if message.isOutgoing {
                    DeliveryCheckmarksView(isRead: true)
                }
            }
            .hidden()
            .accessibilityHidden(true)
            footerContent
        }
        .font(.caption2)
    }

    /// Содержимое подвала по состоянию доставки.
    @ViewBuilder
    private var footerContent: some View {
        switch message.deliveryState {
        case .delivered, .read:
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let editedLabel = message.editedLabel {
                    Text(editedLabel)
                }
                if let time = message.time {
                    Text(time)
                }
                if message.isOutgoing {
                    DeliveryCheckmarksView(isRead: message.deliveryState == .read)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(message.deliveryStateLabel ?? "")
                }
            }
            .opacity(0.7)
        case .sending:
            Image(systemName: "clock")
                // Не выше строки времени: высота подвала не меняется.
                .imageScale(.small)
                .opacity(0.7)
                .accessibilityLabel(message.deliveryStateLabel ?? "")
        case .failed:
            // Светло-розовый, а не красный: красный на синем пузыре почти не читается (контраст 1,1:1).
            // Красный сигнал ошибки даёт значок слева от пузыря.
            Text(message.deliveryStateLabel ?? "")
                .foregroundStyle(Color.failedLabel)
        }
    }
}

/// Раскладка содержимого пузыря: элементы друг под другом, ширина — по самому широкому из них (не шире
/// предложенной), последний элемент (время) прижат к правому краю, остальные — к левому.
///
/// Обычный `VStack` так не умеет: чтобы прижать время вправо, ему нужен `.frame(maxWidth: .infinity)`,
/// и тогда пузырь растягивается на всю доступную ширину, а не по тексту.
private struct MessageBubbleLayout: Layout {
    let spacing: CGFloat

    /// Размер пузыря: ширина самого широкого элемента, высота — сумма высот с промежутками.
    /// - Parameters:
    ///   - proposal: предложенный родителем размер; по его ширине переносится текст.
    ///   - subviews: элементы пузыря.
    ///   - cache: не используется.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = sizes(of: subviews, width: proposal.width)
        let width = sizes.map(\.width).max() ?? 0
        let height = sizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(sizes.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    /// Расставляет элементы сверху вниз: последний — по правому краю, остальные — по левому.
    /// - Parameters:
    ///   - bounds: область пузыря.
    ///   - proposal: предложенный родителем размер.
    ///   - subviews: элементы пузыря.
    ///   - cache: не используется.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = sizes(of: subviews, width: bounds.width)
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            let isLast = index == subviews.count - 1
            let x = isLast ? bounds.maxX - size.width : bounds.minX
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            y += size.height + spacing
        }
    }

    /// Размеры элементов при заданной ширине: длинный текст переносится, имя обрезается.
    /// - Parameters:
    ///   - subviews: элементы пузыря.
    ///   - width: доступная ширина; `nil` — без ограничения.
    private func sizes(of subviews: Subviews, width: CGFloat?) -> [CGSize] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
    }
}

#Preview {
    let ivan = MessageSenderDisplayModel(name: "Иван Петров", isPlaceholder: false, avatarURL: nil)
    VStack(spacing: 0) {
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "1"), text: "Привет!", isUnsupported: false, isOutgoing: true, sender: ivan, time: "12:01", editedLabel: nil, deliveryState: .read, deliveryStateLabel: "Прочитано", actions: []))
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "6"), text: "Я на месте", isUnsupported: false, isOutgoing: true, sender: nil, time: "12:01", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: "Доставлено", actions: []))
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "2"), text: "Как дела?", isUnsupported: false, isOutgoing: true, sender: nil, time: nil, editedLabel: nil, deliveryState: .sending, deliveryStateLabel: "Отправляется", actions: []))
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "3"), text: "Ты тут?", isUnsupported: false, isOutgoing: true, sender: nil, time: nil, editedLabel: nil, deliveryState: .failed, deliveryStateLabel: "Не отправлено", actions: [.retrySending, .deleteUnsent]))
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 2, clientId: "4"), text: "Ок", isUnsupported: false, isOutgoing: false, sender: MessageSenderDisplayModel(name: "Мария Александровна Константинопольская-Вознесенская", isPlaceholder: false, avatarURL: nil), time: "12:02", editedLabel: "Изменено", deliveryState: .delivered, deliveryStateLabel: nil, actions: []))
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 3, clientId: "5"), text: "Сообщение не поддерживается", isUnsupported: true, isOutgoing: false, sender: MessageSenderDisplayModel(name: "Загрузка…", isPlaceholder: true, avatarURL: nil), time: "12:03", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil, actions: []))
    }
    .padding()
}
