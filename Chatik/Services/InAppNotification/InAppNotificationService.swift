//
//  InAppNotificationService.swift
//  Chatik
//

import Foundation

/// Показ уведомлений поверх приложения: всегда последнее, на время `duration`, только в активном приложении.
///
/// Сцен (окон на iPad) может быть несколько: сервис активен, пока активна хотя бы одна, а уведомление показывается
/// в последней ставшей активной — `presentingSceneId`.
@MainActor
protocol InAppNotificationServiceProtocol: AnyObject, Observable, AuthServiceObserver {
    /// Показанное уведомление; `nil` — ничего не показано. Отслеживается Observation.
    var current: InAppNotification? { get }
    /// Активна ли хотя бы одна сцена приложения. Отслеживается Observation.
    var isActive: Bool { get }
    /// Сцена, в окне которой показывается уведомление: последняя ставшая активной; `nil` — активных сцен нет.
    /// Отслеживается Observation: её смена убирает уведомление без анимации.
    var presentingSceneId: UUID? { get }
    /// Активна ли сцена: свёрнутая или неактивная сцена пользователю не видна.
    /// - Parameter sceneId: идентификатор сцены.
    func isSceneActive(_ sceneId: UUID) -> Bool
    /// Показывает уведомление вместо прежнего и запускает таймер. С тем же содержимым — только перезапускает таймер
    /// показанного (на паузе — не запускает).
    /// - Returns: `false` — приложение неактивно, уведомление отброшено.
    @discardableResult
    func show(_ notification: InAppNotification) -> Bool
    /// Скрывает уведомление `id`, если оно ещё показано (свайп, нажатие).
    func dismiss(id: InAppNotification.ID)
    /// Останавливает таймер уведомления `id`: палец на карточке.
    func pauseTimer(id: InAppNotification.ID)
    /// Снимает паузу и запускает таймер уведомления `id` заново на полное время.
    func resumeTimer(id: InAppNotification.ID)
    /// Активность сцены. Пока активных сцен нет, новые уведомления отбрасываются; смена сцены показа (уход её
    /// из `.active` или активация другой) убирает показанное. Сервис создаётся без активных сцен.
    /// - Parameters:
    ///   - isActive: сцена в `.active`.
    ///   - sceneId: идентификатор сцены.
    func setActive(_ isActive: Bool, sceneId: UUID)
}

extension InAppNotificationServiceProtocol {
    /// Показывает ошибку единого вида.
    /// - Parameter message: текст ошибки, готовый к показу.
    /// - Returns: `false` — приложение неактивно, ошибка отброшена.
    @discardableResult
    func showError(_ message: String) -> Bool {
        show(InAppNotification(content: .error(message: message)))
    }
}

/// Уведомления поверх приложения. Очереди нет: новое заменяет показанное сразу, повтор того же содержимого только
/// продлевает показ. Таймер стоит, пока палец на карточке. Уход сцены показа из `.active`, активация другой сцены
/// и выход из аккаунта убирают показанное.
@MainActor
@Observable
final class InAppNotificationService: InAppNotificationServiceProtocol {
    typealias Sleep = @MainActor (Duration) async throws -> Void

    private(set) var current: InAppNotification?
    /// Активные сцены в порядке активации: последняя — сцена показа.
    private var activeSceneIds: [UUID] = []
    /// Таймер показанного стоит: палец на карточке.
    @ObservationIgnored private var isPaused = false
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private let sleep: Sleep

    /// - Parameter sleep: ожидание таймера; в тестах — управляемое.
    init(sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    @discardableResult
    func show(_ notification: InAppNotification) -> Bool {
        guard isActive else { return false }
        guard let current, current.content == notification.content else {
            replace(with: notification)
            return true
        }
        guard !isPaused else { return true }
        startTimer(for: current)
        return true
    }

    func dismiss(id: InAppNotification.ID) {
        guard current?.id == id else { return }
        hide()
    }

    func pauseTimer(id: InAppNotification.ID) {
        guard current?.id == id else { return }
        isPaused = true
        stopTimer()
    }

    func resumeTimer(id: InAppNotification.ID) {
        guard let current, current.id == id, isPaused else { return }
        isPaused = false
        startTimer(for: current)
    }

    var isActive: Bool { !activeSceneIds.isEmpty }

    var presentingSceneId: UUID? { activeSceneIds.last }

    func isSceneActive(_ sceneId: UUID) -> Bool {
        activeSceneIds.contains(sceneId)
    }

    func setActive(_ isActive: Bool, sceneId: UUID) {
        var sceneIds = activeSceneIds.filter { $0 != sceneId }
        if isActive {
            sceneIds.append(sceneId)
        }
        guard sceneIds != activeSceneIds else { return }
        let presentingSceneId = presentingSceneId
        activeSceneIds = sceneIds
        guard self.presentingSceneId != presentingSceneId else { return }
        hide()
    }

    /// Уведомление прошлой сессии не остаётся на экране после выхода.
    func authServiceWillLogout() async {
        hide()
    }

    /// Показывает новое уведомление вместо прежнего; пауза прежнего к новому не относится.
    /// - Parameter notification: новое уведомление.
    private func replace(with notification: InAppNotification) {
        isPaused = false
        current = notification
        startTimer(for: notification)
    }

    /// Убирает показанное уведомление и его таймер.
    private func hide() {
        stopTimer()
        isPaused = false
        current = nil
    }

    /// Запускает таймер заново: по истечении `duration` уведомление скрывается, если его ещё не заменили.
    /// Отменённый таймер не скрывает ничего, даже если ожидание успело завершиться: пауза и повтор того же
    /// содержимого сохраняют `id`, и сверки по нему недостаточно.
    /// - Parameter notification: показанное уведомление.
    private func startTimer(for notification: InAppNotification) {
        stopTimer()
        let id = notification.id
        timer = Task { [weak self, sleep] in
            do {
                try await sleep(notification.duration)
            } catch {
                return
            }
            guard let self, !Task.isCancelled, current?.id == id else { return }
            hide()
        }
    }

    /// Отменяет таймер показанного уведомления.
    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
}
