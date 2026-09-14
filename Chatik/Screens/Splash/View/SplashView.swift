//
//  SplashView.swift
//  Chatik
//

import SwiftUI

/// Экран загрузки: показывается, пока приложение восстанавливает сессию при старте.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                logo
                Text(SplashStrings.title)
                    .font(.largeTitle.bold())
            }

            VStack {
                Spacer()
                loadingIndicator
                    .padding(.bottom, 48)
            }
        }
    }

    private var logo: some View {
        Image(systemName: "bubble.left.and.bubble.right.fill")
            .font(.system(size: 72))
            .foregroundStyle(.tint)
            .symbolRenderingMode(.hierarchical)
    }

    private var loadingIndicator: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(SplashStrings.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SplashView()
}
