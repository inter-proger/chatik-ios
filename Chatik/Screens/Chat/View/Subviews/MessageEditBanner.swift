//
//  MessageEditBanner.swift
//  Chatik
//

import SwiftUI

/// Плашка над полем ввода в режиме редактирования: акцентная черта, значок карандаша, заголовок «Редактирование»
/// и текст редактируемого сообщения в одну строку, справа — крестик, выключающий режим. Во время запроса крестик
/// скрыт прозрачностью, а не убран: высота и раскладка плашки не меняются.
struct MessageEditBanner: View {
    /// Текст редактируемого сообщения в одну строку.
    let text: String
    /// Идёт запрос правки: крестик скрыт и недоступен.
    let isSubmitting: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(width: 2)
            Image(systemName: "pencil")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(ChatStrings.editTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            cancelButton
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// Крестик, выключающий режим редактирования.
    private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .opacity(isSubmitting ? 0 : 1)
        .disabled(isSubmitting)
        .accessibilityLabel(ChatStrings.editCancel)
        .accessibilityHidden(isSubmitting)
    }
}

#Preview {
    VStack {
        MessageEditBanner(text: "Давай в 7 у входа", isSubmitting: false, onCancel: {})
        MessageEditBanner(text: "Очень длинное сообщение, которое не помещается в одну строку плашки", isSubmitting: true, onCancel: {})
    }
    .background(.bar)
}
