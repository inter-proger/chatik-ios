//
//  ConversationStorageServiceTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

final class ConversationStorageServiceTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var sut: ConversationStorageService!

    override func setUp() {
        super.setUp()
        container = CoreDataStack.makeContainer(inMemory: true)
        sut = ConversationStorageService(container: container)
    }

    override func tearDown() {
        sut = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Сохранение

    /// Кейс: сохранены личная переписка (с собеседником) и групповая (с названием и аватаром).
    /// Ожидание: обе читаются из БД без потерь; собеседник и аватар попали в хранилища пользователей и файлов.
    func test_saveConversations_roundTripsAndStoresNestedData() async throws {
        try await sut.save(conversations: [.singleStub, .groupStub])

        let groupFound = try await sut.find(byId: Conversation.groupStub.id)
        let singleFound = try await sut.find(byId: Conversation.singleStub.id)
        let users = try await UserStorageService(container: container).fetchAll()
        let files = try await FileStorageService(container: container).fetchAll()
        XCTAssertEqual(groupFound, .groupStub)
        XCTAssertEqual(singleFound, .singleStub)
        XCTAssertEqual(users, [try XCTUnwrap(Conversation.singleStub.opponentUser)])
        XCTAssertEqual(files, [.stub])
    }

    /// Кейс: переписка сохранена, затем сохранена повторно с тем же `conversationId` и новым названием.
    /// Ожидание: в БД одна запись с обновлённым названием.
    func test_save_existingId_updatesRecord() async throws {
        try await sut.save(conversation: .groupStub)

        try await sut.save(conversation: makeGroup(id: Conversation.groupStub.id, name: "Новое название"))

        let conversations = try await sut.fetchAll()
        XCTAssertEqual(conversations.map(\.name), ["Новое название"])
    }

    /// Кейс: две переписки с одним и тем же собеседником.
    /// Ожидание: собеседник сохранён одной записью.
    func test_saveConversations_sharedOpponent_storedOnce() async throws {
        let opponent = User(userId: 5, login: "anna", name: "Anna", avatar: nil)

        try await sut.save(conversations: [makeSingle(id: 1, opponent: opponent), makeSingle(id: 2, opponent: opponent)])

        let users = try await UserStorageService(container: container).fetchAll()
        XCTAssertEqual(users, [opponent])
    }

    /// Кейс: переписки сохранены вразнобой.
    /// Ожидание: выборка отдаёт их по убыванию `conversationId` — как сервер.
    func test_fetchAll_sortedByIdDescending() async throws {
        try await sut.save(conversations: [makeGroup(id: 2), makeGroup(id: 3), makeGroup(id: 1)])

        let conversations = try await sut.fetchAll()

        XCTAssertEqual(conversations.map(\.id), [3, 2, 1])
    }

    /// Кейс: в БД пять переписок, запрошены три самые новые.
    /// Ожидание: возвращены три переписки с наибольшими `conversationId`, по убыванию.
    func test_fetchLatest_returnsNewestWithinLimit() async throws {
        try await sut.save(conversations: (1...5).map { makeGroup(id: $0) })

        let conversations = try await sut.fetchLatest(limit: 3)

        XCTAssertEqual(conversations.map(\.id), [5, 4, 3])
    }

    /// Кейс: в БД есть переписка без обязательного поля `type`.
    /// Ожидание: выборка её пропускает, остальные записи возвращаются.
    func test_fetchAll_skipsBrokenRecords() async throws {
        try await sut.save(conversation: .groupStub)
        try await container.performWrite { context in
            let broken = ConversationEntity(context: context)
            broken.conversationId = 100
            broken.memberIds = try JSONEncoder().encode([1, 2])
            try context.save()
        }

        let conversations = try await sut.fetchAll()

        XCTAssertEqual(conversations.map(\.id), [Conversation.groupStub.id])
    }

    /// Кейс: `find` и `delete` по `conversationId`, которого нет в БД.
    /// Ожидание: не падают; `find` возвращает `nil`, остальные записи не тронуты.
    func test_findAndDelete_missingId_doNothing() async throws {
        try await sut.save(conversation: .groupStub)

        let found = try await sut.find(byId: 999)
        try await sut.delete(byId: 999)

        let conversations = try await sut.fetchAll()
        XCTAssertNil(found)
        XCTAssertEqual(conversations, [.groupStub])
    }

    /// Кейс: личная переписка удалена по `conversationId`.
    /// Ожидание: переписки нет в БД, собеседник остался в хранилище пользователей.
    func test_delete_keepsOpponent() async throws {
        try await sut.save(conversation: .singleStub)

        try await sut.delete(byId: Conversation.singleStub.id)

        let found = try await sut.find(byId: Conversation.singleStub.id)
        let users = try await UserStorageService(container: container).fetchAll()
        XCTAssertNil(found)
        XCTAssertEqual(users.count, 1)
    }

    // MARK: - Страницы

    /// Кейс: в БД переписки 1…5; первая страница с сервера — [5, 3], `hasNext: true`.
    /// Ожидание: удалена только переписка 4 — она в покрытом страницей диапазоне, но её нет на сервере;
    /// переписки ниже страницы (1, 2) не тронуты.
    func test_savePage_firstPageWithNext_removesMissingWithinRange() async throws {
        try await sut.save(conversations: (1...5).map { makeGroup(id: $0) })
        let page = ConversationsPage(conversations: [makeGroup(id: 5), makeGroup(id: 3)], hasNext: true)

        try await sut.save(page: page, isFirstPage: true)

        let conversations = try await sut.fetchAll()
        XCTAssertEqual(conversations.map(\.id), [5, 3, 2, 1])
    }

    /// Кейс: в БД переписки 1…3; первая страница с сервера — [3], `hasNext: false`.
    /// Ожидание: остальные переписки удалены — страница описывает весь список на сервере.
    func test_savePage_onlyPage_removesAllMissing() async throws {
        try await sut.save(conversations: (1...3).map { makeGroup(id: $0) })

        try await sut.save(page: ConversationsPage(conversations: [makeGroup(id: 3)], hasNext: false), isFirstPage: true)

        let conversations = try await sut.fetchAll()
        XCTAssertEqual(conversations.map(\.id), [3])
    }

    /// Кейс: в БД есть переписки; первая страница с сервера пуста.
    /// Ожидание: БД переписок очищена — на сервере переписок нет.
    func test_savePage_emptyFirstPage_removesAll() async throws {
        try await sut.save(conversations: [.singleStub, .groupStub])

        try await sut.save(page: ConversationsPage(conversations: [], hasNext: false), isFirstPage: true)

        let conversations = try await sut.fetchAll()
        XCTAssertTrue(conversations.isEmpty)
    }

    /// Кейс: в БД переписки 1…10; не первая страница — [8, 6], `hasNext: true`.
    /// Ожидание: удалена только переписка 7 — выше и ниже диапазона страницы ничего не тронуто.
    func test_savePage_nextPage_removesMissingOnlyWithinPage() async throws {
        try await sut.save(conversations: (1...10).map { makeGroup(id: $0) })
        let page = ConversationsPage(conversations: [makeGroup(id: 8), makeGroup(id: 6)], hasNext: true)

        try await sut.save(page: page, isFirstPage: false)

        let conversations = try await sut.fetchAll()
        XCTAssertEqual(conversations.map(\.id), [10, 9, 8, 6, 5, 4, 3, 2, 1])
    }

    /// Кейс: страница с сервера содержит новые данные уже сохранённой переписки.
    /// Ожидание: переписка обновлена, а не удалена и не продублирована.
    func test_savePage_updatesExisting() async throws {
        try await sut.save(conversation: makeGroup(id: 1, name: "Старое"))

        try await sut.save(page: ConversationsPage(conversations: [makeGroup(id: 1, name: "Новое")], hasNext: false), isFirstPage: true)

        let conversations = try await sut.fetchAll()
        XCTAssertEqual(conversations.map(\.name), ["Новое"])
    }

    // MARK: - Helpers

    /// Групповая переписка без аватара.
    /// - Parameters:
    ///   - id: идентификатор переписки.
    ///   - name: название группы.
    private func makeGroup(id: Int, name: String = "Группа") -> Conversation {
        Conversation(conversationId: id, type: .group, memberIds: [1, 2, 3], name: name, avatar: nil, opponentUser: nil)
    }

    /// Личная переписка с указанным собеседником.
    /// - Parameters:
    ///   - id: идентификатор переписки.
    ///   - opponent: собеседник.
    private func makeSingle(id: Int, opponent: User) -> Conversation {
        Conversation(conversationId: id, type: .single, memberIds: [1, opponent.userId], name: nil, avatar: nil, opponentUser: opponent)
    }
}
