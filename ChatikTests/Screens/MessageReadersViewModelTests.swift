//
//  MessageReadersViewModelTests.swift
//  ChatikTests
//

import os
import XCTest
@testable import Chatik

@MainActor
final class MessageReadersViewModelTests: XCTestCase {
    private var memberReads: MemberReadServiceMock!
    private var userCache: UserCacheServiceMock!
    private var sessionService: SessionService!

    override func setUp() async throws {
        try await super.setUp()
        memberReads = MemberReadServiceMock()
        userCache = UserCacheServiceMock()
        sessionService = SessionService(
            userDefaultsService: UserDefaultsServiceMock(currentUser: User(userId: 1, login: "ivan", name: "Ivan", avatar: nil)),
            localStorageCleaner: LocalStorageCleanerMock()
        )
        await sessionService.restore()
    }

    /// Кейс: сообщение 10 автора 2; указатели: автор — 12, участник 3 — ровно 10, участник 4 — 9, текущий
    /// пользователь в мете (на всякий случай) — 20.
    /// Ожидание: прочитал только 3 — автор, текущий пользователь и не дочитавший исключены; заголовок «Прочитано: 1».
    func test_content_filtersByPointerExcludingAuthorAndCurrentUser() {
        memberReads.stubbedPointers = [7: [1: 20, 2: 12, 3: 10, 4: 9]]
        let sut = makeSUT(messageId: 10, senderId: 2)

        let content = sut.content

        XCTAssertEqual(content.readers.map(\.id), [3])
        XCTAssertEqual(content.title, MessageReadersStrings.title(count: 1))
        XCTAssertNil(content.placeholder)
    }

    /// Кейс: указатели есть, но сообщение никто не дочитал.
    /// Ожидание: заглушка «никто не прочитал», заголовок «Прочитано: 0».
    func test_content_nobodyRead_isEmpty() {
        memberReads.stubbedPointers = [7: [3: 9]]
        let sut = makeSUT(messageId: 10, senderId: 1)

        let content = sut.content

        XCTAssertEqual(content.placeholder, .empty)
        XCTAssertEqual(content.title, MessageReadersStrings.title(count: 0))
    }

    /// Кейс: указателей ещё нет, запрос не завершился ошибкой.
    /// Ожидание: загрузка, заголовок без числа — не «никто не прочитал».
    func test_content_withoutMeta_isLoading() {
        let sut = makeSUT(messageId: 10, senderId: 2)

        let content = sut.content

        XCTAssertEqual(content.placeholder, .loading)
        XCTAssertEqual(content.title, MessageReadersStrings.titleUnknown)
        XCTAssertTrue(content.readers.isEmpty)
    }

    /// Кейс: указателей нет, запрос не удался.
    /// Ожидание: ошибка загрузки, заголовок без числа.
    func test_content_withoutMetaAfterFailedRefresh_isFailed() {
        memberReads.failedRefreshIds = [7]
        let sut = makeSUT(messageId: 10, senderId: 2)

        let content = sut.content

        XCTAssertEqual(content.placeholder, .failed)
        XCTAssertEqual(content.title, MessageReadersStrings.titleUnknown)
    }

    /// Кейс: указатели есть (из БД), а запрос не удался.
    /// Ожидание: показывается список по известным указателям, а не ошибка.
    func test_content_storedMetaAfterFailedRefresh_showsReaders() {
        memberReads.stubbedPointers = [7: [3: 10]]
        memberReads.failedRefreshIds = [7]
        let sut = makeSUT(messageId: 10, senderId: 1)

        let content = sut.content

        XCTAssertEqual(content.readers.map(\.id), [3])
        XCTAssertNil(content.placeholder)
    }

    /// Кейс: прочитали «Пётр», два участника «Анна» и ещё не загруженный участник.
    /// Ожидание: загруженные — по имени (равные имена — по id), заглушка — последней.
    func test_content_sortedByNameWithPlaceholdersLast() {
        memberReads.stubbedPointers = [7: [3: 10, 4: 10, 5: 10, 6: 10]]
        userCache.users = [
            3: .loaded(User(userId: 3, login: "petr", name: "Пётр", avatar: nil)),
            4: .loaded(User(userId: 4, login: "anna", name: "Анна", avatar: nil)),
            5: .loaded(User(userId: 5, login: "anna2", name: "Анна", avatar: nil)),
        ]
        let sut = makeSUT(messageId: 10, senderId: 1)

        let readers = sut.content.readers

        XCTAssertEqual(readers.map(\.id), [4, 5, 3, 6])
        XCTAssertEqual(readers.last?.isPlaceholder, true)
    }

    /// Кейс: удалённый участник прочитал сообщение.
    /// Ожидание: в строке текст об удалённом пользователе, как у отправителей в ленте.
    func test_content_deletedUser_showsDeletedText() {
        memberReads.stubbedPointers = [7: [3: 10]]
        userCache.users = [3: .notFound]
        let sut = makeSUT(messageId: 10, senderId: 1)

        XCTAssertEqual(sut.content.readers, [MessageReaderDisplayModel(id: 3, name: ChatStrings.userDeleted, isPlaceholder: false, avatarURL: nil)])
    }

    /// Кейс: лист открыт; пришло событие — прочитал ещё один участник.
    /// Ожидание: список и заголовок обновились — лист наблюдает указатели.
    func test_content_followsPointerChanges() {
        memberReads.stubbedPointers = [7: [3: 10]]
        let sut = makeSUT(messageId: 10, senderId: 1)
        let didChange = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = sut.content } onChange: { didChange.withLock { $0 = true } }

        memberReads.stubbedPointers = [7: [3: 10, 4: 11]]

        XCTAssertTrue(didChange.withLock { $0 })
        XCTAssertEqual(sut.content.readers.map(\.id), [3, 4])
        XCTAssertEqual(sut.content.title, MessageReadersStrings.title(count: 2))
    }

    /// Кейс: лист открыт.
    /// Ожидание: указатели переписки запрошены заново.
    func test_didAppear_refreshesPointers() {
        let sut = makeSUT(messageId: 10, senderId: 1)

        sut.didAppear()

        XCTAssertEqual(memberReads.refreshIds, [7])
    }

    /// Кейс: прочитали загруженный и незагруженный участники; дозагрузка вызвана дважды, пока загрузка идёт.
    /// Ожидание: загружается только незагруженный и только один раз.
    func test_loadMissingUsers_requestsPendingOnce() async {
        memberReads.stubbedPointers = [7: [3: 10, 4: 10]]
        userCache.users = [3: .loaded(User(userId: 3, login: "petr", name: "Пётр", avatar: nil))]
        let gate = Gate()
        userCache.onLoad = { await gate.wait() }
        let sut = makeSUT(messageId: 10, senderId: 1)

        sut.loadMissingUsers()
        await yieldUntil { gate.isWaiting }
        sut.loadMissingUsers()

        XCTAssertEqual(userCache.loadRequests, [[4]])
        gate.open()
    }

    /// Кейс: загрузка участника завершилась, а он так и остался незагруженным (сбой сети); дозагрузка вызвана снова.
    /// Ожидание: участник запрошен повторно — заглушка не остаётся навсегда.
    func test_loadMissingUsers_afterFailedLoad_requestsAgain() async {
        memberReads.stubbedPointers = [7: [4: 10]]
        let sut = makeSUT(messageId: 10, senderId: 1)
        sut.loadMissingUsers()
        await yieldUntil { [unowned self] in userCache.loadRequests.count == 1 }
        await yieldTimes()

        sut.loadMissingUsers()

        await yieldUntil { [unowned self] in userCache.loadRequests.count == 2 }
        XCTAssertEqual(userCache.loadRequests, [[4], [4]])
    }

    /// Кейс: участник загрузился; дозагрузка вызвана снова.
    /// Ожидание: повторного запроса нет.
    func test_loadMissingUsers_afterSuccessfulLoad_doesNotRequestAgain() async {
        memberReads.stubbedPointers = [7: [4: 10]]
        userCache.onLoad = { [unowned self] in
            userCache.users[4] = .loaded(User(userId: 4, login: "anna", name: "Анна", avatar: nil))
        }
        let sut = makeSUT(messageId: 10, senderId: 1)
        sut.loadMissingUsers()
        await yieldUntil { [unowned self] in userCache.loadRequests.count == 1 }
        await yieldTimes()

        sut.loadMissingUsers()

        await yieldTimes()
        XCTAssertEqual(userCache.loadRequests, [[4]])
    }


    /// Кейс: группа, указатели есть, а состав ещё неизвестен.
    /// Ожидание: загрузка вместо списка — без состава прочитавших не определить.
    func test_content_groupWithoutInfo_isLoading() {
        memberReads.stubbedPointers = [7: [3: 10]]
        memberReads.awaitingGroupInfoIds = [7]
        let sut = makeSUT(messageId: 10, senderId: 1)

        XCTAssertEqual(sut.content.placeholder, .loading)
        XCTAssertTrue(sut.content.readers.isEmpty)
    }


    /// Кейс: группа; сообщение 10; участник 3 вступил после сообщения 8 (до 10), участник 4 — после 15 (его указатель
    /// новичка — 20); участника 5 нет в составе.
    /// Ожидание: прочитал только 3 — вступивший после сообщения и не состоящий в группе не считаются.
    func test_content_group_excludesJoinedLaterAndNonMembers() {
        memberReads.stubbedPointers = [7: [3: 10, 4: 20, 5: 30]]
        memberReads.stubbedJoinedAfter = [7: [1: 0, 3: 8, 4: 15]]
        let sut = makeSUT(messageId: 10, senderId: 1)

        XCTAssertEqual(sut.content.readers.map(\.id), [3])
    }

    // MARK: - Helpers

    /// ViewModel листа сообщения переписки 7.
    /// - Parameters:
    ///   - messageId: сообщение.
    ///   - senderId: автор сообщения.
    private func makeSUT(messageId: Int, senderId: Int) -> MessageReadersViewModel {
        MessageReadersViewModel(
            request: MessageReadersRequest(conversationId: 7, messageId: messageId, senderId: senderId),
            memberReads: memberReads,
            sessionService: sessionService,
            userCache: userCache
        )
    }
}
