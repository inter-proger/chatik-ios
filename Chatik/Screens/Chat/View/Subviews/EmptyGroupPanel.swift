//
//  EmptyGroupPanel.swift
//  Chatik
//

import SwiftUI

/// Плавающая панель поверх ленты группы без других участников: текст, «Добавить» и крестик.
struct EmptyGroupPanel: View {
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(ChatStrings.emptyGroupTitle)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(ChatStrings.emptyGroupAdd, action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ChatStrings.emptyGroupDismiss)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

#Preview {
    EmptyGroupPanel(onAdd: {}, onDismiss: {})
}
