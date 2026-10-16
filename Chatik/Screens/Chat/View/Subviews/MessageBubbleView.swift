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
/// В подвале пузыря — только время (дату показывает заголовок дня). У отправляющегося сообщения на месте времени
/// часы, у неотправленного — светло-розовое «Не отправлено» и красный значок слева от пузыря; тап по неотправленному
/// сообщению вызывает `onTapFailed`. Высота подвала одна при любом состоянии — пузырь не прыгает при смене статуса.
/// Тапы по остальным сообщениям не перехватываются — их обрабатывает лента (убирает клавиатуру).
///
/// Выбор «повторить / удалить» привязан к пузырю, а не к экрану: на iOS 26 он всплывает от пузыря, до iOS 26 —
/// обычным листом снизу.
struct MessageBubbleView: View {
    let message: MessageDisplayModel
    /// Показан выбор «повторить / удалить» у неотправленного сообщения.
    var isShowingFailedActions: Binding<Bool> = .constant(false)
    var onTapFailed: () -> Void = {}
    var onRetry: () -> Void = {}
    var onDelete: () -> Void = {}

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

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.isOutgoing {
                Spacer(minLength: Self.avatarSideInset + Self.outgoingShift)
                bubble
                    .confirmationDialog(
                        ChatStrings.failedActionsTitle,
                        isPresented: isShowingFailedActions,
                        titleVisibility: .visible
                    ) {
                        Button(ChatStrings.failedActionsRetry, action: onRetry)
                        Button(ChatStrings.failedActionsDelete, role: .destructive, action: onDelete)
                    }
                    // Значок — снаружи пузыря, у его нижнего края: ширина пузыря не меняется при смене статуса.
                    .overlay(alignment: .bottomLeading) {
                        failedMark
                            .alignmentGuide(.leading) { $0[.trailing] + Self.failedMarkSpacing }
                    }
                    .padding(.trailing, Self.freeSideInset - Self.outgoingShift)
            } else {
                avatar
                bubble
                    .padding(.leading, Self.avatarSpacing)
                Spacer(minLength: Self.freeSideInset)
            }
        }
        // Отступ отделяет серии друг от друга; внутри серии пузыри идут плотно.
        .padding(.top, message.sender == nil ? 0 : 8)
        .contentShape(Rectangle())
        // Жест включается только у неотправленного сообщения, без смены структуры View: при повторной отправке
        // пузырь не пересоздаётся.
        .gesture(TapGesture().onEnded(onTapFailed), including: isFailed ? .all : .subviews)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isFailed ? .isButton : [])
    }

    private var isFailed: Bool {
        message.deliveryState == .failed
    }

    /// Значок неотправленного сообщения слева от пузыря.
    @ViewBuilder
    private var failedMark: some View {
        if isFailed {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.red)
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

    /// Пузырь сообщения: имя отправителя (только у входящих), текст, время и пометка о редактировании.
    private var bubble: some View {
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
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Подвал пузыря: время или состояние доставки. Выводится всегда и последним элементом раскладки — к правому
    /// краю прижат он, а не текст. Высоту задаёт невидимая строка времени того же шрифта, поэтому она одна
    /// и та же у времени, часов и «Не отправлено».
    private var footer: some View {
        ZStack(alignment: .trailing) {
            Text(verbatim: "00:00")
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
        case .delivered:
            HStack(spacing: 4) {
                if let editedLabel = message.editedLabel {
                    Text(editedLabel)
                }
                if let time = message.time {
                    Text(time)
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
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "1"), text: "Привет!", isUnsupported: false, isOutgoing: true, sender: ivan, time: "12:01", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil))
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "2"), text: "Как дела?", isUnsupported: false, isOutgoing: true, sender: nil, time: nil, editedLabel: nil, deliveryState: .sending, deliveryStateLabel: "Отправляется"))
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "3"), text: "Ты тут?", isUnsupported: false, isOutgoing: true, sender: nil, time: nil, editedLabel: nil, deliveryState: .failed, deliveryStateLabel: "Не отправлено"))
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 2, clientId: "4"), text: "Ок", isUnsupported: false, isOutgoing: false, sender: MessageSenderDisplayModel(name: "Мария Александровна Константинопольская-Вознесенская", isPlaceholder: false, avatarURL: nil), time: "12:02", editedLabel: "изменено", deliveryState: .delivered, deliveryStateLabel: nil))
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 3, clientId: "5"), text: "Сообщение не поддерживается", isUnsupported: true, isOutgoing: false, sender: MessageSenderDisplayModel(name: "Загрузка…", isPlaceholder: true, avatarURL: nil), time: "12:03", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil))
    }
    .padding()
}
