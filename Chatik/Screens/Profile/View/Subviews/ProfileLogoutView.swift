//
//  ProfileLogoutView.swift
//  Chatik
//

import SwiftUI

/// Секция с кнопкой выхода из аккаунта. Во время запроса кнопка неактивна, текст скрыт без изменения размера,
/// поверх показан прелоадер.
struct ProfileLogoutView: View {
    let isLoggingOut: Bool
    let onTap: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive, action: onTap) {
                Text(ProfileStrings.logout)
                    .opacity(isLoggingOut ? 0 : 1)
                    .overlay {
                        if isLoggingOut {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity)
            }
            .disabled(isLoggingOut)
        }
    }
}

#Preview {
    List {
        ProfileLogoutView(isLoggingOut: false, onTap: {})
        ProfileLogoutView(isLoggingOut: true, onTap: {})
    }
}
