//
//  InAppNotificationServiceTests.swift
//  ChatikTests
//

import SwiftUI
import XCTest
@testable import Chatik

@MainActor
final class InAppNotificationServiceTests: XCTestCase {
    private var sleeper: SleepController!
    private var sut: InAppNotificationService!
    private let duration: Duration = .seconds(2)
    private let sceneA = UUID()
    private let sceneB = UUID()

    override func setUp() async throws {
        try await super.setUp()
        sleeper = SleepController()
        sut = InAppNotificationService(sleep: { [sleeper] in try await sleeper!.sleep($0) })
        sut.setActive(true, sceneId: sceneA)
    }

    override func tearDown() async throws {
        sut = nil
        sleeper = nil
        try await super.tearDown()
    }

    /// Уведомление-ошибка с фиксированным временем показа.
    /// - Parameter message: текст ошибки.
    private func error(_ message: String) -> InAppNotification {
        InAppNotification(content: .error(message: message), duration: duration)
    }

    /// Дожидается, пока таймер запросит очередное ожидание.
    /// - Parameter count: сколько ожиданий должно быть запрошено всего.
    private func waitForTimer(count: Int) async {
        await yieldUntil { self.sleeper.requested.count == count }
    }

    // MARK: - Показ и таймер

    /// Кейс: сервис только создан, приложение ещё не сообщило об активности.
    /// Ожидание: уведомление отброшено, `show` вернул `false`.
    func test_show_beforeActivation_isIgnored() {
        let sut = InAppNotificationService(sleep: { _ in })

        let isShown = sut.show(error("Ошибка"))

        XCTAssertFalse(isShown)
        XCTAssertNil(sut.current)
    }

    /// Кейс: активное приложение, показано уведомление.
    /// Ожидание: оно текущее, `show` вернул `true`, таймер запросил время показа уведомления.
    func test_show_makesNotificationCurrent() async {
        let notification = error("Ошибка")

        let isShown = sut.show(notification)

        XCTAssertTrue(isShown)
        XCTAssertEqual(sut.current?.id, notification.id)
        await waitForTimer(count: 1)
        XCTAssertEqual(sleeper.requested, [duration])
    }

    /// Кейс: уведомление показано, время показа вышло.
    /// Ожидание: уведомление скрыто.
    func test_timer_hidesNotification() async {
        sleeper.allow(duration)

        sut.show(error("Ошибка"))

        await yieldUntil { self.sut.current == nil }
    }

    /// Кейс: во время показа пришло уведомление с другим содержимым.
    /// Ожидание: новое заменяет показанное сразу.
    func test_show_differentContent_replacesCurrent() {
        sut.show(error("Первая"))
        let second = error("Вторая")

        sut.show(second)

        XCTAssertEqual(sut.current?.id, second.id)
    }

    /// Кейс: уведомление заменено новым, а таймер заменённого всё же досчитал (ожидание завершилось без отмены).
    /// Ожидание: новое остаётся на экране — таймер скрывает только своё уведомление.
    func test_replacedTimer_doesNotHideNewNotification() async {
        let shortDuration: Duration = .seconds(1)
        sleeper.allow(shortDuration)
        sut.show(InAppNotification(content: .error(message: "Первая"), duration: shortDuration))
        let second = error("Вторая")

        sut.show(second)
        await waitForTimer(count: 2)
        await yieldTimes()

        XCTAssertEqual(sut.current?.id, second.id)
    }

    /// Кейс: ожидание таймера завершилось, но до его возврата на main палец лёг на карточку — таймер отменён.
    /// Ожидание: уведомление остаётся: отменённый таймер не скрывает его, хотя `id` тот же.
    func test_cancelledTimer_afterSleepFinished_doesNotHide() async {
        sleeper.allow(duration)
        let notification = error("Ошибка")
        sut.show(notification)

        sut.pauseTimer(id: notification.id)
        await waitForTimer(count: 1)
        await yieldTimes()

        XCTAssertEqual(sut.current?.id, notification.id)
    }

    /// Кейс: ожидание таймера завершилось, но до его возврата на main пришло уведомление с тем же содержимым.
    /// Ожидание: уведомление остаётся — его продлевает новый таймер, а прежний, отменённый, не скрывает.
    func test_cancelledTimer_afterSameContentRestart_doesNotHide() async {
        sleeper.allow(duration)
        let notification = error("Ошибка")
        sut.show(notification)

        sut.show(error("Ошибка"))
        await waitForTimer(count: 2)
        await yieldTimes()

        XCTAssertEqual(sut.current?.id, notification.id)
    }

    /// Кейс: во время показа пришло уведомление с тем же содержимым.
    /// Ожидание: показанное остаётся с прежним `id`, таймер запущен заново; по его истечении уведомление скрыто.
    func test_show_sameContent_restartsTimerOnly() async {
        let first = error("Ошибка")
        sut.show(first)
        await waitForTimer(count: 1)
        sleeper.allow(duration)

        sut.show(error("Ошибка"))

        XCTAssertEqual(sut.current?.id, first.id)
        await yieldUntil { self.sut.current == nil }
        XCTAssertEqual(sleeper.requested, [duration, duration])
    }

    // MARK: - Пауза

    /// Кейс: палец на карточке — таймер на паузе.
    /// Ожидание: таймер отменён и не перезапускается, уведомление остаётся.
    func test_pauseTimer_keepsNotification() async {
        let notification = error("Ошибка")
        sut.show(notification)
        await waitForTimer(count: 1)
        sleeper.allow(duration)

        sut.pauseTimer(id: notification.id)
        await yieldTimes()

        XCTAssertEqual(sut.current?.id, notification.id)
        XCTAssertEqual(sleeper.requested.count, 1)
    }

    /// Кейс: таймер на паузе, палец отпустили.
    /// Ожидание: таймер запущен заново на полное время, по его истечении уведомление скрыто.
    func test_resumeTimer_restartsFullDuration() async {
        let notification = error("Ошибка")
        sut.show(notification)
        await waitForTimer(count: 1)
        sut.pauseTimer(id: notification.id)
        sleeper.allow(duration)

        sut.resumeTimer(id: notification.id)

        await yieldUntil { self.sut.current == nil }
        XCTAssertEqual(sleeper.requested, [duration, duration])
    }

    /// Кейс: таймер на паузе, пришло уведомление с тем же содержимым; затем палец отпустили.
    /// Ожидание: на паузе таймер не запускается; после отпускания — запускается на полное время и скрывает уведомление.
    func test_show_sameContentWhilePaused_doesNotStartTimer() async {
        let notification = error("Ошибка")
        sut.show(notification)
        await waitForTimer(count: 1)
        sut.pauseTimer(id: notification.id)

        sut.show(error("Ошибка"))
        await yieldTimes()
        XCTAssertEqual(sleeper.requested.count, 1)
        XCTAssertEqual(sut.current?.id, notification.id)
        sleeper.allow(duration)
        sut.resumeTimer(id: notification.id)

        await yieldUntil { self.sut.current == nil }
    }

    /// Кейс: таймер на паузе, пришло уведомление с другим содержимым.
    /// Ожидание: новое заменяет показанное и скрывается по своему таймеру.
    func test_show_differentContentWhilePaused_replacesWithOwnTimer() async {
        let first = error("Первая")
        sut.show(first)
        await waitForTimer(count: 1)
        sut.pauseTimer(id: first.id)
        sleeper.allow(duration)
        let second = error("Вторая")

        sut.show(second)

        XCTAssertEqual(sut.current?.id, second.id)
        await yieldUntil { self.sut.current == nil }
    }

    /// Кейс: уведомление заменено; жест прежней карточки вызывает `dismiss`, `pauseTimer`, `resumeTimer` с её `id`.
    /// Ожидание: новое уведомление не тронуто, его таймер не перезапущен.
    func test_actionsWithReplacedId_doNothing() async {
        let first = error("Первая")
        sut.show(first)
        let second = error("Вторая")
        sut.show(second)
        await waitForTimer(count: 2)

        sut.pauseTimer(id: first.id)
        sut.resumeTimer(id: first.id)
        sut.dismiss(id: first.id)
        await yieldTimes()

        XCTAssertEqual(sut.current?.id, second.id)
        XCTAssertEqual(sleeper.requested.count, 2)
    }

    /// Кейс: уведомление скрыли свайпом.
    /// Ожидание: уведомление скрыто.
    func test_dismiss_hidesNotification() {
        let notification = error("Ошибка")
        sut.show(notification)

        sut.dismiss(id: notification.id)

        XCTAssertNil(sut.current)
    }

    // MARK: - Активность и выход

    /// Кейс: уведомление показано, единственная сцена ушла из `.active`; затем пришло новое и сцена вернулась.
    /// Ожидание: показанное убрано, новое отброшено, после возврата ничего не показано.
    func test_setActive_false_hidesAndDropsNotifications() {
        sut.show(error("Первая"))

        sut.setActive(false, sceneId: sceneA)
        let isShown = sut.show(error("Вторая"))
        sut.setActive(true, sceneId: sceneA)

        XCTAssertFalse(isShown)
        XCTAssertNil(sut.current)
        XCTAssertTrue(sut.isActive)
        XCTAssertEqual(sut.presentingSceneId, sceneA)
    }

    /// Кейс: активны две сцены, уведомление показано в последней активированной (B); B ушла из `.active`.
    /// Ожидание: показанное убрано, сервис активен, сцена показа — A, новые уведомления показываются.
    func test_setActive_false_presentingScene_movesToOtherActiveScene() {
        sut.setActive(true, sceneId: sceneB)
        sut.show(error("Первая"))

        sut.setActive(false, sceneId: sceneB)
        let isShown = sut.show(error("Вторая"))

        XCTAssertTrue(isShown)
        XCTAssertTrue(sut.isActive)
        XCTAssertEqual(sut.presentingSceneId, sceneA)
    }

    /// Кейс: активны две сцены, уведомление показано в B; из `.active` ушла A, затем A ушла ещё раз.
    /// Ожидание: уведомление остаётся на месте, сцена показа — B.
    func test_setActive_false_otherScene_keepsNotification() {
        sut.setActive(true, sceneId: sceneB)
        let notification = error("Ошибка")
        sut.show(notification)

        sut.setActive(false, sceneId: sceneA)
        sut.setActive(false, sceneId: sceneA)

        XCTAssertEqual(sut.current?.id, notification.id)
        XCTAssertEqual(sut.presentingSceneId, sceneB)
    }

    /// Кейс: уведомление показано в A, стала активной вторая сцена B.
    /// Ожидание: показанное убрано — оно относилось к A; сцена показа — B.
    func test_setActive_true_otherScene_hidesNotification() {
        sut.show(error("Ошибка"))

        sut.setActive(true, sceneId: sceneB)

        XCTAssertNil(sut.current)
        XCTAssertEqual(sut.presentingSceneId, sceneB)
    }

    /// Кейс: уведомление показано в A, A повторно сообщила об активности.
    /// Ожидание: уведомление остаётся.
    func test_setActive_true_samePresentingScene_keepsNotification() {
        let notification = error("Ошибка")
        sut.show(notification)

        sut.setActive(true, sceneId: sceneA)

        XCTAssertEqual(sut.current?.id, notification.id)
    }

    /// Кейс: активны две сцены, обе ушли из `.active`.
    /// Ожидание: сервис неактивен, сцены показа нет, новые уведомления отбрасываются.
    func test_setActive_false_allScenes_deactivates() {
        sut.setActive(true, sceneId: sceneB)

        sut.setActive(false, sceneId: sceneA)
        sut.setActive(false, sceneId: sceneB)
        let isShown = sut.show(error("Ошибка"))

        XCTAssertFalse(isShown)
        XCTAssertFalse(sut.isActive)
        XCTAssertNil(sut.presentingSceneId)
    }

    /// Кейс: уведомление показано, начался выход из аккаунта.
    /// Ожидание: уведомление прошлой сессии убрано.
    func test_authServiceWillLogout_hidesNotification() async {
        sut.show(error("Ошибка"))

        await sut.authServiceWillLogout()

        XCTAssertNil(sut.current)
    }

    // MARK: - Уведомление

    /// Кейс: уведомление-ошибка создано без параметров и с явным отказом от отклика.
    /// Ожидание: без параметров — время от `InAppNotificationTiming` и отклик `.error`; `.some(nil)` — без отклика.
    func test_notification_defaults() {
        let content = InAppNotification.Content.error(message: "Ошибка")

        let byDefault = InAppNotification(content: content)
        let silent = InAppNotification(content: content, feedback: .some(nil))

        XCTAssertEqual(byDefault.duration, InAppNotificationTiming.duration(for: content))
        XCTAssertEqual(byDefault.feedback, .error)
        XCTAssertNil(silent.feedback)
    }
}
