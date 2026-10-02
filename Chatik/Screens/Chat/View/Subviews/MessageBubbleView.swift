//
//  MessageBubbleView.swift
//  Chatik
//

import SwiftUI

/// Сообщение в ленте: исходящие — справа на фоне акцентного цвета с аватаром справа, входящие — слева с аватаром
/// слева. Аватар и имя отправителя есть только у первого сообщения серии; у остальных на месте аватара пустой
/// отступ, чтобы пузыри серии стояли ровно. Ширина пузыря подстраивается под содержимое.
struct MessageBubbleView: View {
    let message: MessageDisplayModel

    private static let avatarSize: CGFloat = 32

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isOutgoing {
                Spacer(minLength: 48)
                bubble
                avatar
            } else {
                avatar
                bubble
                Spacer(minLength: 48)
            }
        }
        // Отступ отделяет серии друг от друга; внутри серии пузыри идут плотно.
        .padding(.top, message.sender == nil ? 0 : 8)
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
        .background(message.isOutgoing ? Color.accentColor : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Время отправки и пометка «изменено».
    private var footer: some View {
        HStack(spacing: 4) {
            if let editedLabel = message.editedLabel {
                Text(editedLabel)
            }
            Text(message.time)
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
    VStack(spacing: 0) {
        MessageBubbleView(message: MessageDisplayModel(id: 1, text: "Привет!", isUnsupported: false, isOutgoing: true, sender: MessageSenderDisplayModel(name: "Иван Петров", isPlaceholder: false, avatarURL: nil), time: "12:01", editedLabel: nil))
        MessageBubbleView(message: MessageDisplayModel(id: 2, text: "Как дела?", isUnsupported: false, isOutgoing: true, sender: nil, time: "12:01", editedLabel: nil))
        MessageBubbleView(message: MessageDisplayModel(id: 3, text: "Ок", isUnsupported: false, isOutgoing: false, sender: MessageSenderDisplayModel(name: "Мария Александровна Константинопольская-Вознесенская", isPlaceholder: false, avatarURL: nil), time: "12:02", editedLabel: "изменено"))
        MessageBubbleView(message: MessageDisplayModel(id: 4, text: "Сообщение не поддерживается", isUnsupported: true, isOutgoing: false, sender: MessageSenderDisplayModel(name: "Загрузка…", isPlaceholder: true, avatarURL: nil), time: "12:03", editedLabel: nil))
    }
    .padding()
}
