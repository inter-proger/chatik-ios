//
//  RealtimeService.swift
//  Chatik
//

import Foundation
import os

/// Событие реального времени для экранов. Локальная БД к моменту доставки уже обновлена.
enum RealtimeEvent: Equatable, Sendable {
    /// Соединение (пере)установлено. WebSocket не гарантирует доставку: пока соединения не было, события
    /// могли потеряться, поэтому открытые экраны синхронизируются через REST.
    case connected
    /// Создана личная переписка.
    case conversationCreated(Conversation)
    /// Новое сообщение.
    case messageReceived(Message)
    /// Сообщение отредактировано.
    case messageEdited(Message)
}

@MainActor
protocol RealtimeServiceProtocol: AuthServiceObserver {
    /// Начинает работу с `/global/start`: подключается к WebSocket или, если пользователь не авторизован,
    /// закрывает соединение. Прежнее соединение закрывается. Во время выхода из аккаунта ничего не делает.
    func start()
    /// Закрывает соединение и прекращает переподключения; возвращается, когда начатая обработка событий
    /// (запись в БД) закончена.
    func stop() async
    /// Поток событий реального времени; заканчивается, когда отменена читающая его задача.
    func events() -> AsyncStream<RealtimeEvent>
}

/// Соединение с WebSocket-сервером: подключение, переподключение, heartbeat и разбор событий.
///
/// В каждый момент у клиента не больше одного текущего соединения: его ведёт задача `runTask`. Новый `start()`
/// и `stop()` отменяют её — соединение закрывается с кодом 1000, и его дальнейшие события и закрытие уже ни на что
/// не влияют (например, 4003 по старому соединению после входа под другим пользователем).
///
/// Цикл соединения: токен (`/global/start` или `/global/getWebsocketToken`) → handshake → `auth` / `connect` →
/// `auth` / `connected` → события. После `connected` экраны получают `RealtimeEvent.connected` и синхронизируются
/// через REST. Событие сначала применяется к БД (из двух версий объекта побеждает версия с большим `updatedAt`,
/// см. storage-сервисы), затем доставляется экранам и только потом подтверждается серверу.
@MainActor
final class RealtimeService: RealtimeServiceProtocol {
    /// Откуда брать токен для следующего подключения.
    private enum TokenSource {
        /// `/global/start` — при старте, входе, выходе, возврате из фона и после закрытия 4003.
        case globalStart
        /// `/global/getWebsocketToken` — при переподключении.
        case websocketToken
    }

    /// Чем закончилась попытка соединения — от этого зависит, переподключаться ли и как.
    private enum ConnectionOutcome: Equatable {
        /// Пользователь не авторизован (или сменился): не подключаться.
        case notAuthorized
        /// Соединение закрыто нормально (1000) или клиентом: не переподключаться.
        case closedNormally
        /// Сессия завершена (4003): начать заново с `/global/start`.
        case sessionEnded
        /// Токен не подошёл (2004): сразу взять новый.
        case tokenRejected
        /// Прочие сбои (сеть, ошибки сервера и протокола): переподключиться с задержкой.
        case failed
    }

    /// Итог получения данных подключения.
    private enum ConnectInfoResult {
        case info(WebsocketConnectInfo)
        /// Подключаться не с чем — попытка заканчивается этим исходом.
        case finished(ConnectionOutcome)
    }

    /// Состояние текущего соединения, которое меняет задача heartbeat.
    private final class ConnectionState {
        /// `true` — pong не пришёл вовремя, и соединение закрыл клиент: это обрыв, а не нормальное закрытие.
        var isPongTimedOut = false
    }

    /// Ответ на один ping.
    private final class PingState {
        /// `true` — pong пришёл (или ping не ушёл: соединение уже закрыто, это обработает чтение).
        var isAnswered = false
    }

    /// Интервал ping, который шлёт клиент: сервер сам не пингует и разрывает соединение после 60 с тишины.
    private let pingInterval: Duration
    /// Сколько ждать pong, прежде чем считать соединение потерянным.
    private let pongTimeout: Duration

    private let globalService: GlobalServiceProtocol
    private let connectionFactory: WebSocketConnectionFactoryProtocol
    private let sessionService: SessionServiceProtocol
    private let authService: AuthServiceProtocol
    private let conversationStorage: ConversationStorageServiceProtocol
    private let messageStorage: MessageStorageServiceProtocol
    private let userCache: UserCacheServiceProtocol
    private let backoff: ReconnectBackoff
    private let sleep: @Sendable (Duration) async throws -> Void

    /// Задача, ведущая текущее соединение и переподключения; `nil` — соединения нет и не будет.
    private var runTask: Task<Void, Never>?
    /// Идущая задержка перед переподключением; появление сети её прерывает.
    private var reconnectDelayTask: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<RealtimeEvent>.Continuation] = [:]
    /// `true` между `authServiceWillLogout` и `authServiceDidLogout`: `start()` в это время не подключается —
    /// иначе возврат из фона во время выхода открыл бы соединение по ещё живой cookie, и закрытие 4003 после
    /// выхода выглядело бы как истечение сессии.
    private var isLoggingOut = false

    /// - Parameters:
    ///   - globalService: источник данных подключения.
    ///   - connectionFactory: открывает WebSocket-соединения.
    ///   - sessionService: текущий пользователь.
    ///   - authService: при `null` из `/global/start` сессия завершается через него — как истёкшая.
    ///   - conversationStorage: куда пишутся переписки из событий.
    ///   - messageStorage: куда пишутся сообщения из событий.
    ///   - userCache: загружает пользователей из `userIds` событий.
    ///   - backoff: задержки переподключения.
    ///   - pingInterval: интервал ping.
    ///   - pongTimeout: сколько ждать pong.
    ///   - sleep: ожидание; подменяется в тестах.
    init(
        globalService: GlobalServiceProtocol,
        connectionFactory: WebSocketConnectionFactoryProtocol,
        sessionService: SessionServiceProtocol,
        authService: AuthServiceProtocol,
        conversationStorage: ConversationStorageServiceProtocol,
        messageStorage: MessageStorageServiceProtocol,
        userCache: UserCacheServiceProtocol,
        backoff: ReconnectBackoff = ReconnectBackoff(),
        pingInterval: Duration = .seconds(25),
        pongTimeout: Duration = .seconds(10),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.globalService = globalService
        self.connectionFactory = connectionFactory
        self.sessionService = sessionService
        self.authService = authService
        self.conversationStorage = conversationStorage
        self.messageStorage = messageStorage
        self.userCache = userCache
        self.backoff = backoff
        self.pingInterval = pingInterval
        self.pongTimeout = pongTimeout
        self.sleep = sleep
    }

    // MARK: - Управление

    /// Отменяет прежнее соединение и, дождавшись его закрытия, начинает новое с `/global/start`.
    /// Во время выхода из аккаунта ничего не делает: подключаться после него не с чем.
    func start() {
        guard !isLoggingOut else { return }
        let previous = runTask
        previous?.cancel()
        runTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await run()
        }
    }

    /// Закрывает соединение (1000) и прекращает переподключения.
    func stop() async {
        let task = runTask
        runTask = nil
        task?.cancel()
        await task?.value
    }

    /// Выход из аккаунта начинается (`AuthServiceObserver`): соединение закрывается до запроса выхода — сервер закроет
    /// соединения сессии с кодом 4003, и по ещё текущему соединению это выглядело бы как истечение сессии.
    /// Закрытие дожидается записей событий в БД — они не попадут туда после очистки. До конца выхода `start()`
    /// не подключается; заново работа с сервером начнётся при следующем входе.
    func authServiceWillLogout() async {
        isLoggingOut = true
        await stop()
    }

    /// Выход из аккаунта завершён (`AuthServiceObserver`): `start()` снова работает.
    /// - Parameter reason: причина выхода; на соединение не влияет.
    func authServiceDidLogout(reason: LogoutReason) async {
        isLoggingOut = false
    }

    /// Появилась сеть: если идёт задержка перед переподключением — переподключиться сразу.
    func networkDidBecomeAvailable() {
        reconnectDelayTask?.cancel()
    }

    /// Подписывает на события реального времени.
    func events() -> AsyncStream<RealtimeEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: RealtimeEvent.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.subscribers[id] = nil }
        }
        return stream
    }

    // MARK: - Цикл переподключения

    /// Подключается и переподключается, пока задачу не отменят или исход не скажет остановиться.
    /// Без задержки повторяется только первая попытка после 2004 или 4003: если и она закончилась тем же,
    /// не дойдя до `connected`, — ждём как при сбое, чтобы не забрасывать сервер запросами.
    private func run() async {
        var source = TokenSource.globalStart
        var attempt = 0
        var previousOutcome: ConnectionOutcome?
        while !Task.isCancelled {
            let (outcome, didConnect) = await connectOnce(using: source)
            if didConnect { attempt = 0 }
            let isRepeated = outcome == previousOutcome && !didConnect
            previousOutcome = outcome
            switch outcome {
            case .notAuthorized, .closedNormally:
                return
            case .sessionEnded, .tokenRejected:
                if isRepeated {
                    await waitBeforeReconnect(attempt: attempt)
                    attempt += 1
                }
                source = outcome == .sessionEnded ? .globalStart : .websocketToken
            case .failed:
                await waitBeforeReconnect(attempt: attempt)
                attempt += 1
                source = .websocketToken
            }
        }
    }

    /// Ждёт задержку перед переподключением; появление сети (`networkDidBecomeAvailable`) и отмена её прерывают.
    /// - Parameter attempt: номер переподключения подряд.
    private func waitBeforeReconnect(attempt: Int) async {
        let delay = backoff.delay(forAttempt: attempt)
        let sleep = sleep
        let wait = Task { _ = try? await sleep(delay) }
        reconnectDelayTask = wait
        await withTaskCancellationHandler {
            await wait.value
        } onCancel: {
            wait.cancel()
        }
        reconnectDelayTask = nil
    }

    // MARK: - Одно соединение

    /// Получает токен, подключается и обслуживает соединение до его закрытия.
    /// - Parameter source: откуда брать токен.
    /// - Returns: исход и признак того, что соединение дошло до `auth` / `connected`.
    private func connectOnce(using source: TokenSource) async -> (ConnectionOutcome, Bool) {
        let info: WebsocketConnectInfo
        switch await connectInfo(from: source) {
        case let .info(connectInfo): info = connectInfo
        case let .finished(outcome): return (outcome, false)
        }
        guard !Task.isCancelled else { return (.closedNormally, false) }
        guard let userId = sessionService.currentUser?.userId else { return (.notAuthorized, false) }

        let connection = connectionFactory.makeConnection(url: info.url)
        return await withTaskCancellationHandler {
            await serve(connection, userId: userId, token: info.token)
        } onCancel: {
            connection.close(code: WebSocketCloseCode.normal)
        }
    }

    /// Получает данные подключения.
    /// - Parameter source: откуда брать токен.
    /// - Returns: данные подключения либо исход, которым попытка заканчивается без подключения.
    private func connectInfo(from source: TokenSource) async -> ConnectInfoResult {
        switch source {
        case .globalStart: return await connectInfoFromGlobalStart()
        case .websocketToken: return await connectInfoFromTokenRequest()
        }
    }

    /// `/global/start`: `null` — пользователь не авторизован; если локально сессия ещё открыта, она завершается
    /// как истёкшая через `AuthService` (выход идёт отдельной задачей: он сам дожидается остановки этого цикла).
    /// Ошибка запроса при открытой сессии — повод переподключиться с задержкой.
    private func connectInfoFromGlobalStart() async -> ConnectInfoResult {
        do {
            guard let info = try await globalService.start() else {
                if sessionService.isLoggedIn {
                    authService.expireSession()
                }
                return .finished(.notAuthorized)
            }
            guard sessionService.isLoggedIn else { return .finished(.notAuthorized) }
            return .info(info)
        } catch {
            Logger.realtime.error("/global/start не выполнен: \(String(describing: error), privacy: .public)")
            return .finished(sessionService.isLoggedIn ? .failed : .notAuthorized)
        }
    }

    /// `/global/getWebsocketToken`: ошибка 2003 — сессии нет (сетевой слой уже завершил её), переподключаться не нужно.
    private func connectInfoFromTokenRequest() async -> ConnectInfoResult {
        guard sessionService.isLoggedIn else { return .finished(.notAuthorized) }
        do {
            return .info(try await globalService.fetchWebsocketToken())
        } catch NetworkError.api(let code) where code == NetworkError.Code.unauthorized {
            return .finished(.notAuthorized)
        } catch {
            Logger.realtime.error("Токен WebSocket не получен: \(String(describing: error), privacy: .public)")
            return .finished(.failed)
        }
    }

    /// Авторизует соединение и читает его до закрытия. Пока соединение открыто, его пингует отдельная задача.
    /// - Parameters:
    ///   - connection: открытое соединение.
    ///   - userId: пользователь, от имени которого оно авторизуется.
    ///   - token: одноразовый токен.
    /// - Returns: исход и признак того, что соединение дошло до `auth` / `connected`.
    private func serve(_ connection: WebSocketConnectionProtocol, userId: Int, token: String) async -> (ConnectionOutcome, Bool) {
        let state = ConnectionState()
        let keepAliveTask = Task { await keepAlive(connection, state: state) }
        defer { keepAliveTask.cancel() }
        do {
            try await connection.send(.authConnect(userId: userId, token: token))
        } catch {
            return (outcome(of: error, connectionErrorCode: nil, state: state), false)
        }
        return await receiveMessages(from: connection, userId: userId, state: state)
    }

    /// Читает сообщения соединения до его закрытия. До `auth` / `connected` обрабатываются только сообщения
    /// авторизации: сервер других не шлёт, а подтверждение до `connected` — ошибка протокола.
    /// - Returns: исход и признак того, что соединение дошло до `auth` / `connected`.
    private func receiveMessages(
        from connection: WebSocketConnectionProtocol,
        userId: Int,
        state: ConnectionState
    ) async -> (ConnectionOutcome, Bool) {
        var isConnected = false
        var connectionErrorCode: Int?
        while true {
            let message: WebSocketServerMessage
            do {
                message = try await connection.receive()
            } catch WebSocketConnectionError.malformedMessage {
                continue
            } catch {
                return (outcome(of: error, connectionErrorCode: connectionErrorCode, state: state), isConnected)
            }
            switch message.event {
            case .connected:
                isConnected = true
                broadcast(.connected)
            case let .connectionError(errorCode):
                connectionErrorCode = errorCode
            default:
                guard isConnected else { continue }
                guard await handle(message, from: connection, userId: userId) else {
                    connection.close(code: WebSocketCloseCode.normal)
                    return (.notAuthorized, isConnected)
                }
            }
        }
    }

    /// Исход соединения по ошибке, которой оно закончилось.
    /// - Parameters:
    ///   - error: ошибка отправки или чтения.
    ///   - connectionErrorCode: код из `auth` / `connectionError`, если он приходил.
    ///   - state: состояние соединения — закрыл ли его клиент по таймауту pong.
    private func outcome(of error: Error, connectionErrorCode: Int?, state: ConnectionState) -> ConnectionOutcome {
        guard !state.isPongTimedOut else { return .failed }
        guard case let WebSocketConnectionError.closed(code) = error else { return .failed }
        switch code {
        case WebSocketCloseCode.normal:
            return .closedNormally
        case WebSocketCloseCode.sessionEnded:
            return .sessionEnded
        case WebSocketCloseCode.authorizationFailed where connectionErrorCode == NetworkError.Code.websocketTokenInvalid:
            return .tokenRejected
        default:
            return .failed
        }
    }

    /// Heartbeat: ping каждые `pingInterval`; если pong не пришёл за `pongTimeout`, соединение закрывается
    /// как потерянное. Ошибка ping — соединение уже закрыто, это обработает чтение.
    /// - Parameters:
    ///   - connection: пингуемое соединение.
    ///   - state: куда отметить таймаут pong.
    private func keepAlive(_ connection: WebSocketConnectionProtocol, state: ConnectionState) async {
        var wait = pingInterval
        while true {
            guard (try? await sleep(wait)) != nil, !Task.isCancelled else { return }
            let pingState = PingState()
            Task {
                try? await connection.sendPing()
                pingState.isAnswered = true
            }
            guard (try? await sleep(pongTimeout)) != nil, !Task.isCancelled else { return }
            guard pingState.isAnswered else {
                state.isPongTimedOut = true
                connection.close(code: WebSocketCloseCode.normal)
                return
            }
            // Ожидание pong входит в интервал: ping уходит каждые `pingInterval`, а не реже.
            wait = pingInterval - pongTimeout
        }
    }

    // MARK: - События

    /// Применяет событие к БД, доставляет экранам, запускает загрузку упомянутых пользователей и подтверждает
    /// получение. Пользователей не ждёт: подтверждение — после применения к локальному состоянию.
    /// - Parameters:
    ///   - message: сообщение сервера после `connected`.
    ///   - connection: соединение, в которое уходит подтверждение.
    ///   - userId: пользователь, от имени которого авторизовано соединение.
    /// - Returns: `false`, если сессия за это время сменилась или закрылась: события чужого пользователя
    ///   не применяются, а соединение нужно закрыть.
    private func handle(_ message: WebSocketServerMessage, from connection: WebSocketConnectionProtocol, userId: Int) async -> Bool {
        guard sessionService.currentUser?.userId == userId else { return false }
        if let event = await apply(message.event) {
            broadcast(event)
        }
        if !message.userIds.isEmpty {
            let userIds = message.userIds
            Task { await userCache.loadUsers(ids: userIds) }
        }
        if message.requiresAcknowledgement {
            // Соединение могло закрыться — тогда подтверждение не отправляется, закрытие обработает чтение.
            try? await connection.send(.acknowledge(receivedUid: message.uid))
        }
        return true
    }

    /// Сохраняет данные события в БД. Ошибка записи не мешает доставить событие экранам.
    /// - Parameter event: событие сервера.
    /// - Returns: событие для экранов; `nil` — экранам доставлять нечего.
    private func apply(_ event: WebSocketServerEvent) async -> RealtimeEvent? {
        do {
            switch event {
            case let .conversationCreated(conversation):
                try await conversationStorage.save(conversation: conversation)
            case let .messageReceived(message), let .messageEdited(message):
                try await messageStorage.save(message: message)
            case .connected, .connectionError, .unknown:
                break
            }
        } catch {
            Logger.storage.error("Не удалось сохранить событие WebSocket в БД: \(String(describing: error), privacy: .public)")
        }
        return realtimeEvent(for: event)
    }

    /// Событие для экранов без записи в БД.
    /// - Parameter event: событие сервера.
    private func realtimeEvent(for event: WebSocketServerEvent) -> RealtimeEvent? {
        switch event {
        case let .conversationCreated(conversation): return .conversationCreated(conversation)
        case let .messageReceived(message): return .messageReceived(message)
        case let .messageEdited(message): return .messageEdited(message)
        case .connected, .connectionError, .unknown: return nil
        }
    }

    /// Доставляет событие всем подписчикам.
    private func broadcast(_ event: RealtimeEvent) {
        subscribers.values.forEach { $0.yield(event) }
    }
}

extension Logger {
    /// Лог WebSocket-соединения: сбои подключения не показываются пользователю — клиент переподключается сам.
    static let realtime = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Chatik", category: "Realtime")
}
