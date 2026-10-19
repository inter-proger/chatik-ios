//
//  MessagesListView.swift
//  Chatik
//

import SwiftUI

/// Лента сообщений по дням: самые новые внизу, более старые подгружаются при прокрутке вверх. Над сообщениями
/// каждого дня — заголовок с датой, а во время прокрутки поверх ленты — плавающая дата верхних сообщений
/// (`FloatingDateHeaderView`).
///
/// Прокрутка перевёрнута: `ScrollView` и каждая строка отражены по вертикали. Так лента начинается с самых новых
/// сообщений без ручной прокрутки, а подгруженные старые дописываются в конец данных (визуально — сверху)
/// и не сдвигают то, что сейчас на экране. Поэтому заголовок дня идёт в данных после сообщений своей секции —
/// визуально он над ними. Pull-to-refresh (`.refreshable` у родителя) тоже переворачивается: индикатор появляется
/// внизу ленты, а обновление запускается, если потянуть ленту вверх от самых новых сообщений.
///
/// Секции и строки — плоские `ForEach` внутри одного `LazyVStack`: обёртка дня в `VStack` выключила бы ленивую
/// загрузку внутри дня, а за день бывают сотни сообщений.
struct MessagesListView: View {
    /// Секции по дням, сначала самые новые.
    let sections: [MessageDaySectionDisplayModel]
    let isLoadingOlder: Bool
    let onAppear: (MessageDisplayModel) -> Void
    /// `clientId` неотправленного сообщения, у пузыря которого показан выбор «повторить / удалить». `nil` — выбор скрыт.
    @Binding var failedActionsClientId: String?
    /// Тап по неотправленному сообщению.
    let onTapFailed: (MessageDisplayModel) -> Void
    /// Выбрано «повторить» у неотправленного сообщения.
    let onRetry: (MessageDisplayModel) -> Void
    /// Выбрано «удалить» у неотправленного сообщения.
    let onDelete: (MessageDisplayModel) -> Void
    /// Выбран пункт меню по долгому нажатию на сообщение.
    let onAction: (MessageAction, MessageDisplayModel) -> Void

    @State private var tracker = FloatingDateTracker()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(sections) { section in
                    ForEach(section.messages) { message in
                        MessageBubbleView(
                            message: message,
                            isShowingFailedActions: isShowingFailedActions(for: message),
                            onTapFailed: { onTapFailed(message) },
                            onRetry: { onRetry(message) },
                            onDelete: { onDelete(message) },
                            onAction: { onAction($0, message) }
                        )
                            .flippedVertically()
                            .onAppear { onAppear(message) }
                            .trackFrame(FloatingDateRow(kind: .message(message.id), section: section.id), in: tracker)
                    }
                    DateHeaderRow(section: section, tracker: tracker)
                }
                if isLoadingOlder {
                    ProgressView()
                        .padding()
                        .flippedVertically()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .flippedVertically()
        .scrollPhaseTracking(tracker)
        // Пространство — снаружи отражения: кадры строк в нём уже визуальные.
        .coordinateSpace(.named(FloatingDateTracker.coordinateSpace))
        // Клавиатура и поворот меняют высоту ленты и сдвигают строки без жеста.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in tracker.layoutDidChange() }
        .overlay(alignment: .top) { FloatingDateHeaderView(tracker: tracker) }
        // Только заголовки, а не сами секции: сравнение всей ленты с сообщениями на каждом `body` шло бы на main.
        .onChange(of: sectionTitles, initial: true) { _, titles in tracker.setTitles(titles) }
        .onChange(of: isLoadingOlder) { tracker.layoutDidChange() }
        .scrollEdgeEffectsHiddenIfAvailable()
        .scrollDismissesKeyboard(.interactively)
    }

    /// Показан ли выбор «повторить / удалить» у сообщения. Закрытие выбора сбрасывает `failedActionsClientId`.
    /// - Parameter message: сообщение строки.
    private func isShowingFailedActions(for message: MessageDisplayModel) -> Binding<Bool> {
        Binding(
            get: { failedActionsClientId == message.id.clientId },
            set: { isShowing in
                guard !isShowing, failedActionsClientId == message.id.clientId else { return }
                failedActionsClientId = nil
            }
        )
    }

    /// Заголовки секций для трекера плавающей даты.
    private var sectionTitles: [MessageDaySectionID: String] {
        Dictionary(sections.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Заголовок дня в ленте. Отдельный View: прозрачность под плашкой перерисовывает только этот заголовок, а не всю
/// ленту. Пока плашка видна и закрывает его, заголовок прозрачный — иначе на переходе были бы видны две капсулы.
private struct DateHeaderRow: View {
    let section: MessageDaySectionDisplayModel
    let tracker: FloatingDateTracker

    var body: some View {
        MessageDateHeaderView(title: section.title)
            .opacity(tracker.coveredHeader == section.id ? 0 : 1)
            .flippedVertically()
            .trackFrame(FloatingDateRow(kind: .header, section: section.id), in: tracker)
            // Снаружи `trackFrame`: трекер знает кадр капсулы, и плашка встаёт ровно на место заголовка.
            .padding(.vertical, 8)
    }
}

private extension View {
    /// Скрывает эффекты краёв прокрутки iOS 26 (размытие и затемнение под панелями). Для перевёрнутой ленты они
    /// рисуются не у тех краёв: нижний эффект, высота которого — панель ввода вместе с клавиатурой, оказывается
    /// сверху и при открытой клавиатуре затемняет почти всю ленту. Подложку под панелью навигации рисует `ChatView`.
    @ViewBuilder
    func scrollEdgeEffectsHiddenIfAvailable() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }

    /// Сообщает трекеру плавающей даты фазу прокрутки (iOS 18+). На iOS 17 фазы нет — трекер определяет прокрутку
    /// по кадрам строк.
    /// - Parameter tracker: трекер плавающей даты.
    @ViewBuilder
    func scrollPhaseTracking(_ tracker: FloatingDateTracker) -> some View {
        if #available(iOS 18, *) {
            onScrollPhaseChange { _, phase in
                tracker.scrollPhaseDidChange(isActive: phase != .idle)
            }
        } else {
            self
        }
    }
}

extension View {
    /// Отражает View по вертикали — для перевёрнутой ленты сообщений.
    func flippedVertically() -> some View {
        scaleEffect(x: 1, y: -1)
    }
}

#Preview {
    let ivan = MessageSenderDisplayModel(name: "Иван Петров", isPlaceholder: false, avatarURL: nil)
    let maria = MessageSenderDisplayModel(name: "Мария", isPlaceholder: false, avatarURL: nil)
    let today = Calendar.current.startOfDay(for: .now)
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
    MessagesListView(
        sections: [
            MessageDaySectionDisplayModel(id: MessageDaySectionID(day: today, occurrence: 0), title: "Сегодня, 15 октября", messages: [
                MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "6"), text: "Ты где?", isUnsupported: false, isOutgoing: true, sender: nil, time: nil, editedLabel: nil, deliveryState: .failed, deliveryStateLabel: "Не отправлено", actions: []),
                MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "5"), text: "Я уже на месте", isUnsupported: false, isOutgoing: true, sender: ivan, time: nil, editedLabel: nil, deliveryState: .sending, deliveryStateLabel: "Отправляется", actions: []),
                MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "4"), text: "Отлично, до встречи!", isUnsupported: false, isOutgoing: true, sender: ivan, time: "12:05", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil, actions: []),
                MessageDisplayModel(id: MessageClientKey(senderId: 2, clientId: "3"), text: "Давай в 7 у входа", isUnsupported: false, isOutgoing: false, sender: maria, time: "12:04", editedLabel: "Изменено", deliveryState: .delivered, deliveryStateLabel: nil, actions: []),
            ]),
            MessageDaySectionDisplayModel(id: MessageDaySectionID(day: yesterday, occurrence: 0), title: "Вчера, 14 октября", messages: [
                MessageDisplayModel(id: MessageClientKey(senderId: 2, clientId: "2"), text: "Привет!", isUnsupported: false, isOutgoing: false, sender: maria, time: "21:03", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil, actions: []),
                MessageDisplayModel(id: MessageClientKey(senderId: 1, clientId: "1"), text: "Привет! Во сколько встречаемся?", isUnsupported: false, isOutgoing: true, sender: ivan, time: "21:01", editedLabel: nil, deliveryState: .delivered, deliveryStateLabel: nil, actions: []),
            ]),
        ],
        isLoadingOlder: true,
        onAppear: { _ in },
        failedActionsClientId: .constant(nil),
        onTapFailed: { _ in },
        onRetry: { _ in },
        onDelete: { _ in },
        onAction: { _, _ in }
    )
}
