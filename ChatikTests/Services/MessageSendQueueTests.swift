//
//  MessageSendQueueTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class MessageSendQueueTests: XCTestCase {
    private var messageService: MessageServiceMock!
    private var messageStorage: MessageStorageServiceMock!
    private var outgoingStorage: OutgoingMessageStorageServiceMock!
    private var sessionService: SessionService!
    private var realtimeService: RealtimeServiceMock!

    override func setUp() async throws {
        try await super.setUp()
        messageService = MessageServiceMock()
        messageStorage = MessageStorageServiceMock()
        outgoingStorage = OutgoingMessageStorageServiceMock()
        let userDefaultsService = UserDefaultsServiceMock(currentUser: User(userId: 1, login: "ivan", name: "Ivan", avatar: nil))
        sessionService = SessionService(userDefaultsService: userDefaultsService, localStorageCleaner: LocalStorageCleanerMock())
        await sessionService.restore()
        realtimeService = RealtimeServiceMock()
    }

    // MARK: - Отправка

    /// Кейс: сообщение поставлено в очередь, сервер ещё не ответил.
    /// Ожидание: сообщение текущего пользователя с обрезанными краевыми пробелами сразу в очереди в статусе
    /// «отправляется» и сохранено в БД; на сервер ушёл тот же текст с перепиской и сгенерированным `clientId`.
    func test_enqueue_addsSendingMessageAndSendsIt() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.onSend = { await gate.wait() }

        sut.enqueue(text: "  Привет \n", conversationId: 7)

        XCTAssertEqual(sut.outgoingMessages, [.stub(clientId: "c1", conversationId: 7, text: "Привет", createdAt: now, status: .sending)])
        await yieldUntil { gate.isWaiting }
        XCTAssertEqual(outgoingStorage.messages["c1"]?.status, .sending)
        XCTAssertEqual(messageService.sentRequests.map(\.text), ["Привет"])
        XCTAssertEqual(messageService.sentRequests.map(\.conversationId), [7])
        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1"])
        gate.open()
    }

    /// Кейс: сессии нет.
    /// Ожидание: сообщение не ставится в очередь и не отправляется.
    func test_enqueue_withoutSession_isIgnored() async {
        await sessionService.end()
        let sut = makeSUT()

        sut.enqueue(text: "Привет", conversationId: 1)

        XCTAssertTrue(sut.outgoingMessages.isEmpty)
        XCTAssertTrue(messageService.sentRequests.isEmpty)
    }

    /// Кейс: сервер принял сообщение.
    /// Ожидание: созданное сообщение опубликовано подписчикам и сохранено в БД, из очереди сообщение убрано.
    func test_enqueue_success_publishesSavesAndRemoves() async {
        let sut = makeSUT()
        let sent = Message.make(id: 2, clientId: "c1")
        messageService.stubbedSentMessage = .success(sent)
        var published: [Message] = []
        let subscription = Task { for await message in sut.sentMessages() { published.append(message) } }
        await Task.yield()

        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { sut.outgoingMessages.isEmpty }

        await yieldUntil { published == [sent] }
        await yieldUntil { [unowned self] in messageStorage.savedMessages == [sent] }
        subscription.cancel()
    }

    /// Кейс: в очереди два сообщения; сервер принял первое, а его запись в БД ещё не завершилась.
    /// Ожидание: первое уже убрано из очереди, второе отправлено, не дожидаясь записи; после записи сохранены оба.
    func test_confirm_doesNotWaitForStorage() async {
        let sut = makeSUT()
        let saveGate = Gate()
        messageStorage.onSave = { await saveGate.wait() }
        messageService.stubbedSentMessages = [
            .success(.make(id: 1, clientId: "c1")),
            .success(.make(id: 2, clientId: "c2")),
        ]
        sut.enqueue(text: "Первое", conversationId: 1)
        sut.enqueue(text: "Второе", conversationId: 1)

        await yieldUntil { sut.outgoingMessages.isEmpty }
        await yieldUntil { saveGate.isWaiting }

        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1", "c2"])
        XCTAssertTrue(messageStorage.savedMessages.isEmpty)
        messageStorage.onSave = nil
        saveGate.open()
        await yieldUntil { [unowned self] in messageStorage.savedMessages.map(\.messageId) == [1, 2] }
    }

    /// Кейс: отправка не удалась.
    /// Ожидание: сообщение осталось в очереди в статусе «не отправлено», статус сохранён в БД, повторно само не отправляется.
    func test_enqueue_failure_marksFailed() async {
        let sut = makeSUT()
        messageService.stubbedSentMessage = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))

        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { [unowned self] in outgoingStorage.messages["c1"]?.status == .failed }

        XCTAssertEqual(sut.outgoingMessages.map(\.status), [.failed])
        XCTAssertEqual(messageService.sentRequests.count, 1)
    }

    /// Кейс: в очереди три сообщения; отправка первого не удалась.
    /// Ожидание: все три в статусе «не отправлено» (статусы сохранены в БД), второе и третье на сервер не уходили.
    func test_failure_marksRemainingQueueFailed() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.stubbedSentMessage = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Первое", conversationId: 1)
        sut.enqueue(text: "Второе", conversationId: 2)
        sut.enqueue(text: "Третье", conversationId: 1)
        await yieldUntil { gate.isWaiting }

        gate.open()

        await yieldUntil { [unowned self] in outgoingStorage.messages.values.filter { $0.status == .failed }.count == 3 }
        XCTAssertEqual(sut.outgoingMessages.map(\.status), [.failed, .failed, .failed])
        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1"])
    }

    /// Кейс: отправка сообщения не удалась, после этого поставлено новое.
    /// Ожидание: новое отправлено — упавшее сообщение ждёт ручного повтора и очередь не блокирует.
    func test_failure_thenNewMessage_isSent() async {
        let sut = makeSUT()
        messageService.stubbedSentMessages = [
            .failure(NetworkError.transport(URLError(.timedOut))),
            .success(.make(id: 2, clientId: "c2")),
        ]
        sut.enqueue(text: "Первое", conversationId: 1)
        await yieldUntil { sut.outgoingMessages.first?.status == .failed }

        sut.enqueue(text: "Второе", conversationId: 1)

        await yieldUntil { sut.outgoingMessages.map(\.clientId) == ["c1"] }
        XCTAssertEqual(sut.outgoingMessages.map(\.status), [.failed])
        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1", "c2"])
    }

    /// Кейс: в очереди два сообщения; `clientId` первого сервер отклонил как занятый (6004).
    /// Ожидание: первое удалено, второе отправлено — удалённое сообщение порядок не нарушает.
    func test_clientIdConflict_continuesQueue() async {
        let sut = makeSUT()
        messageService.stubbedSentMessages = [
            .failure(NetworkError.api(code: NetworkError.Code.clientIdConflict)),
            .success(.make(id: 2, clientId: "c2")),
        ]
        sut.enqueue(text: "Первое", conversationId: 1)
        sut.enqueue(text: "Второе", conversationId: 1)

        await yieldUntil { sut.outgoingMessages.isEmpty }

        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1", "c2"])
    }

    /// Кейс: сервер отклонил `clientId` как занятый в другой переписке (6004).
    /// Ожидание: сообщение удалено из очереди и из БД, повторно ничего не отправлено.
    func test_enqueue_clientIdConflict_deletesMessage() async {
        let sut = makeSUT()
        messageService.stubbedSentMessage = .failure(NetworkError.api(code: NetworkError.Code.clientIdConflict))

        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { [unowned self] in outgoingStorage.deletedClientIds == ["c1"] }

        XCTAssertTrue(sut.outgoingMessages.isEmpty)
        XCTAssertTrue(outgoingStorage.messages.isEmpty)
        XCTAssertEqual(messageService.sentRequests.count, 1)
    }

    /// Кейс: пока первое сообщение отправляется, в очередь поставлено второе — в другую переписку.
    /// Ожидание: второй запрос уходит только после ответа на первый — очередь общая, порядок сохраняется.
    func test_enqueue_whileSending_sendsInOrder() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.stubbedSentMessages = [
            .success(.make(id: 1, clientId: "c1")),
            .success(.make(id: 2, conversationId: 2, clientId: "c2")),
        ]
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Первое", conversationId: 1)
        await yieldUntil { gate.isWaiting }

        sut.enqueue(text: "Второе", conversationId: 2)

        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["c1", "c2"])
        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1"])
        messageService.onSend = nil
        gate.open()
        await yieldUntil { sut.outgoingMessages.isEmpty }
        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1", "c2"])
    }

    // MARK: - Повтор и удаление

    /// Кейс: неотправленное сообщение отправлено повторно, на этот раз успешно.
    /// Ожидание: до ответа — снова статус «отправляется»; повтор ушёл с тем же `clientId`, сообщение убрано из очереди.
    func test_retry_success_sendsSameClientId() async {
        let sut = makeSUT()
        messageService.stubbedSentMessages = [
            .failure(NetworkError.transport(URLError(.timedOut))),
            .success(.make(id: 2, clientId: "c1")),
        ]
        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { sut.outgoingMessages.first?.status == .failed }

        sut.retry(clientId: "c1")

        XCTAssertEqual(sut.outgoingMessages.map(\.status), [.sending])
        await yieldUntil { sut.outgoingMessages.isEmpty }
        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1", "c1"])
    }

    /// Кейс: удаление неотправленного сообщения и попытка удалить отправляющееся.
    /// Ожидание: неотправленное убрано из очереди и БД, отправляющееся не тронуто.
    func test_delete_removesFailedOnly() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.stubbedSentMessages = [.failure(NetworkError.transport(URLError(.timedOut)))]
        sut.enqueue(text: "Первое", conversationId: 1)
        await yieldUntil { sut.outgoingMessages.first?.status == .failed }
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Второе", conversationId: 1)
        await yieldUntil { gate.isWaiting }

        sut.delete(clientId: "c1")
        sut.delete(clientId: "c2")

        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["c2"])
        await yieldUntil { [unowned self] in outgoingStorage.deletedClientIds == ["c1"] }
        gate.open()
    }

    // MARK: - Подтверждение помимо ответа

    /// Кейс: событие WebSocket о собственном сообщении пришло раньше ответа `/messages/send` (чат может быть закрыт).
    /// Ожидание: сообщение сразу убрано из очереди; ответ, пришедший следом, его не возвращает.
    func test_realtimeEvent_ownMessage_removesFromQueue() async {
        let sut = makeSUT()
        let gate = Gate()
        let sent = Message.make(id: 2, clientId: "c1")
        messageService.stubbedSentMessage = .success(sent)
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { gate.isWaiting }

        realtimeService.send(.messageReceived(sent))

        await yieldUntil { sut.outgoingMessages.isEmpty }
        gate.open()
        await yieldUntil { [unowned self] in messageStorage.savedMessages == [sent] }
        XCTAssertTrue(sut.outgoingMessages.isEmpty)
    }

    /// Кейс: событием пришло сообщение другого отправителя с тем же `clientId`.
    /// Ожидание: очередь не меняется — `clientId` сравнивается вместе с отправителем.
    func test_realtimeEvent_otherSenderSameClientId_keepsMessage() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { gate.isWaiting }

        realtimeService.send(.messageReceived(.make(id: 2, senderId: 2, clientId: "c1")))
        sut.removeConfirmed(by: [.make(id: 3, senderId: 2, clientId: "c1")])

        await Task.yield()
        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["c1"])
        gate.open()
    }

    // MARK: - Восстановление

    /// Кейс: в БД неотправленные сообщения двух переписок — прерванное перезапуском («отправляется») и неудачное.
    /// Ожидание: оба в очереди в своих статусах; прерванное отправлено повторно с тем же `clientId`,
    /// неудачное само не отправляется.
    func test_start_restoresAndResendsInterrupted() async {
        outgoingStorage.messages = [
            "old": .stub(clientId: "old", conversationId: 2, createdAt: now, status: .failed),
            "new": .stub(clientId: "new", createdAt: now.addingTimeInterval(1), status: .sending),
        ]
        let gate = Gate()
        messageService.onSend = { await gate.wait() }
        let sut = makeSUT()

        sut.start()

        await yieldUntil { sut.outgoingMessages.count == 2 }
        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["old", "new"])
        XCTAssertEqual(sut.outgoingMessages.map(\.status), [.failed, .sending])
        await yieldUntil { gate.isWaiting }
        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["new"])
        gate.open()
    }

    /// Кейс: очередь восстанавливается повторно, сообщение из БД уже в памяти.
    /// Ожидание: оно не дублируется и не отправляется второй раз.
    func test_start_twice_doesNotDuplicate() async {
        outgoingStorage.messages = ["a": .stub(clientId: "a", status: .failed)]
        let sut = makeSUT()

        sut.start()
        await yieldUntil { sut.outgoingMessages.count == 1 }
        sut.start()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["a"])
    }

    // MARK: - Выход из аккаунта

    /// Кейс: в очереди два сообщения, первое отправляется; пользователь выходит из аккаунта, затем приходит
    /// ответ на прерванный запрос.
    /// Ожидание: очередь очищена, второе сообщение не отправлено, ответ на прерванный запрос не применён
    /// (статус в БД не перезаписан); выход дождался завершения отправки.
    func test_willLogout_cancelsQueue() async {
        let sut = makeSUT()
        let gate = Gate()
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Первое", conversationId: 1)
        sut.enqueue(text: "Второе", conversationId: 1)
        await yieldUntil { gate.isWaiting }
        var isLogoutFinished = false

        let logout = Task {
            await sut.authServiceWillLogout()
            isLogoutFinished = true
        }
        await yieldUntil { sut.outgoingMessages.isEmpty }
        XCTAssertFalse(isLogoutFinished)
        gate.open()
        await logout.value

        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1"])
        XCTAssertEqual(outgoingStorage.messages["c1"]?.status, .sending)
        XCTAssertTrue(messageStorage.savedMessages.isEmpty)
    }

    /// Кейс: сообщение поставлено в очередь во время выхода, затем после его завершения.
    /// Ожидание: во время выхода сообщение не принимается, после — принимается и отправляется.
    func test_enqueue_duringLogout_isIgnored() async {
        let sut = makeSUT()
        messageService.stubbedSentMessage = .success(.make(id: 1, clientId: "c1"))
        await sut.authServiceWillLogout()

        sut.enqueue(text: "Во время выхода", conversationId: 1)
        XCTAssertTrue(sut.outgoingMessages.isEmpty)
        await sut.authServiceDidLogout(reason: .userInitiated)
        sut.enqueue(text: "После выхода", conversationId: 1)

        await yieldUntil { [unowned self] in messageService.sentRequests.count == 1 }
        XCTAssertEqual(messageService.sentRequests.map(\.text), ["После выхода"])
    }

    // MARK: - Helpers

    private let now = Date(timeIntervalSince1970: 1_790_846_400)

    /// Создаёт очередь над моками этого теста; `clientId` — `c1`, `c2`, ... по порядку.
    private func makeSUT() -> MessageSendQueue {
        var counter = 0
        return MessageSendQueue(
            messageService: messageService,
            messageStorage: messageStorage,
            outgoingMessageStorage: outgoingStorage,
            sessionService: sessionService,
            realtimeService: realtimeService,
            now: { [now] in now },
            makeClientId: {
                counter += 1
                return "c\(counter)"
            }
        )
    }
}
