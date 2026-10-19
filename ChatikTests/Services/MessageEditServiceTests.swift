//
//  MessageEditServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class MessageEditServiceTests: XCTestCase {
    private var messageService: MessageServiceMock!
    private var messageCache: MessageCacheServiceMock!
    private var positionUpdater: ConversationPositionUpdatingMock!
    private var draftService: MessageDraftServiceMock!
    private var sut: MessageEditService!
    private let edit = MessageEditDraft(messageId: 15, originalText: "Привет!", text: "Привет всем!")
    private let result = MessageEditResult(message: .editedStub, lastMessage: LastMessage(message: .editedStub))

    override func setUp() async throws {
        try await super.setUp()
        messageService = MessageServiceMock()
        messageCache = MessageCacheServiceMock()
        positionUpdater = ConversationPositionUpdatingMock()
        draftService = MessageDraftServiceMock()
        draftService.edits = [1: edit]
        sut = MessageEditService(
            messageService: messageService,
            messageCache: messageCache,
            positionUpdater: positionUpdater,
            draftService: draftService
        )
    }

    override func tearDown() async throws {
        sut = nil
        draftService = nil
        positionUpdater = nil
        messageCache = nil
        messageService = nil
        try await super.tearDown()
    }

    /// Кейс: в переписке включён режим редактирования; правка отправлена, сервер ответил успехом.
    /// Ожидание: запрос ушёл с текстом правки; ответ записан в кэш, затем в список чатов, затем режим выключен —
    /// именно в этом порядке; после запроса переписка больше не отправляется.
    func test_submit_success_appliesResultInOrder() async throws {
        messageService.stubbedEditResults = [.success(result)]
        var journal: [String] = []
        messageCache.onApplyEdited = { [unowned self] in journal.append("cache, endEditing: \(draftService.endEditings.count)") }
        positionUpdater.onApplyEdited = { [unowned self] in journal.append("list, endEditing: \(draftService.endEditings.count)") }

        let task = try XCTUnwrap(sut.submit(conversationId: 1, userId: 3))
        try await task.value

        XCTAssertEqual(messageService.editRequests.map(\.messageId), [15])
        XCTAssertEqual(messageService.editRequests.map(\.newText), ["Привет всем!"])
        XCTAssertEqual(journal, ["cache, endEditing: 0", "list, endEditing: 0"])
        XCTAssertEqual(messageCache.editedMessages, [.editedStub])
        XCTAssertEqual(positionUpdater.editedMessages.map(\.lastMessage), [LastMessage(message: .editedStub)])
        XCTAssertEqual(draftService.endEditings, [.init(messageId: 15, conversationId: 1, userId: 3)])
        XCTAssertFalse(sut.isSubmitting(conversationId: 1))
    }

    /// Кейс: правка отправлена.
    /// Ожидание: переписка помечена отправляющейся сразу, до начала запроса.
    func test_submit_marksSubmittingSynchronously() {
        messageService.stubbedEditResults = [.success(result)]

        sut.submit(conversationId: 1, userId: 3)

        XCTAssertTrue(sut.isSubmitting(conversationId: 1))
        XCTAssertFalse(sut.isSubmitting(conversationId: 2))
    }

    /// Кейс: режим редактирования в переписке выключен; вызвана отправка.
    /// Ожидание: запрос не начат.
    func test_submit_withoutEdit_returnsNil() async {
        let task = sut.submit(conversationId: 2, userId: 3)

        await yieldTimes()
        XCTAssertNil(task)
        XCTAssertTrue(messageService.editRequests.isEmpty)
        XCTAssertFalse(sut.isSubmitting(conversationId: 2))
    }

    /// Кейс: сервер ответил ошибкой.
    /// Ожидание: ошибка проброшена тому, кто начал запрос; ответ нигде не применён, режим не выключен,
    /// переписка больше не отправляется.
    func test_submit_failure_keepsModeAndThrows() async throws {
        messageService.stubbedEditResults = [.failure(NetworkError.api(code: NetworkError.Code.invalidText))]

        let task = try XCTUnwrap(sut.submit(conversationId: 1, userId: 3))
        let outcome = await task.result

        XCTAssertThrowsError(try outcome.get()) { XCTAssertEqual($0 as? NetworkError, .api(code: 1005)) }
        XCTAssertEqual(sut.takeFailure(conversationId: 1) as? NetworkError, .api(code: 1005))
        XCTAssertNil(sut.takeFailure(conversationId: 1))
        XCTAssertTrue(messageCache.editedMessages.isEmpty)
        XCTAssertTrue(positionUpdater.editedMessages.isEmpty)
        XCTAssertTrue(draftService.endEditings.isEmpty)
        XCTAssertFalse(sut.isSubmitting(conversationId: 1))
    }

    /// Кейс: запрос идёт; вызвана повторная отправка, а два ожидающих ждут исхода; сервер отвечает ошибкой.
    /// Ожидание: второго запроса нет, повторная отправка возвращает `nil`; оба ожидающих получают ту же ошибку.
    func test_submit_whileSubmitting_sharesOneRequest() async {
        let gate = Gate()
        messageService.onEdit = { await gate.wait() }
        messageService.stubbedEditResults = [.failure(NetworkError.api(code: NetworkError.Code.messageNotFound))]
        sut.submit(conversationId: 1, userId: 3)
        await yieldUntil { gate.isWaiting }

        let second = sut.submit(conversationId: 1, userId: 3)
        let firstWaiter = Task { try await sut.waitForSubmission(conversationId: 1) }
        let secondWaiter = Task { try await sut.waitForSubmission(conversationId: 1) }
        await yieldTimes()
        gate.open()

        let firstOutcome = await firstWaiter.result
        let secondOutcome = await secondWaiter.result
        XCTAssertNil(second)
        XCTAssertEqual(messageService.editRequests.count, 1)
        XCTAssertThrowsError(try firstOutcome.get()) { XCTAssertEqual($0 as? NetworkError, .api(code: 6001)) }
        XCTAssertThrowsError(try secondOutcome.get()) { XCTAssertEqual($0 as? NetworkError, .api(code: 6001)) }
    }

    /// Кейс: запроса по переписке нет; вызвано ожидание.
    /// Ожидание: ожидание сразу завершается без ошибки.
    func test_waitForSubmission_withoutRequest_returnsImmediately() async throws {
        try await sut.waitForSubmission(conversationId: 1)

        XCTAssertTrue(messageService.editRequests.isEmpty)
    }

    /// Кейс: запрос идёт; задача, которая ждёт его исхода (экран), отменена; сервер отвечает успехом.
    /// Ожидание: запрос не отменён — ответ применён, режим выключен.
    func test_cancelWaiter_doesNotCancelRequest() async {
        let gate = Gate()
        messageService.onEdit = { await gate.wait() }
        messageService.stubbedEditResults = [.success(result)]
        let task = sut.submit(conversationId: 1, userId: 3)
        let waiter = Task { try await sut.waitForSubmission(conversationId: 1) }
        await yieldUntil { gate.isWaiting }

        waiter.cancel()
        gate.open()

        _ = await task?.result
        XCTAssertEqual(messageCache.editedMessages, [.editedStub])
        XCTAssertEqual(draftService.endEditings.count, 1)
    }

    /// Кейс: запрос идёт; начинается выход из аккаунта, после чего сервер отвечает успехом.
    /// Ожидание: запрос отменён (`CancellationError`), ответ не применён, режим не выключен.
    func test_logout_cancelsRequestAndDiscardsResponse() async throws {
        let gate = Gate()
        messageService.onEdit = { await gate.wait() }
        messageService.stubbedEditResults = [.success(result)]
        let task = try XCTUnwrap(sut.submit(conversationId: 1, userId: 3))
        await yieldUntil { gate.isWaiting }

        let logout = Task { await sut.authServiceWillLogout() }
        await yieldTimes()
        gate.open()
        await logout.value

        let outcome = await task.result
        XCTAssertThrowsError(try outcome.get()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertTrue(messageCache.editedMessages.isEmpty)
        XCTAssertTrue(positionUpdater.editedMessages.isEmpty)
        XCTAssertTrue(draftService.endEditings.isEmpty)
        XCTAssertFalse(sut.isSubmitting(conversationId: 1))
        XCTAssertNil(sut.takeFailure(conversationId: 1))
    }

    /// Кейс: запрос в переписке 1 идёт; начинается выход, и пока он ждёт отмены, начата правка в переписке 2;
    /// затем выход завершается.
    /// Ожидание: во время выхода новый запрос не начат; после завершения выхода запросы снова принимаются.
    func test_submitDuringLogout_isRejectedUntilLogoutFinishes() async throws {
        let gate = Gate()
        messageService.onEdit = { await gate.wait() }
        messageService.stubbedEditResults = [.success(result), .success(result)]
        draftService.edits = [1: edit, 2: edit]
        sut.submit(conversationId: 1, userId: 3)
        await yieldUntil { gate.isWaiting }

        let logout = Task { await sut.authServiceWillLogout() }
        await yieldTimes()
        let duringLogout = sut.submit(conversationId: 2, userId: 3)
        gate.open()
        await logout.value
        await sut.authServiceDidLogout(reason: .userInitiated)
        messageService.onEdit = nil
        let afterLogout = sut.submit(conversationId: 2, userId: 3)
        _ = await afterLogout?.result

        XCTAssertNil(duringLogout)
        XCTAssertNotNil(afterLogout)
        XCTAssertEqual(messageService.editRequests.count, 2)
    }

    /// Кейс: запрос упал, ошибку не забрали; затем начат новый запрос той же переписки.
    /// Ожидание: прежняя ошибка отброшена при начале нового запроса.
    func test_submit_clearsPreviousFailure() async throws {
        let gate = Gate()
        messageService.stubbedEditResults = [.failure(NetworkError.api(code: NetworkError.Code.invalidText)), .success(result)]
        _ = await sut.submit(conversationId: 1, userId: 3)?.result
        messageService.onEdit = { await gate.wait() }

        let second = sut.submit(conversationId: 1, userId: 3)

        XCTAssertNil(sut.takeFailure(conversationId: 1))
        await yieldUntil { gate.isWaiting }
        gate.open()
        _ = await second?.result
    }

    /// Кейс: запрос упал, ошибку не забрали; начинается выход из аккаунта.
    /// Ожидание: ошибка закончившейся сессии отброшена.
    func test_logout_dropsUnseenFailures() async {
        messageService.stubbedEditResults = [.failure(NetworkError.api(code: NetworkError.Code.invalidText))]
        _ = await sut.submit(conversationId: 1, userId: 3)?.result

        await sut.authServiceWillLogout()

        XCTAssertNil(sut.takeFailure(conversationId: 1))
    }

    /// Кейс: ответ получен и пишется в кэш; во время записи начинается выход из аккаунта.
    /// Ожидание: после записи в кэш превью списка не меняется и режим не выключается.
    func test_logoutDuringCacheWrite_skipsFollowingSteps() async throws {
        let gate = Gate()
        messageCache.onApplyEdited = { await gate.wait() }
        messageService.stubbedEditResults = [.success(result)]
        let task = try XCTUnwrap(sut.submit(conversationId: 1, userId: 3))
        await yieldUntil { gate.isWaiting }

        let logout = Task { await sut.authServiceWillLogout() }
        await yieldTimes()
        gate.open()
        await logout.value

        let outcome = await task.result
        XCTAssertThrowsError(try outcome.get()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertTrue(positionUpdater.editedMessages.isEmpty)
        XCTAssertTrue(draftService.endEditings.isEmpty)
    }
}
