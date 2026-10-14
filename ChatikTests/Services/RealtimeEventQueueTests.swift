//
//  RealtimeEventQueueTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class RealtimeEventQueueTests: XCTestCase {
    private var sleeper: SleepController!
    private var timedOutReasons: [String] = []
    private var sut: RealtimeEventQueue!
    /// События, полученные подписчиком, по порядку.
    private var received: [RealtimeEvent] = []
    private var subscription: RealtimeSubscription?

    override func setUp() async throws {
        try await super.setUp()
        sleeper = SleepController()
        let sleeper = sleeper!
        timedOutReasons = []
        received = []
        sut = RealtimeEventQueue(
            sleep: { try await sleeper.sleep($0) },
            onLeaseTimeout: { [unowned self] reason in timedOutReasons.append(String(describing: reason)) }
        )
    }

    override func tearDown() async throws {
        subscription = nil
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Доставка

    /// Кейс: в очередь положены три события.
    /// Ожидание: подписчик получил их в порядке прихода.
    func test_enqueue_deliversInOrder() async {
        subscribeRecorder()

        sut.enqueue(.connected)
        sut.enqueue(.received(.make(id: 1)))
        sut.enqueue(.received(.make(id: 2)))

        await yieldUntil { [unowned self] in received.count == 3 }
        XCTAssertEqual(received, [.connected, .received(.make(id: 1)), .received(.make(id: 2))])
    }

    /// Кейс: два подписчика; первый обрабатывает событие асинхронно и долго.
    /// Ожидание: второй получает событие только после первого, следующее событие — только после обоих.
    func test_delivery_waitsForEachHandler() async {
        let gate = Gate()
        var log: [String] = []
        let first = sut.subscribe { event in
            log.append("first \(event == .connected ? "connected" : "message")")
            if event == .connected { await gate.wait() }
        }
        let second = sut.subscribe { event in
            log.append("second \(event == .connected ? "connected" : "message")")
        }

        sut.enqueue(.connected)
        sut.enqueue(.received(.make(id: 1)))
        await yieldUntil { gate.isWaiting }
        XCTAssertEqual(log, ["first connected"])
        gate.open()

        await yieldUntil { log.count == 4 }
        XCTAssertEqual(log, ["first connected", "second connected", "first message", "second message"])
        _ = (first, second)
    }

    /// Кейс: событие положено в очередь до подписки, следующее — после.
    /// Ожидание: подписчик получил только второе — очередь не хранит события для будущих подписчиков.
    func test_eventBeforeSubscription_isNotDelivered() async {
        sut.enqueue(.received(.make(id: 1)))
        await yieldTimes()

        subscribeRecorder()
        sut.enqueue(.received(.make(id: 2)))

        await yieldUntil { [unowned self] in !received.isEmpty }
        XCTAssertEqual(received, [.received(.make(id: 2))])
    }

    /// Кейс: подписка отменена через `cancel()`, затем пришло событие.
    /// Ожидание: обработчик его не получил.
    func test_cancelledSubscription_receivesNothing() async {
        subscribeRecorder()
        subscription?.cancel()
        var other: [RealtimeEvent] = []
        let otherSubscription = sut.subscribe { other.append($0) }

        sut.enqueue(.connected)

        await yieldUntil { other.count == 1 }
        XCTAssertTrue(received.isEmpty)
        _ = otherSubscription
    }

    /// Кейс: токен подписки уничтожен без `cancel()`.
    /// Ожидание: подписка снята — событие обработчик не получил.
    func test_releasedSubscriptionToken_unsubscribes() async {
        subscribeRecorder()
        subscription = nil
        await yieldTimes()
        var other: [RealtimeEvent] = []
        let otherSubscription = sut.subscribe { other.append($0) }

        sut.enqueue(.connected)

        await yieldUntil { other.count == 1 }
        XCTAssertTrue(received.isEmpty)
        _ = otherSubscription
    }

    // MARK: - Аренды

    /// Кейс: взята аренда, пришли события; затем аренда снята.
    /// Ожидание: пока аренда активна, события копятся; после снятия доставлены по порядку.
    func test_lease_accumulatesUntilReleased() async {
        subscribeRecorder()
        let lease = sut.suspendProcessing(reason: "test")

        sut.enqueue(.received(.make(id: 1)))
        sut.enqueue(.received(.make(id: 2)))
        await yieldTimes()
        XCTAssertTrue(received.isEmpty)
        lease.release()

        await yieldUntil { [unowned self] in received.count == 2 }
        XCTAssertEqual(received, [.received(.make(id: 1)), .received(.make(id: 2))])
    }

    /// Кейс: две аренды; первую сняли, затем вторую.
    /// Ожидание: события доставлены только после снятия второй — семафор считает аренды.
    func test_twoLeases_deliverAfterLastRelease() async {
        subscribeRecorder()
        let first = sut.suspendProcessing(reason: "first")
        let second = sut.suspendProcessing(reason: "second")
        sut.enqueue(.connected)

        first.release()
        await yieldTimes()
        XCTAssertTrue(received.isEmpty)
        second.release()

        await yieldUntil { [unowned self] in received == [.connected] }
    }

    /// Кейс: обработчик `connected` синхронно берёт аренду; следом в очереди ещё событие.
    /// Ожидание: следующее событие не доставляется, пока аренда активна, — аренда проверяется перед каждым событием.
    func test_leaseTakenByHandler_stopsNextEvent() async {
        var lease: RealtimeQueueLease?
        subscription = sut.subscribe { [unowned self] event in
            received.append(event)
            if event == .connected { lease = sut.suspendProcessing(reason: "handler") }
        }

        sut.enqueue(.connected)
        sut.enqueue(.received(.make(id: 1)))
        await yieldUntil { lease != nil }
        await yieldTimes()
        XCTAssertEqual(received, [.connected])
        lease?.release()

        await yieldUntil { [unowned self] in received.count == 2 }
    }

    /// Кейс: `withProcessingSuspended` — операция завершилась успешно, бросила ошибку, её задачу отменили.
    /// Ожидание: во всех случаях аренда снята.
    func test_withProcessingSuspended_releasesOnReturnThrowAndCancel() async {
        await sut.withProcessingSuspended(reason: "return") { _ in }
        XCTAssertEqual(sut.activeLeaseCount, 0)

        _ = try? await sut.withProcessingSuspended(reason: "throw") { _ in throw NetworkError.missingResponse }
        XCTAssertEqual(sut.activeLeaseCount, 0)

        let task = Task { [sut] in
            try await sut!.withProcessingSuspended(reason: "cancel") { _ in try await Task.sleep(for: .seconds(3600)) }
        }
        await yieldUntil { [unowned self] in sut.activeLeaseCount == 1 }
        task.cancel()
        _ = await task.result
        XCTAssertEqual(sut.activeLeaseCount, 0)
    }

    /// Кейс: аренду взяли и потеряли без `release()`.
    /// Ожидание: `deinit` аренды снимает её, накопленное событие доставлено.
    func test_lostLease_isReleasedOnDeinit() async {
        subscribeRecorder()
        _ = sut.suspendProcessing(reason: "lost")
        sut.enqueue(.connected)

        await yieldUntil { [unowned self] in received == [.connected] }
        XCTAssertEqual(sut.activeLeaseCount, 0)
    }

    /// Кейс: аренда снята дважды, рядом активна другая аренда.
    /// Ожидание: повторный `release()` ничего не делает — другая аренда по-прежнему держит очередь.
    func test_release_twice_isIdempotent() async {
        let lease = sut.suspendProcessing(reason: "lease")
        let other = sut.suspendProcessing(reason: "other")

        lease.release()
        lease.release()

        XCTAssertEqual(sut.activeLeaseCount, 1)
        other.release()
        XCTAssertEqual(sut.activeLeaseCount, 0)
    }

    /// Кейс: аренду не сняли за время сторожевого таймаута.
    /// Ожидание: аренда снята принудительно и помечена `isExpired`, причина передана в обработчик таймаута,
    /// накопленные события доставлены; поздний `release()` ничего не ломает.
    func test_watchdog_expiresLease() async {
        subscribeRecorder()
        sleeper.allow(RealtimeEventQueue.defaultLeaseTimeout)
        let lease = sut.suspendProcessing(reason: "stuck")
        sut.enqueue(.connected)

        await yieldUntil { [unowned self] in received == [.connected] }

        XCTAssertTrue(lease.isExpired)
        XCTAssertEqual(timedOutReasons, ["stuck"])
        XCTAssertEqual(sut.activeLeaseCount, 0)
        lease.release()
        XCTAssertEqual(sut.activeLeaseCount, 0)
    }

    /// Кейс: аренду сняли вовремя.
    /// Ожидание: сторожевой таймаут не срабатывает, аренда не помечена истёкшей.
    func test_watchdog_releasedLease_isNotExpired() async {
        let lease = sut.suspendProcessing(reason: "ok")
        await yieldUntil { [unowned self] in sleeper.requested == [RealtimeEventQueue.defaultLeaseTimeout] }

        lease.release()
        sleeper.allow(RealtimeEventQueue.defaultLeaseTimeout)
        await yieldTimes()

        XCTAssertFalse(lease.isExpired)
        XCTAssertTrue(timedOutReasons.isEmpty)
    }

    // MARK: - Выход из аккаунта

    /// Кейс: выход, пока обработчик висит на долгой работе, есть аренда и накопленные события.
    /// Ожидание: доставка отменена и дождалась обработчика, аренда снята принудительно, накопленное отброшено;
    /// после выхода очередь снова доставляет события.
    func test_willLogout_cancelsDrainExpiresLeasesAndDropsPending() async {
        var handled: [RealtimeEvent] = []
        var isHanging = false
        subscription = sut.subscribe { event in
            handled.append(event)
            guard event == .connected else { return }
            isHanging = true
            try? await Task.sleep(for: .seconds(3600))
            isHanging = false
        }
        sut.enqueue(.connected)
        await yieldUntil { isHanging }
        let lease = sut.suspendProcessing(reason: "sync")
        sut.enqueue(.received(.make(id: 1)))

        await sut.authServiceWillLogout()

        XCTAssertFalse(isHanging)
        XCTAssertTrue(lease.isExpired)
        XCTAssertEqual(sut.activeLeaseCount, 0)
        sut.enqueue(.received(.make(id: 2)))
        await yieldUntil { handled.count == 2 }
        XCTAssertEqual(handled, [.connected, .received(.make(id: 2))])
    }

    // MARK: - Helpers

    /// Подписывает обработчик, записывающий события в `received`.
    private func subscribeRecorder() {
        subscription = sut.subscribe { [unowned self] event in
            received.append(event)
        }
    }
}
