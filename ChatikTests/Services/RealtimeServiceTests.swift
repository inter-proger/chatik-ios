//
//  RealtimeServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class RealtimeServiceTests: XCTestCase {
    private let pingInterval: Duration = .seconds(25)
    private let pongTimeout: Duration = .seconds(10)
    private var globalService: GlobalServiceMock!
    private var factory: WebSocketConnectionFactoryMock!
    private var sessionService: SessionService!
    private var authService: AuthService!
    private var eventQueue: RealtimeEventQueueMock!
    private var connectionMonitor: RealtimeConnectionMonitor!
    private var userCache: UserCacheServiceMock!
    private var sleeper: SleepController!
    private var sut: RealtimeService!

    override func setUp() async throws {
        try await super.setUp()
        globalService = GlobalServiceMock()
        factory = WebSocketConnectionFactoryMock()
        let userDefaultsService = UserDefaultsServiceMock(currentUser: User(userId: 1, login: "ivan", name: "Ivan", avatar: nil))
        sessionService = SessionService(userDefaultsService: userDefaultsService, localStorageCleaner: LocalStorageCleanerMock())
        await sessionService.restore()
        authService = AuthService(networkService: NetworkServiceMock())
        eventQueue = RealtimeEventQueueMock()
        connectionMonitor = RealtimeConnectionMonitor()
        userCache = UserCacheServiceMock()
        sleeper = SleepController()
        let sleeper = sleeper!
        sut = RealtimeService(
            globalService: globalService,
            connectionFactory: factory,
            sessionService: sessionService,
            authService: authService,
            eventQueue: eventQueue,
            connectionMonitor: connectionMonitor,
            userCache: userCache,
            backoff: ReconnectBackoff(randomFactor: { 1 }),
            pingInterval: pingInterval,
            pongTimeout: pongTimeout,
            sleep: { try await sleeper.sleep($0) }
        )
        authService.addObserver(sut)
        authService.addObserver(sessionService)
    }

    override func tearDown() async throws {
        await sut.stop()
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Подключение

    /// Кейс: `start()` при открытой сессии, `/global/start` выдал данные подключения.
    /// Ожидание: соединение открыто по `url` из ответа, первым сообщением ушёл `auth` / `connect` с id пользователя
    /// и токеном.
    func test_start_connectsAndAuthorizes() async throws {
        globalService.startResults = [.success(.stub(token: "t1"))]

        sut.start()
        await waitUntil { [unowned self] in factory.made.first?.sent.isEmpty == false }

        XCTAssertEqual(globalService.startCallCount, 1)
        XCTAssertEqual(factory.urls, [WebsocketConnectInfo.stub().url])
        XCTAssertEqual(factory.made.first?.sent, [.authConnect(userId: 1, token: "t1")])
    }

    /// Кейс: сервер ответил `auth` / `connected`.
    /// Ожидание: в очередь событий положен `.connected` — сигнал синхронизироваться через REST.
    func test_connected_enqueuesConnected() async throws {
        _ = try await startAndConnect()

        await waitUntil { [unowned self] in eventQueue.enqueued == [.connected] }
    }

    /// Кейс: `/global/start` вернул `null`, а локально сессия открыта (сессию завершили на сервере).
    /// Ожидание: соединение не открывается, сессия завершена с пометкой «истекла».
    func test_start_nullConnectInfo_loggedIn_expiresSession() async {
        globalService.startResults = [.success(nil)]

        sut.start()
        await waitUntil { [unowned self] in !sessionService.isLoggedIn }

        XCTAssertTrue(sessionService.isExpired)
        XCTAssertTrue(factory.made.isEmpty)
    }

    /// Кейс: `/global/start` вернул `null` после выхода из аккаунта — локальной сессии нет.
    /// Ожидание: соединение не открывается, переподключений нет, признак истечения не поднят.
    func test_start_nullConnectInfo_loggedOut_staysDisconnected() async {
        await sessionService.end()
        globalService.startResults = [.success(nil)]

        sut.start()
        await sut.stopWhenIdle(globalService: globalService)

        XCTAssertEqual(globalService.startCallCount, 1)
        XCTAssertEqual(globalService.tokenCallCount, 0)
        XCTAssertTrue(factory.made.isEmpty)
        XCTAssertFalse(sessionService.isExpired)
    }

    // MARK: - События

    /// Кейс: после `connected` пришло `messages` / `received` с `userIds`.
    /// Ожидание: событие с превью положено в очередь, отправитель запрошен в кэше пользователей, серверу ушло
    /// подтверждение с `uid` события. В БД сообщение пишет `MessageCacheService` при обработке очереди.
    func test_messageReceived_enqueuesLoadsUsersAndAcknowledges() async throws {
        let connection = try await startAndConnect()

        connection.deliver(WebSocketServerMessage(uid: "e1", group: "messages", event: .messageReceived(.stub, .make(id: 15)), userIds: [1]))

        await waitUntil { connection.sent.count == 2 }
        await waitUntil { [unowned self] in !userCache.loadRequests.isEmpty }
        XCTAssertEqual(eventQueue.enqueued, [.connected, .messageReceived(.stub, .make(id: 15))])
        XCTAssertEqual(userCache.loadRequests, [[1]])
        XCTAssertEqual(connection.sent.last, .acknowledge(receivedUid: "e1"))
    }

    /// Кейс: после `connected` пришли `messages` / `edited` и `conversations` / `singleCreated`.
    /// Ожидание: оба события положены в очередь по порядку.
    func test_editedAndConversationCreated_areEnqueuedInOrder() async throws {
        let connection = try await startAndConnect()

        connection.deliver(WebSocketServerMessage(uid: "e1", group: "messages", event: .messageEdited(.editedStub, nil), userIds: []))
        connection.deliver(WebSocketServerMessage(uid: "e2", group: "conversations", event: .conversationCreated(.singleStub), userIds: []))

        await waitUntil { connection.sent.count == 3 }
        XCTAssertEqual(eventQueue.enqueued, [.connected, .messageEdited(.editedStub, nil), .conversationCreated(.singleStub)])
    }

    /// Кейс: после `connected` пришло событие неизвестной группы.
    /// Ожидание: оно подтверждено сразу, в очередь ничего не положено.
    func test_unknownEvent_isAcknowledgedOnly() async throws {
        let connection = try await startAndConnect()

        connection.deliver(WebSocketServerMessage(uid: "e1", group: "typing", event: .unknown, userIds: []))

        await waitUntil { connection.sent.count == 2 }
        XCTAssertEqual(connection.sent.last, .acknowledge(receivedUid: "e1"))
        XCTAssertEqual(eventQueue.enqueued, [.connected])
    }

    /// Кейс: событие пришло до `auth` / `connected`.
    /// Ожидание: оно не применяется и не подтверждается — подтверждение до `connected` было бы ошибкой протокола.
    func test_eventBeforeConnected_isIgnored() async throws {
        globalService.startResults = [.success(.stub())]
        sut.start()
        await waitUntil { [unowned self] in factory.made.first?.sent.count == 1 }
        let connection = factory.made[0]

        connection.deliver(WebSocketServerMessage(uid: "e1", group: "messages", event: .messageReceived(.stub, .make(id: 15)), userIds: [1]))
        connection.deliverConnected()
        connection.deliver(WebSocketServerMessage(uid: "e2", group: "typing", event: .unknown, userIds: []))
        await waitUntil { connection.sent.count == 2 }

        XCTAssertEqual(connection.sent.last, .acknowledge(receivedUid: "e2"))
        XCTAssertEqual(eventQueue.enqueued, [.connected])
    }

    /// Кейс: пока соединение открыто, локальная сессия завершилась, и пришло событие.
    /// Ожидание: событие чужой (уже закрытой) сессии не применяется, соединение закрыто клиентом, переподключений нет.
    func test_event_afterSessionEnded_isDroppedAndConnectionClosed() async throws {
        let connection = try await startAndConnect()
        await sessionService.end()

        connection.deliver(WebSocketServerMessage(uid: "e1", group: "messages", event: .messageReceived(.stub, .make(id: 15)), userIds: [1]))

        await waitUntil { connection.closeCodes == [WebSocketCloseCode.normal] }
        XCTAssertEqual(eventQueue.enqueued, [.connected])
        XCTAssertEqual(globalService.tokenCallCount, 0)
    }

    // MARK: - Монитор соединения

    /// Кейс: соединение дошло до `auth` / `connected`.
    /// Ожидание: в мониторе появилось текущее соединение — до того, как `connected` положен в очередь.
    func test_connected_setsCurrentConnection() async throws {
        globalService.startResults = [.success(.stub())]
        sut.start()
        await waitUntil { [unowned self] in factory.made.first?.sent.count == 1 }
        XCTAssertNil(connectionMonitor.current)

        factory.made[0].deliverConnected()

        await waitUntil { [unowned self] in eventQueue.enqueued == [.connected] }
        XCTAssertNotNil(connectionMonitor.current)
    }

    /// Кейс: сервер закрыл соединение, затем клиент переподключился.
    /// Ожидание: после закрытия текущего соединения нет, у нового соединения — новый id.
    func test_reconnect_clearsAndReplacesCurrentConnection() async throws {
        let connection = try await startAndConnect()
        let firstId = try XCTUnwrap(connectionMonitor.current)
        globalService.tokenResults = [.success(.stub(token: "t2"))]
        sleeper.allow(.seconds(1))

        connection.closeByServer(code: WebSocketCloseCode.abnormal)

        await waitUntil { [unowned self] in factory.made.count == 2 && factory.made[1].sent.count == 1 }
        XCTAssertNil(connectionMonitor.current)
        factory.made[1].deliverConnected()
        await waitUntil { [unowned self] in connectionMonitor.current != nil }
        XCTAssertNotEqual(connectionMonitor.current, firstId)
    }

    /// Кейс: сервис остановлен (`stop()`) при открытом соединении.
    /// Ожидание: текущего соединения в мониторе нет.
    func test_stop_clearsCurrentConnection() async throws {
        _ = try await startAndConnect()

        await sut.stop()

        XCTAssertNil(connectionMonitor.current)
    }

    // MARK: - Закрытие и переподключение

    /// Кейс: сервер закрыл соединение с кодом 1000.
    /// Ожидание: переподключения нет — ни токена, ни нового соединения.
    func test_closeNormal_doesNotReconnect() async throws {
        let connection = try await startAndConnect()

        connection.closeByServer(code: WebSocketCloseCode.normal)
        await sut.stopWhenIdle(globalService: globalService)

        XCTAssertEqual(globalService.tokenCallCount, 0)
        XCTAssertEqual(factory.made.count, 1)
        XCTAssertTrue(sleeper.requested.allSatisfy { $0 == pingInterval })
    }

    /// Кейс: соединение обрывается раз за разом (1006), не доходя до `connected`, затем доходит и снова обрывается.
    /// Ожидание: переподключения с задержками 1, 2, 4 с, каждое — с новым токеном из `/global/getWebsocketToken`;
    /// после `connected` задержка снова 1 с.
    func test_abnormalClose_reconnectsWithBackoffAndResetsAfterConnected() async throws {
        let first = try await startAndConnect()
        globalService.tokenResults = (1...4).map { .success(.stub(token: "r\($0)")) }
        sleeper.allow(.seconds(1), times: 2)
        sleeper.allow(.seconds(2))

        first.closeByServer(code: WebSocketCloseCode.abnormal)
        await waitUntil { [unowned self] in factory.made.count == 2 }
        factory.made[1].closeByServer(code: WebSocketCloseCode.abnormal)
        await waitUntil { [unowned self] in factory.made.count == 3 }
        factory.made[2].deliverConnected()
        await waitUntil { [unowned self] in factory.made[2].sent.count == 1 }
        factory.made[2].closeByServer(code: 1011)
        await waitUntil { [unowned self] in factory.made.count == 4 }

        XCTAssertEqual(reconnectDelays, [.seconds(1), .seconds(2), .seconds(1)])
        XCTAssertEqual(factory.made[1].sent.first, .authConnect(userId: 1, token: "r1"))
        XCTAssertEqual(globalService.startCallCount, 1)
        XCTAssertEqual(globalService.tokenCallCount, 3)
    }

    /// Кейс: авторизация соединения не удалась с кодом 2004 (токен истёк), затем ещё раз с 2004.
    /// Ожидание: первый раз новый токен берётся сразу, без задержки; при повторе — с задержкой.
    func test_tokenRejected_reconnectsImmediatelyThenWithDelay() async throws {
        globalService.startResults = [.success(.stub())]
        globalService.tokenResults = [.success(.stub(token: "r1")), .success(.stub(token: "r2"))]
        sleeper.allow(.seconds(1))
        sut.start()
        await waitUntil { [unowned self] in factory.made.first?.sent.count == 1 }

        rejectToken(on: factory.made[0])
        await waitUntil { [unowned self] in factory.made.count == 2 }
        XCTAssertTrue(reconnectDelays.isEmpty)
        rejectToken(on: factory.made[1])
        await waitUntil { [unowned self] in factory.made.count == 3 }

        XCTAssertEqual(reconnectDelays, [.seconds(1)])
        XCTAssertEqual(factory.made[2].sent.first, .authConnect(userId: 1, token: "r2"))
    }

    /// Кейс: `/global/getWebsocketToken` ответил 2003 при переподключении.
    /// Ожидание: переподключения прекращаются — новое соединение не открывается.
    func test_tokenRequestUnauthorized_stopsReconnecting() async throws {
        let connection = try await startAndConnect()
        globalService.tokenResults = [.failure(NetworkError.api(code: NetworkError.Code.unauthorized))]
        sleeper.allow(.seconds(1))

        connection.closeByServer(code: WebSocketCloseCode.abnormal)
        await waitUntil { [unowned self] in globalService.tokenCallCount == 1 }
        await sut.stopWhenIdle(globalService: globalService)

        XCTAssertEqual(factory.made.count, 1)
        XCTAssertEqual(globalService.tokenCallCount, 1)
    }

    /// Кейс: сервер закрыл соединение с кодом 4003 (сессия завершена), `/global/start` вернул `null`.
    /// Ожидание: без задержки вызван `/global/start`, сессия завершена как истёкшая, нового соединения нет.
    func test_sessionEnded_callsGlobalStartAndExpiresOnNull() async throws {
        let connection = try await startAndConnect()
        globalService.startResults = [.success(nil)]

        connection.closeByServer(code: WebSocketCloseCode.sessionEnded)
        await waitUntil { [unowned self] in !sessionService.isLoggedIn }

        XCTAssertEqual(globalService.startCallCount, 2)
        XCTAssertEqual(globalService.tokenCallCount, 0)
        XCTAssertTrue(sessionService.isExpired)
        XCTAssertEqual(factory.made.count, 1)
    }

    /// Кейс: во время задержки перед переподключением появилась сеть.
    /// Ожидание: переподключение — сразу, не дожидаясь конца задержки.
    func test_networkAvailable_skipsReconnectDelay() async throws {
        let connection = try await startAndConnect()
        globalService.tokenResults = [.success(.stub(token: "r1"))]

        connection.closeByServer(code: WebSocketCloseCode.abnormal)
        await waitUntil { [unowned self] in reconnectDelays == [.seconds(1)] }
        sut.networkDidBecomeAvailable()

        await waitUntil { [unowned self] in factory.made.count == 2 }
        XCTAssertEqual(globalService.tokenCallCount, 1)
    }

    /// Кейс: ping ушёл, pong за `pongTimeout` не пришёл.
    /// Ожидание: клиент закрыл соединение и переподключился с задержкой, как при обрыве.
    func test_pongTimeout_closesAndReconnects() async throws {
        let connection = WebSocketConnectionMock(answersPing: false)
        factory = WebSocketConnectionFactoryMock(connections: [connection])
        rebuildSUT()
        globalService.startResults = [.success(.stub())]
        globalService.tokenResults = [.success(.stub(token: "r1"))]
        sleeper.allow(pingInterval)
        sleeper.allow(pongTimeout)
        sleeper.allow(.seconds(1))

        sut.start()
        await waitUntil { [unowned self] in factory.made.count == 2 }

        XCTAssertEqual(connection.pingCount, 1)
        XCTAssertEqual(connection.closeCodes, [WebSocketCloseCode.normal])
        XCTAssertEqual(reconnectDelays, [.seconds(1)])
    }

    /// Кейс: соединение отвечает на ping.
    /// Ожидание: следующий ping ждёт остаток интервала (`pingInterval - pongTimeout`), соединение не закрывается.
    func test_pongReceived_keepsConnection() async throws {
        sleeper.allow(pingInterval)
        sleeper.allow(pongTimeout)
        let connection = try await startAndConnect()

        await waitUntil { [unowned self] in sleeper.requested.contains(pingInterval - pongTimeout) }

        XCTAssertEqual(connection.pingCount, 1)
        XCTAssertTrue(connection.closeCodes.isEmpty)
    }

    // MARK: - Управление

    /// Кейс: `stop()` при открытом соединении (уход в фон, выход из аккаунта).
    /// Ожидание: соединение закрыто клиентом с кодом 1000, переподключения нет.
    func test_stop_closesConnectionWithoutReconnect() async throws {
        let connection = try await startAndConnect()

        await sut.stop()

        XCTAssertEqual(connection.closeCodes, [WebSocketCloseCode.normal])
        XCTAssertEqual(globalService.tokenCallCount, 0)
        XCTAssertEqual(factory.made.count, 1)
    }

    /// Кейс: `AuthService` сообщил о начале выхода при открытом соединении.
    /// Ожидание: соединение закрыто клиентом с кодом 1000 до запроса выхода, переподключения нет.
    func test_authServiceWillLogout_closesConnection() async throws {
        let connection = try await startAndConnect()

        await sut.authServiceWillLogout()

        XCTAssertEqual(connection.closeCodes, [WebSocketCloseCode.normal])
        XCTAssertEqual(factory.made.count, 1)
    }

    /// Кейс: `start()` между `authServiceWillLogout` и `authServiceDidLogout` (возврат из фона во время выхода).
    /// Ожидание: `/global/start` не вызывается, соединение не открывается.
    func test_start_whileLoggingOut_doesNothing() async {
        await sut.authServiceWillLogout()

        sut.start()
        await sut.stop()

        XCTAssertEqual(globalService.startCallCount, 0)
        XCTAssertTrue(factory.made.isEmpty)
    }

    /// Кейс: `start()` после завершения выхода (новый вход).
    /// Ожидание: работа с сервером начинается заново с `/global/start`.
    func test_start_afterLogoutFinished_connects() async {
        globalService.startResults = [.success(.stub(token: "t1"))]
        await sut.authServiceWillLogout()
        await sut.authServiceDidLogout(reason: .userInitiated)

        sut.start()
        await waitUntil { [unowned self] in factory.made.first?.sent.isEmpty == false }

        XCTAssertEqual(globalService.startCallCount, 1)
    }

    /// Кейс: повторный `start()` (вход под другим пользователем, возврат из фона) при открытом соединении.
    /// Ожидание: старое соединение закрыто клиентом, новое открыто по данным нового `/global/start`;
    /// закрытие старого не вызывает переподключения.
    func test_restart_replacesCurrentConnection() async throws {
        let old = try await startAndConnect()
        globalService.startResults = [.success(.stub(token: "t2"))]

        sut.start()
        await waitUntil { [unowned self] in factory.made.count == 2 && factory.made[1].sent.count == 1 }

        XCTAssertEqual(old.closeCodes, [WebSocketCloseCode.normal])
        XCTAssertEqual(factory.made[1].sent, [.authConnect(userId: 1, token: "t2")])
        XCTAssertEqual(globalService.tokenCallCount, 0)
    }

    // MARK: - Helpers

    /// Паузы перед переподключением — все запрошенные, кроме интервалов heartbeat.
    private var reconnectDelays: [Duration] {
        sleeper.requested.filter { $0 != pingInterval && $0 != pongTimeout && $0 != pingInterval - pongTimeout }
    }

    /// Запускает сервис, дожидается `auth` / `connect` и отвечает `connected`.
    /// - Returns: открытое соединение.
    private func startAndConnect() async throws -> WebSocketConnectionMock {
        globalService.startResults.append(.success(.stub()))
        let index = factory.made.count
        sut.start()
        await waitUntil { [unowned self] in factory.made.count > index && factory.made[index].sent.count == 1 }
        let connection = try XCTUnwrap(factory.made.last)
        connection.deliverConnected()
        await Task.yield()
        return connection
    }

    /// Отвечает `auth` / `connectionError` с 2004 и закрывает соединение с 4001 — как сервер при негодном токене.
    private func rejectToken(on connection: WebSocketConnectionMock) {
        connection.deliver(WebSocketServerMessage(
            uid: UUID().uuidString,
            group: "auth",
            event: .connectionError(errorCode: NetworkError.Code.websocketTokenInvalid),
            userIds: []
        ))
        connection.closeByServer(code: WebSocketCloseCode.authorizationFailed)
    }

    /// Пересобирает сервис над текущими моками — после замены фабрики.
    private func rebuildSUT() {
        let sleeper = sleeper!
        sut = RealtimeService(
            globalService: globalService,
            connectionFactory: factory,
            sessionService: sessionService,
            authService: authService,
            eventQueue: eventQueue,
            connectionMonitor: connectionMonitor,
            userCache: userCache,
            backoff: ReconnectBackoff(randomFactor: { 1 }),
            pingInterval: pingInterval,
            pongTimeout: pongTimeout,
            sleep: { try await sleeper.sleep($0) }
        )
        authService.addObserver(sut)
        authService.addObserver(sessionService)
    }
}

private extension RealtimeService {
    /// Даёт циклу соединения закончить работу после исхода «не переподключаться»: уступает main actor, затем
    /// останавливает сервис. Если цикл ошибочно продолжил переподключаться, это видно по вызовам `globalService`.
    func stopWhenIdle(globalService: GlobalServiceMock) async {
        for _ in 0..<50 {
            await Task.yield()
        }
        await stop()
    }
}
