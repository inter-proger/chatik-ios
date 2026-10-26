//
//  MessageSendQueueTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class MessageSendQueueTests: XCTestCase {
    private var messageService: MessageServiceMock!
    private var messageCache: MessageCacheServiceMock!
    private var outgoingStorage: OutgoingMessageStorageServiceMock!
    private var eventQueue: RealtimeEventQueueMock!
    private var positionUpdater: ConversationPositionUpdatingMock!
    /// Проверка членства — мок списка переписок.
    private var membership = ConversationListServiceMock()

    override func setUp() async throws {
        try await super.setUp()
        messageService = MessageServiceMock()
        messageCache = MessageCacheServiceMock()
        outgoingStorage = OutgoingMessageStorageServiceMock()
        eventQueue = RealtimeEventQueueMock()
        positionUpdater = ConversationPositionUpdatingMock()
    }

    // MARK: - Отправка

    /// Кейс: сообщение поставлено в очередь, сервер ещё не ответил.
    /// Ожидание: сообщение текущего пользователя с обрезанными краевыми пробелами сразу в очереди в статусе
    /// «отправляется» и сохранено в БД; на сервер ушёл тот же текст с перепиской и сгенерированным `clientId`.
    func test_enqueue_addsSendingMessageAndSendsIt() async {
        let sut = await makeActiveSUT()
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

    /// Кейс: очередь ещё не загружена (сессии нет).
    /// Ожидание: сообщение не ставится в очередь и не отправляется.
    func test_enqueue_beforeLoad_isIgnored() async {
        let sut = makeSUT()
        sut.resumeDeliveries()

        sut.enqueue(text: "Привет", conversationId: 1)

        XCTAssertTrue(sut.outgoingMessages.isEmpty)
        XCTAssertTrue(messageService.sentRequests.isEmpty)
    }

    /// Кейс: очередь загружена для пользователя 5.
    /// Ожидание: отправитель нового сообщения — пользователь из `load`.
    func test_enqueue_senderIsLoadedUser() async {
        let sut = await makeActiveSUT(userId: 5)

        sut.enqueue(text: "Привет", conversationId: 1)

        XCTAssertEqual(sut.outgoingMessages.map(\.senderId), [5])
    }

    /// Кейс: сервер принял сообщение.
    /// Ожидание: переписка поднята в списке чатов, созданное сообщение опубликовано подписчикам и записано в кэш
    /// сообщений, из очереди сообщение убрано.
    func test_enqueue_success_publishesSavesAndRemoves() async {
        let sut = await makeActiveSUT()
        let sent = Message.make(id: 2, clientId: "c1")
        messageService.stubbedSentMessage = .success(sent)
        var published: [Message] = []
        let subscription = Task { for await message in sut.sentMessages() { published.append(message) } }
        await Task.yield()

        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { sut.outgoingMessages.isEmpty }

        await yieldUntil { published == [sent] }
        await yieldUntil { [unowned self] in messageCache.sentMessages == [sent] }
        XCTAssertEqual(positionUpdater.sentMessages, [sent])
        subscription.cancel()
    }

    /// Кейс: сервер принял сообщение, в ответе — прочтение переписки для отправителя.
    /// Ожидание: прочтение передано списку чатов вместе с сообщением.
    func test_enqueue_success_passesReadInfo() async {
        let sut = await makeActiveSUT()
        let sent = Message.make(id: 2, clientId: "c1")
        let readInfo = ReadInfo.make(conversationId: 1, lastRead: 2, total: 4, version: 30)
        messageService.stubbedSentMessage = .success(sent)
        messageService.stubbedSentReadInfo = readInfo

        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { [unowned self] in !positionUpdater.sentMessages.isEmpty }

        XCTAssertEqual(positionUpdater.sentMessages, [sent])
        XCTAssertEqual(positionUpdater.sentReadInfos, [readInfo])
    }

    /// Кейс: сервер отклонил отправку.
    /// Ожидание: переписка в списке чатов не поднимается.
    func test_enqueue_failure_doesNotLiftConversation() async {
        let sut = await makeActiveSUT()
        messageService.stubbedSentMessage = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))

        sut.enqueue(text: "Привет", conversationId: 1)

        await yieldUntil { sut.outgoingMessages.first?.status == .failed }
        XCTAssertTrue(positionUpdater.sentMessages.isEmpty)
    }

    /// Кейс: в очереди два сообщения; сервер принял первое, а его запись в БД ещё не завершилась.
    /// Ожидание: первое уже убрано из очереди, второе отправлено, не дожидаясь записи; после записи сохранены оба.
    func test_confirm_doesNotWaitForStorage() async {
        let sut = await makeActiveSUT()
        let saveGate = Gate()
        messageCache.onApplySent = { await saveGate.wait() }
        messageService.stubbedSentMessages = [
            .success(.make(id: 1, clientId: "c1")),
            .success(.make(id: 2, clientId: "c2")),
        ]
        sut.enqueue(text: "Первое", conversationId: 1)
        sut.enqueue(text: "Второе", conversationId: 1)

        await yieldUntil { sut.outgoingMessages.isEmpty }
        await yieldUntil { saveGate.isWaiting }

        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1", "c2"])
        XCTAssertTrue(messageCache.sentMessages.isEmpty)
        messageCache.onApplySent = nil
        saveGate.open()
        await yieldUntil { [unowned self] in messageCache.sentMessages.map(\.messageId) == [1, 2] }
    }

    /// Кейс: отправка не удалась.
    /// Ожидание: сообщение осталось в очереди в статусе «не отправлено», статус сохранён в БД, повторно само не отправляется.
    func test_enqueue_failure_marksFailed() async {
        let sut = await makeActiveSUT()
        messageService.stubbedSentMessage = .failure(NetworkError.transport(URLError(.notConnectedToInternet)))

        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { [unowned self] in outgoingStorage.messages["c1"]?.status == .failed }

        XCTAssertEqual(sut.outgoingMessages.map(\.status), [.failed])
        XCTAssertEqual(messageService.sentRequests.count, 1)
    }

    /// Кейс: в очереди три сообщения; отправка первого не удалась.
    /// Ожидание: все три в статусе «не отправлено» (статусы сохранены в БД), второе и третье на сервер не уходили.
    func test_failure_marksRemainingQueueFailed() async {
        let sut = await makeActiveSUT()
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
        let sut = await makeActiveSUT()
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
        let sut = await makeActiveSUT()
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
        let sut = await makeActiveSUT()
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
        let sut = await makeActiveSUT()
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
        let sut = await makeActiveSUT()
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
        let sut = await makeActiveSUT()
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

    /// Кейс: событие WebSocket о собственном сообщении пришло через очередь событий раньше ответа `/messages/send`
    /// (чат может быть закрыт).
    /// Ожидание: сообщение сразу убрано из очереди; ответ, пришедший следом, его не возвращает.
    func test_realtimeEvent_ownMessage_removesFromQueue() async {
        let sut = await makeActiveSUT()
        let gate = Gate()
        let sent = Message.make(id: 2, clientId: "c1")
        messageService.stubbedSentMessage = .success(sent)
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { gate.isWaiting }

        await eventQueue.send(.messageReceived(sent, LastMessage(message: sent), nil))

        await yieldUntil { sut.outgoingMessages.isEmpty }
        gate.open()
        await yieldUntil { [unowned self] in messageCache.sentMessages == [sent] }
        XCTAssertTrue(sut.outgoingMessages.isEmpty)
    }

    /// Кейс: событием пришло сообщение другого отправителя с тем же `clientId`.
    /// Ожидание: очередь не меняется — `clientId` сравнивается вместе с отправителем.
    func test_realtimeEvent_otherSenderSameClientId_keepsMessage() async {
        let sut = await makeActiveSUT()
        let gate = Gate()
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { gate.isWaiting }

        await eventQueue.send(.messageReceived(.make(id: 2, senderId: 2, clientId: "c1"), .make(id: 2), nil))
        sut.removeConfirmed(by: [.make(id: 3, senderId: 2, clientId: "c1")])

        await Task.yield()
        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["c1"])
        gate.open()
    }

    // MARK: - Загрузка

    /// Кейс: в БД сообщения двух пользователей; загружается очередь первого.
    /// Ожидание: в памяти только его сообщения в порядке отправки и в своих статусах.
    func test_load_readsOnlyUserMessages() async {
        outgoingStorage.put([
            .stub(clientId: "late", senderId: 1, createdAt: now.addingTimeInterval(1), status: .failed),
            .stub(clientId: "foreign", senderId: 2, createdAt: now, status: .failed),
            .stub(clientId: "early", senderId: 1, createdAt: now, status: .sending),
        ])
        let sut = makeSUT()

        await sut.load(userId: 1)

        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["early", "late"])
        XCTAssertEqual(sut.outgoingMessages.map(\.status), [.sending, .failed])
        XCTAssertEqual(outgoingStorage.fetchedSenderIds, [1])
    }

    /// Кейс: в БД сообщение старше срока жизни и сообщение ровно на границе срока.
    /// Ожидание: до чтения удалены сообщения раньше `now − unsentMessageLifetime`; сообщение на границе загружено.
    func test_load_deletesExpiredBeforeFetch() async {
        let boundary = now.addingTimeInterval(-MessageSendQueue.unsentMessageLifetime)
        outgoingStorage.put([
            .stub(clientId: "expired", createdAt: boundary.addingTimeInterval(-1), status: .failed),
            .stub(clientId: "edge", createdAt: boundary, status: .failed),
        ])
        let sut = makeSUT()

        await sut.load(userId: 1)

        XCTAssertEqual(outgoingStorage.calls, ["deleteAll", "fetchAll"])
        XCTAssertEqual(outgoingStorage.deletedBeforeDates, [boundary])
        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["edge"])
    }

    /// Кейс: в БД сообщения в статусе «отправляется» (приложение закрыли во время отправки) и неотправленное;
    /// очередь загружена, а отправка ещё не запущена; затем пользователь отправил новое сообщение.
    /// Ожидание: до `resumeDeliveries()` ничего не отправлено; после — прерванные уходят в порядке отправки, следом
    /// новое; неотправленное само не отправляется.
    func test_load_doesNotSendUntilResume() async {
        outgoingStorage.put([
            .stub(clientId: "second", createdAt: now.addingTimeInterval(2), status: .sending),
            .stub(clientId: "failed", createdAt: now.addingTimeInterval(1), status: .failed),
            .stub(clientId: "first", createdAt: now, status: .sending),
        ])
        messageService.stubbedSentMessages = [
            .success(.make(id: 1, clientId: "first")),
            .success(.make(id: 2, clientId: "second")),
            .success(.make(id: 3, clientId: "c1")),
        ]
        let sut = makeSUT()
        await sut.load(userId: 1)
        sut.enqueue(text: "Новое", conversationId: 1)
        await Task.yield()
        XCTAssertTrue(messageService.sentRequests.isEmpty)

        sut.resumeDeliveries()

        await yieldUntil { [unowned self] in messageService.sentRequests.count == 3 }
        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["first", "second", "c1"])
    }

    /// Кейс: `resumeDeliveries()` вызван до загрузки очереди, затем очередь загружена.
    /// Ожидание: вызов до загрузки ничего не запускает — после загрузки отправка снова ждёт `resumeDeliveries()`.
    func test_resumeBeforeLoad_isIgnored() async {
        outgoingStorage.put([.stub(clientId: "a", status: .sending)])
        let sut = makeSUT()

        sut.resumeDeliveries()
        await sut.load(userId: 1)
        await Task.yield()

        XCTAssertTrue(messageService.sentRequests.isEmpty)
    }

    /// Кейс: `resumeDeliveries()` вызван дважды, в БД одно прерванное сообщение.
    /// Ожидание: сообщение отправлено один раз.
    func test_resumeTwice_sendsOnce() async {
        outgoingStorage.put([.stub(clientId: "a", status: .sending)])
        let sut = makeSUT()
        await sut.load(userId: 1)

        sut.resumeDeliveries()
        sut.resumeDeliveries()

        await yieldUntil { sut.outgoingMessages.first?.status == .failed }
        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["a"])
    }

    /// Кейс: очередь пользователя загружена; загрузка для того же пользователя вызвана повторно.
    /// Ожидание: БД повторно не читается, очередь не меняется.
    func test_load_sameUserTwice_readsOnce() async {
        outgoingStorage.put([.stub(clientId: "a", status: .failed)])
        let sut = makeSUT()
        await sut.load(userId: 1)

        await sut.load(userId: 1)

        XCTAssertEqual(outgoingStorage.fetchedSenderIds, [1])
        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["a"])
    }

    /// Кейс: чтение очереди из БД не удалось; затем пользователь отправляет сообщение, и загрузка для него
    /// вызвана повторно.
    /// Ожидание: очередь пуста, но принимает сообщения; повторная загрузка БД не читает и сообщение не теряет.
    func test_load_fetchError_acceptsMessagesAndDoesNotReread() async {
        outgoingStorage.put([.stub(clientId: "old", status: .failed)])
        outgoingStorage.stubbedFetchError = CocoaError(.fileReadCorruptFile)
        let sut = makeSUT()
        await sut.load(userId: 1)
        sut.resumeDeliveries()

        sut.enqueue(text: "Привет", conversationId: 1)
        await sut.load(userId: 1)

        XCTAssertEqual(outgoingStorage.fetchedSenderIds, [1])
        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["c1"])
    }

    /// Кейс: загрузка первого пользователя ещё читает БД, когда вызвана загрузка второго.
    /// Ожидание: вторая дождалась первой — загрузки применены в порядке вызова, в памяти очередь второго.
    func test_load_twoCalls_applyInCallOrder() async {
        outgoingStorage.put([
            .stub(clientId: "first", senderId: 1, status: .failed),
            .stub(clientId: "second", senderId: 2, status: .failed),
        ])
        let gate = Gate()
        outgoingStorage.onFetch = { await gate.wait() }
        let sut = makeSUT()
        let firstLoad = Task { await sut.load(userId: 1) }
        await yieldUntil { gate.isWaiting }

        let secondLoad = Task { await sut.load(userId: 2) }
        await Task.yield()
        outgoingStorage.onFetch = nil
        gate.open()
        await firstLoad.value
        await secondLoad.value

        XCTAssertEqual(outgoingStorage.fetchedSenderIds, [1, 2])
        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["second"])
    }

    /// Кейс: очередь первого пользователя загружена, его сообщение отправляется; загружается очередь второго
    /// без выхода первого (сессию сменили в обход `AuthService`).
    /// Ожидание: отправка первого отменена и ответ не применён, его сообщение осталось в БД в своём статусе
    /// (ничего не записано), в памяти — очередь второго, и её отправка ждёт `resumeDeliveries()`.
    func test_load_otherUserWithoutLogout_abandonsPreviousQueue() async {
        outgoingStorage.put([.stub(clientId: "foreign", senderId: 2, status: .sending)])
        let sut = await makeActiveSUT(userId: 1)
        let gate = Gate()
        messageService.stubbedSentMessage = .success(.make(id: 1, clientId: "c1"))
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Первого", conversationId: 1)
        await yieldUntil { gate.isWaiting }

        let load = Task { await sut.load(userId: 2) }
        await Task.yield()
        gate.open()
        await load.value

        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["foreign"])
        XCTAssertEqual(outgoingStorage.messages["c1"]?.status, .sending)
        XCTAssertTrue(messageCache.sentMessages.isEmpty)
        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1"])
    }

    /// Кейс: очередь загружается, и во время чтения БД начинается выход из аккаунта.
    /// Ожидание: прочитанное не применяется — очередь пуста и сообщений не принимает.
    func test_load_logoutDuringFetch_discardsResult() async {
        outgoingStorage.put([.stub(clientId: "a", status: .failed)])
        let gate = Gate()
        outgoingStorage.onFetch = { await gate.wait() }
        let sut = makeSUT()
        let load = Task { await sut.load(userId: 1) }
        await yieldUntil { gate.isWaiting }

        await sut.authServiceWillLogout()
        gate.open()
        await load.value
        sut.enqueue(text: "Привет", conversationId: 1)

        XCTAssertTrue(sut.outgoingMessages.isEmpty)
    }

    // MARK: - Превью для списка чатов

    /// Кейс: в очереди переписки 1 два неотправленных сообщения и одно отправляющееся (самое новое), в переписке 2 —
    /// только отправляющееся.
    /// Ожидание: для переписки 1 — текст последнего по времени неотправленного, для переписки 2 — `nil`.
    func test_lastFailedText_lastFailedPerConversation() async {
        outgoingStorage.put([
            .stub(clientId: "a", conversationId: 1, text: "Первое", createdAt: now, status: .failed),
            .stub(clientId: "b", conversationId: 1, text: "Второе", createdAt: now.addingTimeInterval(1), status: .failed),
            .stub(clientId: "c", conversationId: 1, text: "Третье", createdAt: now.addingTimeInterval(2), status: .sending),
            .stub(clientId: "d", conversationId: 2, text: "Другое", createdAt: now, status: .sending),
        ])
        let sut = makeSUT()

        await sut.load(userId: 1)

        XCTAssertEqual(sut.lastFailedText(for: 1), "Второе")
        XCTAssertNil(sut.lastFailedText(for: 2))
        XCTAssertNil(sut.lastFailedText(for: 3))
    }

    /// Кейс: в переписке одно неотправленное сообщение; его повторяют (успешно), затем другое неотправленное удаляют.
    /// Ожидание: на время повтора и после подтверждения текста нет; удаление единственного неотправленного другой
    /// переписки тоже убирает текст.
    func test_lastFailedText_followsRetryConfirmAndDelete() async {
        outgoingStorage.put([
            .stub(clientId: "a", conversationId: 1, text: "Повторю", status: .failed),
            .stub(clientId: "b", conversationId: 2, text: "Удалю", status: .failed),
        ])
        let sut = await makeActiveSUT()
        let gate = Gate()
        messageService.stubbedSentMessage = .success(.make(id: 1, conversationId: 1, clientId: "a"))
        messageService.onSend = { await gate.wait() }

        sut.retry(clientId: "a")
        let duringRetry = sut.lastFailedText(for: 1)
        await yieldUntil { gate.isWaiting }
        gate.open()
        await yieldUntil { sut.outgoingMessages.map(\.clientId) == ["b"] }
        sut.delete(clientId: "b")

        XCTAssertNil(duringRetry)
        XCTAssertNil(sut.lastFailedText(for: 1))
        XCTAssertNil(sut.lastFailedText(for: 2))
    }

    /// Кейс: в очереди есть неотправленное сообщение; пользователь отправляет новое — оно в статусе «отправляется».
    /// Ожидание: индекс не присваивается заново — список чатов не узнаёт об изменении.
    func test_lastFailedTexts_unchangedValue_doesNotNotify() async {
        outgoingStorage.put([.stub(clientId: "a", status: .failed)])
        let sut = await makeActiveSUT()
        let gate = Gate()
        messageService.onSend = { await gate.wait() }
        let changed = ObservationFlag()
        withObservationTracking { _ = sut.lastFailedText(for: 1) } onChange: { changed.isSet = true }

        sut.enqueue(text: "Новое", conversationId: 1)
        await yieldUntil { gate.isWaiting }

        XCTAssertFalse(changed.isSet)
        XCTAssertEqual(sut.outgoingMessages.count, 2)
        gate.open()
    }

    /// Кейс: в очереди три сообщения разных переписок; отправка первого не удалась — все становятся неотправленными.
    /// Ожидание: тексты всех трёх переписок в индексе.
    func test_lastFailedText_failureOfQueue_indexesAll() async {
        let sut = await makeActiveSUT()
        let gate = Gate()
        messageService.stubbedSentMessage = .failure(NetworkError.transport(URLError(.timedOut)))
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Первое", conversationId: 1)
        sut.enqueue(text: "Второе", conversationId: 2)
        sut.enqueue(text: "Третье", conversationId: 3)
        await yieldUntil { gate.isWaiting }

        gate.open()

        await yieldUntil { sut.lastFailedText(for: 3) != nil }
        XCTAssertEqual([1, 2, 3].map(sut.lastFailedText(for:)), ["Первое", "Второе", "Третье"])
    }

    // MARK: - Подтверждение и неотправленная копия

    /// Кейс: сервер принял сообщение, кэш записал его вместе с удалением копии.
    /// Ожидание: очередь копию сама не удаляет — второй записи нет.
    func test_confirm_cacheWrote_doesNotDeleteCopy() async {
        let sut = await makeActiveSUT()
        messageService.stubbedSentMessage = .success(.make(id: 1, clientId: "c1"))

        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { [unowned self] in messageCache.sentMessages.count == 1 }
        await Task.yield()

        XCTAssertTrue(outgoingStorage.deletedClientIds.isEmpty)
    }

    /// Кейс: сервер принял сообщение, а кэш запись отбросил (он уже в выходе).
    /// Ожидание: неотправленную копию удаляет из БД очередь.
    func test_confirm_cacheRejected_deletesCopy() async {
        let sut = await makeActiveSUT()
        messageCache.stubbedApplySentResult = .discarded
        messageService.stubbedSentMessage = .success(.make(id: 1, clientId: "c1"))

        sut.enqueue(text: "Привет", conversationId: 1)

        await yieldUntil { [unowned self] in outgoingStorage.deletedClientIds == ["c1"] }
        XCTAssertNil(outgoingStorage.messages["c1"])
    }

    /// Кейс: сервер принял сообщение, а запись в кэш не удалась (ошибка БД, не выход).
    /// Ожидание: очередь копию не удаляет — она останется в БД «отправляющейся» и уйдёт повторно с тем же
    /// `clientId` при следующей загрузке.
    func test_confirm_cacheWriteFailed_keepsCopy() async {
        let sut = await makeActiveSUT()
        var isApplySentCalled = false
        messageCache.stubbedApplySentResult = .failed
        messageCache.onApplySent = { isApplySentCalled = true }
        messageService.stubbedSentMessage = .success(.make(id: 1, clientId: "c1"))

        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { isApplySentCalled }
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(outgoingStorage.deletedClientIds.isEmpty)
        XCTAssertEqual(outgoingStorage.messages["c1"]?.status, .sending)
        XCTAssertTrue(sut.outgoingMessages.isEmpty)
    }

    // MARK: - Выход из аккаунта

    /// Кейс: в очереди два сообщения, первое отправляется; пользователь выходит из аккаунта, затем приходит
    /// ответ на прерванный запрос.
    /// Ожидание: выход дождался прерванной отправки; оба сообщения в БД неотправленные, второе на сервер не уходило,
    /// ответ на прерванный запрос не применён; память и индекс пусты.
    func test_willLogout_marksQueueFailedAndKeepsIt() async {
        let sut = await makeActiveSUT()
        let gate = Gate()
        messageService.stubbedSentMessage = .success(.make(id: 1, clientId: "c1"))
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Первое", conversationId: 1)
        sut.enqueue(text: "Второе", conversationId: 1)
        await yieldUntil { gate.isWaiting }
        var isLogoutFinished = false

        let logout = Task {
            await sut.authServiceWillLogout()
            isLogoutFinished = true
        }
        await Task.yield()
        XCTAssertFalse(isLogoutFinished)
        gate.open()
        await logout.value

        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1"])
        XCTAssertEqual(outgoingStorage.messages["c1"]?.status, .failed)
        XCTAssertEqual(outgoingStorage.messages["c2"]?.status, .failed)
        XCTAssertTrue(messageCache.sentMessages.isEmpty)
        XCTAssertTrue(sut.outgoingMessages.isEmpty)
        XCTAssertNil(sut.lastFailedText(for: 1))
    }

    /// Кейс: в очереди три сообщения, первое отправляется; пользователь выходит из аккаунта.
    /// Ожидание: статусы «не отправлено» всех трёх записаны в БД одной записью, а не тремя.
    func test_willLogout_storesFailedStatusesInOneWrite() async {
        let sut = await makeActiveSUT()
        let gate = Gate()
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Первое", conversationId: 1)
        sut.enqueue(text: "Второе", conversationId: 1)
        sut.enqueue(text: "Третье", conversationId: 2)
        await yieldUntil { gate.isWaiting }

        let logout = Task { await sut.authServiceWillLogout() }
        await Task.yield()
        gate.open()
        await logout.value

        let lastBatch = outgoingStorage.savedBatches.last ?? []
        XCTAssertEqual(lastBatch.map(\.clientId), ["c1", "c2", "c3"])
        XCTAssertEqual(lastBatch.map(\.status), [.failed, .failed, .failed])
    }

    /// Кейс: идёт выход (ждёт прерванную отправку); пользователь повторяет и удаляет неотправленное сообщение,
    /// отправляет новое.
    /// Ожидание: ни одно действие не принято — БД и сервер не тронуты.
    func test_actionsDuringLogout_areIgnored() async {
        outgoingStorage.put([.stub(clientId: "failed", createdAt: now.addingTimeInterval(-1), status: .failed)])
        let sut = await makeActiveSUT()
        let gate = Gate()
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Отправляется", conversationId: 1)
        await yieldUntil { gate.isWaiting }
        var isLogoutStarted = false
        let logout = Task {
            isLogoutStarted = true
            await sut.authServiceWillLogout()
        }
        await yieldUntil { isLogoutStarted }

        sut.retry(clientId: "failed")
        sut.delete(clientId: "failed")
        sut.enqueue(text: "Во время выхода", conversationId: 1)
        gate.open()
        await logout.value

        XCTAssertEqual(outgoingStorage.messages["failed"]?.status, .failed)
        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1"])
        XCTAssertEqual(outgoingStorage.messages.count, 2)
    }

    /// Кейс: выход завершён, затем пользователь повторяет и удаляет сообщение и отправляет новое.
    /// Ожидание: до новой загрузки очередь действий не принимает.
    func test_actionsAfterLogout_areIgnoredUntilLoad() async {
        outgoingStorage.put([.stub(clientId: "failed", status: .failed)])
        let sut = await makeActiveSUT()
        await sut.authServiceWillLogout()

        sut.retry(clientId: "failed")
        sut.delete(clientId: "failed")
        sut.enqueue(text: "После выхода", conversationId: 1)

        XCTAssertTrue(sut.outgoingMessages.isEmpty)
        XCTAssertEqual(outgoingStorage.messages.map(\.key), ["failed"])
        XCTAssertTrue(messageService.sentRequests.isEmpty)
    }

    /// Кейс: в очереди отправляющееся сообщение; пользователь вышел, затем вошёл другой, затем снова первый.
    /// Ожидание: второй пользователь сообщение первого не видит; первый после входа видит его неотправленным,
    /// а отправка снова ждёт `resumeDeliveries()`.
    func test_logoutThenLoad_returnsMessagesOnlyToSameUser() async {
        let sut = await makeActiveSUT(userId: 1)
        let gate = Gate()
        messageService.onSend = { await gate.wait() }
        sut.enqueue(text: "Привет", conversationId: 7)
        await yieldUntil { gate.isWaiting }
        let logout = Task { await sut.authServiceWillLogout() }
        await Task.yield()
        gate.open()
        await logout.value
        messageService.onSend = nil

        await sut.load(userId: 2)
        let otherUserMessages = sut.outgoingMessages
        await sut.authServiceWillLogout()
        await sut.load(userId: 1)

        XCTAssertTrue(otherUserMessages.isEmpty)
        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["c1"])
        XCTAssertEqual(sut.outgoingMessages.map(\.status), [.failed])
        XCTAssertEqual(sut.lastFailedText(for: 7), "Привет")
    }

    /// Кейс: после выхода в БД осталась запись в статусе «отправляется» (удаление копии после подтверждения
    /// не удалось); пользователь снова вошёл.
    /// Ожидание: запись отправлена повторно с тем же `clientId` — после `resumeDeliveries()`, не раньше.
    func test_logout_confirmedButCopyNotDeleted_resendsAfterLoad() async {
        let sut = await makeActiveSUT()
        messageCache.stubbedApplySentResult = .discarded
        outgoingStorage.stubbedDeleteError = CocoaError(.fileWriteUnknown)
        messageService.stubbedSentMessage = .success(.make(id: 1, clientId: "c1"))
        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { sut.outgoingMessages.isEmpty }
        await sut.authServiceWillLogout()
        outgoingStorage.stubbedDeleteError = nil

        await sut.load(userId: 1)
        await Task.yield()
        let requestsBeforeResume = messageService.sentRequests.count
        sut.resumeDeliveries()

        await yieldUntil { [unowned self] in messageService.sentRequests.count == 2 }
        XCTAssertEqual(requestsBeforeResume, 1)
        XCTAssertEqual(messageService.sentRequests.map(\.clientId), ["c1", "c1"])
    }

    /// Кейс: кэш сообщений уже в выходе, когда приходит подтверждение; удаление копии удаётся; пользователь
    /// снова входит.
    /// Ожидание: подтверждённое сообщение в очередь не возвращается.
    func test_logout_cacheStoppedFirst_confirmedMessageDoesNotReturn() async {
        let sut = await makeActiveSUT()
        messageCache.stubbedApplySentResult = .discarded
        messageService.stubbedSentMessage = .success(.make(id: 1, clientId: "c1"))
        sut.enqueue(text: "Привет", conversationId: 1)
        await yieldUntil { sut.outgoingMessages.isEmpty }

        await sut.authServiceWillLogout()
        await sut.load(userId: 1)

        XCTAssertTrue(sut.outgoingMessages.isEmpty)
    }


    // MARK: - Удаление переписки

    /// Кейс: в очереди неотправленные сообщения групп 7 и 8; пользователя удалили из группы 7.
    /// Ожидание: сообщения группы 7 удалены из очереди и БД; сообщение группы 8 осталось.
    func test_conversationWasRemoved_dropsOnlyItsMessages() async {
        outgoingStorage.put([
            .stub(clientId: "a", conversationId: 7, status: .failed),
            .stub(clientId: "b", conversationId: 8, status: .failed),
        ])
        let sut = await makeActiveSUT()

        await sut.conversationWasRemoved(RemovedConversationInfo(conversationId: 7, name: nil, type: .group, reason: .removed, changeVersion: 1))

        XCTAssertEqual(sut.outgoingMessages.map(\.clientId), ["b"])
        await yieldUntil { [unowned self] in outgoingStorage.messages["a"] == nil }
        XCTAssertNotNil(outgoingStorage.messages["b"])
    }

    // MARK: - Helpers

    private let now = Date(timeIntervalSince1970: 1_790_846_400)

    /// Создаёт очередь над моками этого теста, загружает очередь пользователя и запускает отправку — как после
    /// открытия сессии и старта приложения.
    /// - Parameter userId: пользователь открытой сессии.
    private func makeActiveSUT(userId: Int = 1) async -> MessageSendQueue {
        let sut = makeSUT()
        await sut.load(userId: userId)
        sut.resumeDeliveries()
        return sut
    }

    /// Создаёт очередь над моками этого теста; `clientId` — `c1`, `c2`, ... по порядку.
    private func makeSUT() -> MessageSendQueue {
        var counter = 0
        return MessageSendQueue(
            messageService: messageService,
            messageCache: messageCache,
            outgoingMessageStorage: outgoingStorage,
            eventQueue: eventQueue,
            positionUpdater: positionUpdater,
            membership: membership,
            now: { [now] in now },
            makeClientId: {
                counter += 1
                return "c\(counter)"
            }
        )
    }
}

/// Признак, поднятый из `@Sendable`-замыкания `withObservationTracking`.
private final class ObservationFlag: @unchecked Sendable {
    var isSet = false
}
