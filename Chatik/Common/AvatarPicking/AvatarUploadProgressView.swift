//
//  AvatarUploadProgressView.swift
//  Chatik
//

import SwiftUI

/// Прогресс загрузки аватара поверх него: затемнение, кольцо по краю, заполняющееся по мере отправки,
/// и процент в центре. Размер задаётся снаружи — вью растягивается на весь аватар.
struct AvatarUploadProgressView: View {
    /// Доля отправленных данных от 0 до 1.
    let progress: Double

    private let lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.3))
            ring
                // Половина толщины линии — чтобы кольцо не обрезалось краем аватара; затемнение при этом доходит до края.
                .padding(lineWidth / 2)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }

    /// Кольцо по краю: подложка и дуга, заполняющаяся по мере отправки.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.3), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: progress)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach([0, 0.35, 1], id: \.self) { progress in
            AvatarView(url: nil)
                .frame(width: 120, height: 120)
                .overlay { AvatarUploadProgressView(progress: progress) }
        }
    }
}
