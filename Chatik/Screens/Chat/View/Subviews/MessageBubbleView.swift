//
//  MessageBubbleView.swift
//  Chatik
//

import SwiftUI

/// Сообщение в ленте: исходящие — справа на фоне `OutgoingBubble` (акцентный синий, в тёмной теме приглушённый)
/// с аватаром справа, входящие — слева с аватаром слева. Аватар и имя отправителя есть только у первого сообщения
/// серии; у остальных на месте аватара пустой отступ, чтобы пузыри серии стояли ровно. Ширина пузыря подстраивается
/// под содержимое.
///
/// У отправляющегося сообщения рядом со временем часы, у неотправленного — красный значок слева от пузыря;
/// тап по неотправленному сообщению вызывает `onTapFailed`. Тапы по остальным сообщениям не перехватываются —
/// их обрабатывает лента (убирает клавиатуру).
struct MessageBubbleView: View {
    let message: MessageDisplayModel
    var onTapFailed: () -> Void = {}

    private static let avatarSize: CGFloat = 32

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isOutgoing {
                Spacer(minLength: 48)
                // Значок ошибки — у нижнего края пузыря.
                HStack(alignment: .bottom, spacing: 6) {
                    failedMark
                    bubble
                }
                avatar
            } else {
                avatar
                bubble
                Spacer(minLength: 48)
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
                .accessibilityLabel(message.deliveryStateLabel ?? "")
        }
    }

    /// Аватар отправителя у первого сообщения серии, иначе пустое место того же размера.
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

    /// Пузырь сообщения: имя отправителя, текст, время и пометка о редактировании.
    private var bubble: some View {
        MessageBubbleLayout(spacing: 4) {
            if let sender = message.sender {
                Text(sender.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(message.isOutgoing ? Color.white : Color.accentColor)
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

    /// Время отправки, пометка «изменено» и часы, пока сообщение отправляется.
    private var footer: some View {
        HStack(spacing: 4) {
            if let editedLabel = message.editedLabel {
                Text(editedLabel)
            }
            Text(message.time)
            if message.deliveryState == .sending {
                Image(systemName: "clock")
                    .accessibilityLabel(message.deliveryStateLabel ?? "")
            }
        }
        .font(.caption2)
        .opacity(0.7)
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
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "2"), text: "Как дела?", isUnsupported: false, isOutgoing: true, sender: nil, time: "12:01", editedLabel: nil, deliveryState: .sending, deliveryStateLabel: "Отправляется"))
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "3"), text: "Ты тут?", isUnsupported: false, isOutgoing: true, sender: nil, time: "12:02", editedLabel: nil, deliveryState: .failed, deliveryStateLabel: "Не отправлено"))
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 2, clientId: "4"), text: "Ок", isUnsupported: false, isOutgoing: false, sender: MessageSenderDisplayModel(name: "Мария Александровна Константинопольская-Вознесенская", isPlaceholder: false, avatarURL: nil), time: "12:02", editedLabel: "изменено", deliveryState: .delivered, deliveryStateLabel: nil))
        MessageBubbleView(message: MessageDisplayModel(id: MessageClientKey(senderId: 3, clientId: "5"), text: "Сообщение не поддерживается", isUnsupported: true, isOutgoing: false, sender: MessageSenderDisplayModel(name: "Загрузка…", isPlaceholder: true, avatarURL: nil), time: "12:03", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil))
    }
    .padding()
}
