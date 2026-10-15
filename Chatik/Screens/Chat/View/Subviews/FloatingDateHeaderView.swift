//
//  FloatingDateHeaderView.swift
//  Chatik
//

import SwiftUI

/// Плавающая дата поверх ленты: видна во время прокрутки, когда заголовок дня верхних сообщений ушёл за верхний
/// край. Неотличима от заголовка в ленте — это тот же `MessageDateHeaderView`. Касаний не принимает, а для VoiceOver
/// скрыта: это дубль заголовка в ленте.
struct FloatingDateHeaderView: View {
    let tracker: FloatingDateTracker

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if tracker.isVisible, let title = tracker.title {
                MessageDateHeaderView(title: title)
                    // Смена даты на видимой плашке — перекрёстным затуханием текста, без повторного появления.
                    .contentTransition(.opacity)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, FloatingDateTracker.topInset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
