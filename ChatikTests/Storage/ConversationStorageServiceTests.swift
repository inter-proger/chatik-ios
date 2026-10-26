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

    /// Кейс: сохранены личная переписка (с id собеседника, без сообщений) и групповая (с названием, аватаром
    /// и последним сообщением).
    /// Ожидание: обе читаются из БД без потерь, включая `lastMessage` и время в миллисекундах; аватар попал
    /// в хранилище файлов, а пользователей переписка не создаёт — они живут в кэше пользователей.
    func test_save_roundTripsAndStoresAvatar() async throws {
        try await sut.save(conversations: [.singleStub, .groupStub], state: ConversationListState())

        let groupFound = try await sut.find(byId: Conversation.groupStub.id)
        let singleFound = try await sut.find(byId: Conversation.singleStub.id)
        let users = try await UserStorageService(container: container).fetchAll()
        let files = try await FileStorageService(container: container).fetchAll()
        XCTAssertEqual(groupFound, .groupStub)
        XCTAssertEqual(singleFound, .singleStub)
        XCTAssertTrue(users.isEmpty)
        XCTAssertEqual(files, [.stub])
    }

    /// Кейс: переписка с непрочитанными сохранена и прочитана обратно.
    /// Ожидание: поля прочтения на месте.
    func test_save_readState_roundTrips() async throws {
        let conversation = Conversation.make(id: 3, readState: .make(unread: 4, lastRead: 15, version: 120))

        try await sut.save(conversations: [conversation], state: ConversationListState())

        let found = try await sut.find(byId: 3)
        XCTAssertEqual(found?.readState, .make(unread: 4, lastRead: 15, version: 120))
    }

    /// Кейс: последнее сообщение неизвестного типа без текста.
    /// Ожидание: читается из БД как есть — тип `.unknown`, текст `nil`.
    func test_save_lastMessageWithoutText_roundTrips() async throws {
        let conversation = Conversation.make(id: 1).with(position: .stub, lastMessage: LastMessage(messageId: 3, senderId: 1, type: .unknown, text: nil, updatedAt: .stub(7)))

        try await sut.save(conversations: [conversation], state: ConversationListState())

        let found = try await sut.find(byId: 1)
        XCTAssertEqual(found, conversation)
    }

    /// Кейс: состояние синхронизации записано, затем перезаписано.
    /// Ожидание: читается последнее состояние; запись одна.
    func test_save_state_roundTripsAndOverwrites() async throws {
        let first = ConversationListState(isLoaded: true, hasMorePages: true, positionWatermark: .stub, positionWatermarkCeiling: nil, syncedChangeVersion: 7, totalUnreadCount: 3, totalUnreadVersion: 7)
        let second = ConversationListState(isLoaded: true, hasMorePages: false, positionWatermark: .stub(10), positionWatermarkCeiling: .stub(3), syncedChangeVersion: nil)
        try await sut.save(conversations: [], state: first)

        try await sut.save(conversations: [], state: second)

        let stored = try await sut.fetchList()
        let records = try await container.performRead { context in
            try context.count(for: ConversationListStateEntity.makeFetchRequest())
        }
        XCTAssertEqual(stored.state, second)
        XCTAssertEqual(records, 1)
    }

    /// Кейс: состояние с метками удаления и ожидающими группами записано и прочитано.
    /// Ожидание: оба словаря восстановлены без потерь.
    func test_save_state_roundTripsRemovedAndPending() async throws {
        var state = ConversationListState(isLoaded: true, syncedChangeVersion: 7)
        state.removedVersions = [12: 131, 3: 9]
        state.pendingConversations = [20: 74]

        try await sut.save(state: state)

        let stored = try await sut.fetchList()
        XCTAssertEqual(stored.state, state)
    }

    /// Кейс: группа и личная переписка в БД; группа удаляется вместе с записью нового состояния.
    /// Ожидание: остаётся личная переписка; состояние записано.
    func test_delete_removesConversationAndStoresState() async throws {
        try await sut.save(conversations: [Conversation.make(id: 1), Conversation.make(id: 2)], state: ConversationListState())
        var state = ConversationListState()
        state.removedVersions = [2: 10]

        try await sut.delete(conversationId: 2, state: state)

        let stored = try await sut.fetchList()
        XCTAssertEqual(stored.conversations.map(\.id), [1])
        XCTAssertEqual(stored.state.removedVersions, [2: 10])
    }

    /// Кейс: группа (`memberIds == nil`) с описанием и отправителем последнего сообщения сохранена и прочитана.
    /// Ожидание: переписка восстановлена без изменений.
    func test_save_groupWithoutMembers_roundTrips() async throws {
        let conversation = Conversation.groupStub

        try await sut.save(conversations: [conversation], state: nil)

        let found = try await sut.find(byId: conversation.id)
        XCTAssertEqual(found, conversation)
    }

    /// Кейс: в БД нет записи состояния синхронизации (первый запуск).
    /// Ожидание: возвращается состояние по умолчанию — список не загружен, водяных знаков нет.
    func test_fetchList_withoutState_returnsDefaultState() async throws {
        let stored = try await sut.fetchList()

        XCTAssertEqual(stored.state, ConversationListState())
        XCTAssertTrue(stored.conversations.isEmpty)
    }

    /// Кейс: в БД записано состояние синхронизации; затем переписка сохранена без состояния (`state: nil`).
    /// Ожидание: переписка записана, сохранённое состояние не изменилось.
    func test_save_nilState_keepsStoredState() async throws {
        let state = ConversationListState(isLoaded: true, hasMorePages: true, positionWatermark: .stub, positionWatermarkCeiling: nil, syncedChangeVersion: 7)
        try await sut.save(conversations: [], state: state)

        try await sut.save(conversations: [Conversation.make(id: 1)], state: nil)

        let stored = try await sut.fetchList()
        XCTAssertEqual(stored.conversations.map(\.id), [1])
        XCTAssertEqual(stored.state, state)
    }

    /// Кейс: в БД переписка с более поздней позицией и более новой информацией, затем сохраняется более старая
    /// версия обоих (страница, собранная раньше события).
    /// Ожидание: правила слияния не дают откатить ни позицию, ни информацию.
    func test_save_olderVersion_keepsNewerPositionAndInfo() async throws {
        let newer = Conversation.make(id: 1)
            .with(name: "Новое", updatedInfoAt: .stub(5000))
            .with(position: .stub(5000), lastMessage: .make(id: 16, updatedAt: .stub(5000)))
        try await sut.save(conversations: [newer], state: ConversationListState())

        try await sut.save(conversations: [Conversation.make(id: 1)], state: ConversationListState())

        let found = try await sut.find(byId: 1)
        XCTAssertEqual(found, newer)
    }

    /// Кейс: в БД группа с аватаром и более новой информацией; сохраняется версия с более поздней позицией,
    /// но старой информацией без аватара.
    /// Ожидание: позиция взята, а аватар остался связан с перепиской — он из сохранённой версии.
    func test_save_newerPositionOlderInfo_keepsStoredAvatar() async throws {
        let stored = Conversation.groupStub.with(name: "Команда", updatedInfoAt: .stub(9000))
        try await sut.save(conversations: [stored], state: ConversationListState())
        let incoming = Conversation(
            conversationId: stored.conversationId, type: .group, memberIds: stored.memberIds, name: "Старое", avatar: nil,
            opponentUserId: nil, lastMessage: .make(id: 99, updatedAt: .stub(9999)), positionUpdatedAt: .stub(9999), updatedInfoAt: .stub,
            readState: .stub
        )

        try await sut.save(conversations: [incoming], state: ConversationListState())

        let found = try await sut.find(byId: stored.conversationId)
        XCTAssertEqual(found?.avatar, .stub)
        XCTAssertEqual(found?.name, "Команда")
        XCTAssertEqual(found?.positionUpdatedAt, .stub(9999))
    }

    /// Кейс: личная переписка пересохранена группой с более новой информацией — у неё больше нет собеседника.
    /// Ожидание: `opponentUserId` в БД обнулён, а не остался от прежней версии.
    func test_save_opponentRemoved_clearsOpponentId() async throws {
        let single = Conversation(
            conversationId: 1, type: .single, memberIds: [1, 5], name: nil, avatar: nil, opponentUserId: 5,
            lastMessage: nil, positionUpdatedAt: .stub, updatedInfoAt: .stub, readState: .stub
        )
        try await sut.save(conversations: [single], state: ConversationListState())

        try await sut.save(conversations: [Conversation.make(id: 1, updatedInfoAt: .stub(1))], state: ConversationListState())

        let found = try await sut.find(byId: 1)
        XCTAssertNil(found?.opponentUserId)
    }

    // MARK: - Порядок списка

    /// Кейс: переписки с разными позициями и две с одинаковой позицией сохранены вразнобой.
    /// Ожидание: выборка отдаёт их по убыванию позиции, при равенстве — по убыванию `conversationId`.
    func test_fetchList_sortedByPositionThenId() async throws {
        let conversations = [
            Conversation.make(id: 1, position: .stub(300)),
            Conversation.make(id: 2, position: .stub(100)),
            Conversation.make(id: 3, position: .stub(200)),
            Conversation.make(id: 4, position: .stub(100)),
        ]
        try await sut.save(conversations: conversations, state: ConversationListState())

        let stored = try await sut.fetchList()

        XCTAssertEqual(stored.conversations.map(\.id), [1, 3, 4, 2])
    }

    /// Кейс: в БД есть переписка без обязательного поля `type` и переписка с битым последним сообщением
    /// (есть `lastMessageId`, нет `lastMessageType`).
    /// Ожидание: выборка их пропускает, остальные записи возвращаются.
    func test_fetchList_skipsBrokenRecords() async throws {
        try await sut.save(conversations: [.groupStub], state: ConversationListState())
        try await container.performWrite { context in
            let withoutType = ConversationEntity(context: context)
            withoutType.conversationId = 100
            withoutType.memberIds = try JSONEncoder().encode([1, 2])
            let brokenLast = ConversationEntity(context: context)
            brokenLast.conversationId = 101
            brokenLast.type = ConversationType.group.rawValue
            brokenLast.memberIds = try JSONEncoder().encode([1, 2])
            brokenLast.lastMessageId = 5
            try context.save()
        }

        let stored = try await sut.fetchList()

        XCTAssertEqual(stored.conversations.map(\.id), [Conversation.groupStub.id])
    }

    // MARK: - Замена списка

    /// Кейс: в БД переписки 1…5; список заменён переписками [5, 3] с новым состоянием.
    /// Ожидание: остались только 5 и 3, состояние записано; аватары удалённых переписок остались в файлах.
    func test_replaceList_removesMissingAndStoresState() async throws {
        try await sut.save(conversations: (1...5).map { Conversation.make(id: $0) } + [.groupStub], state: ConversationListState())
        let state = ConversationListState(isLoaded: true, hasMorePages: true, positionWatermark: .stub, positionWatermarkCeiling: nil, syncedChangeVersion: 7)

        try await sut.replaceList(with: [Conversation.make(id: 5), Conversation.make(id: 3)], state: state)

        let stored = try await sut.fetchList()
        let files = try await FileStorageService(container: container).fetchAll()
        XCTAssertEqual(Set(stored.conversations.map(\.id)), [5, 3])
        XCTAssertEqual(stored.state, state)
        XCTAssertEqual(files, [.stub])
    }

    /// Кейс: в БД переписка с последним сообщением; список заменён версией сервера, где последнее сообщение
    /// удалено (`lastMessage: nil`), позиция ушла назад, а информация старше сохранённой.
    /// Ожидание: записана ровно версия сервера — без слияния с сохранённой, как и в списке в памяти.
    func test_replaceList_overwritesWithoutMerging() async throws {
        let stored = Conversation.make(id: 1)
            .with(name: "Старое", updatedInfoAt: .stub(500))
            .with(position: .stub(100), lastMessage: .make(id: 9, updatedAt: .stub(100)))
        try await sut.save(conversations: [stored], state: ConversationListState())
        let server = Conversation.make(id: 1, updatedInfoAt: .stub(10)).with(position: .stub(50), lastMessage: nil)

        try await sut.replaceList(with: [server], state: ConversationListState(isLoaded: true))

        let found = try await sut.find(byId: 1)
        XCTAssertEqual(found, server)
    }

    /// Кейс: в БД группа с аватаром; список заменён её версией без аватара.
    /// Ожидание: аватар отвязан от переписки — замена не подставляет сохранённый.
    func test_replaceList_avatarRemoved_clearsAvatar() async throws {
        try await sut.save(conversations: [.groupStub], state: ConversationListState())
        let server = Conversation(
            conversationId: Conversation.groupStub.conversationId, type: .group, memberIds: Conversation.groupStub.memberIds,
            name: Conversation.groupStub.name, avatar: nil, opponentUserId: nil, lastMessage: Conversation.groupStub.lastMessage,
            positionUpdatedAt: Conversation.groupStub.positionUpdatedAt, updatedInfoAt: Conversation.groupStub.updatedInfoAt,
            readState: Conversation.groupStub.readState
        )

        try await sut.replaceList(with: [server], state: ConversationListState(isLoaded: true))

        let found = try await sut.find(byId: server.conversationId)
        XCTAssertNil(found?.avatar)
    }

    /// Кейс: список заменён пустым.
    /// Ожидание: в БД не осталось переписок.
    func test_replaceList_empty_removesAll() async throws {
        try await sut.save(conversations: [.singleStub, .groupStub], state: ConversationListState())

        try await sut.replaceList(with: [], state: ConversationListState(isLoaded: true))

        let stored = try await sut.fetchList()
        XCTAssertTrue(stored.conversations.isEmpty)
        XCTAssertTrue(stored.state.isLoaded)
    }

    /// Кейс: `find` по `conversationId`, которого нет в БД.
    /// Ожидание: `nil`, без ошибки.
    func test_find_missingId_returnsNil() async throws {
        try await sut.save(conversations: [.groupStub], state: ConversationListState())

        let found = try await sut.find(byId: 999)

        XCTAssertNil(found)
    }
}
