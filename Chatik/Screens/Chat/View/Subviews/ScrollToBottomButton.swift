//
//  ScrollToBottomButton.swift
//  Chatik
//

import SwiftUI

/// Круглая кнопка со стрелкой вниз над лентой; счётчик непрочитанных — в её правом верхнем углу, частично
/// перекрывая круг.
struct ScrollToBottomButton: View {
    /// Счётчик непрочитанных; `nil` — счётчика нет.
    let badgeText: String?
    /// Непрочитанные для VoiceOver — с точным числом.
    let accessibilityValue: String?
    let action: () -> Void

    /// Насколько правый верхний угол счётчика выступает за правый верхний угол рамки круга: `width` — вправо,
    /// `height` — вверх. Отрицательные значения сдвигают счётчик внутрь круга.
    private static let badgeOverhang = CGSize(width: 5, height: 5)

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                // Внутри кнопки: нажатие на счётчик — нажатие на кнопку.
                .overlay(alignment: .topTrailing) {
                    // Направляющие — на `Group`, а не на счётчике внутри `if`: направляющие условного содержимого
                    // `overlay` не учитывает, и счётчик стоял бы ровно в углу при любом `badgeOverhang`.
                    Group {
                        if let badgeText {
                            UnreadBadgeView(text: badgeText)
                                .fixedSize()
                                .accessibilityHidden(true)
                        }
                    }
                    .alignmentGuide(.top) { $0[.top] + Self.badgeOverhang.height }
                    .alignmentGuide(.trailing) { $0[.trailing] - Self.badgeOverhang.width }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ChatStrings.scrollToBottom)
        .accessibilityValue(accessibilityValue ?? "")
    }
}

#Preview {
    HStack(spacing: 24) {
        ScrollToBottomButton(badgeText: nil, accessibilityValue: nil) {}
        ScrollToBottomButton(badgeText: "3", accessibilityValue: nil) {}
        ScrollToBottomButton(badgeText: "99+", accessibilityValue: nil) {}
    }
    .padding(40)
}
