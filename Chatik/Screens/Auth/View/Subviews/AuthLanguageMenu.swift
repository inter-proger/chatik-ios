//
//  AuthLanguageMenu.swift
//  Chatik
//

import SwiftUI

/// Кнопка-меню выбора языка интерфейса: иконка глобуса, в меню — список языков с отметкой текущего.
struct AuthLanguageMenu: View {
    let selected: AppLanguage
    let onSelect: (AppLanguage) -> Void

    var body: some View {
        Menu {
            Picker(AuthStrings.language, selection: selection) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
        } label: {
            Label(AuthStrings.language, systemImage: "globe")
        }
    }

    /// Binding для Picker: читает выбранный язык, запись пробрасывает в `onSelect`.
    private var selection: Binding<AppLanguage> {
        Binding(get: { selected }, set: onSelect)
    }
}

#Preview {
    NavigationStack {
        Text("Preview")
            .toolbar {
                AuthLanguageMenu(selected: .ru, onSelect: { _ in })
            }
    }
}
