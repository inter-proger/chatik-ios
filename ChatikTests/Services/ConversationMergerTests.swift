//
//  ConversationMergerTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class ConversationMergerTests: XCTestCase {
    private let local = Conversation.make(id: 7, position: .stub(1000), updatedInfoAt: .stub)
        .with(position: .stub(1000), lastMessage: .make(id: 15, text: "Привет!", updatedAt: .stub(1000)))

    // MARK: - Правило 1: позиция

    /// Кейс: полная версия с более поздней позицией и новым последним сообщением.
    /// Ожидание: взяты `positionUpdatedAt` и `lastMessage`, позиция сменилась.
    func test_full_newerPosition_takesPositionAndLastMessage() throws {
        let incoming = local.with(position: .stub(2000), lastMessage: .make(id: 16, text: "Как дела?", updatedAt: .stub(2000)))

        let result = try XCTUnwrap(ConversationMerger.merge(.full(incoming), into: local))

        XCTAssertEqual(result.conversation.positionUpdatedAt, .stub(2000))
        XCTAssertEqual(result.conversation.lastMessage, .make(id: 16, text: "Как дела?", updatedAt: .stub(2000)))
        XCTAssertTrue(result.isPositionChanged)
    }

    /// Кейс: позиции с одинаковым временем, но у пришедшей больше `messageId`.
    /// Ожидание: пара сравнивается лексикографически — позиция пришедшей больше и берётся.
    func test_samePositionTime_biggerMessageId_wins() throws {
        let patch = ConversationPatch(conversationId: 7, positionUpdatedAt: .stub(1000), lastMessage: .make(id: 16, updatedAt: .stub(1000)))

        let result = try XCTUnwrap(ConversationMerger.merge(.patch(patch), into: local))

        XCTAssertEqual(result.conversation.lastMessage?.messageId, 16)
        XCTAssertTrue(result.isPositionChanged)
    }

    /// Кейс: локальная переписка без сообщений (`lastMessage: null`) и патч с тем же временем позиции.
    /// Ожидание: у локальной `messageId = 0`, поэтому патч с сообщением побеждает.
    func test_localWithoutLastMessage_countsMessageIdAsZero() throws {
        let empty = Conversation.make(id: 7, position: .stub)
        let patch = ConversationPatch(conversationId: 7, positionUpdatedAt: .stub, lastMessage: .make(id: 1))

        let result = try XCTUnwrap(ConversationMerger.merge(.patch(patch), into: empty))

        XCTAssertEqual(result.conversation.lastMessage?.messageId, 1)
    }

    /// Кейс: полная версия с более ранней позицией (страница собрана раньше события).
    /// Ожидание: позиция и превью не откатываются; информация такая же — `nil`, ничего не меняется.
    func test_full_olderPosition_keepsLocal() {
        let incoming = local.with(position: .stub(500), lastMessage: .make(id: 14, updatedAt: .stub(500)))

        XCTAssertNil(ConversationMerger.merge(.full(incoming), into: local))
    }

    // MARK: - Правило 2: текст

    /// Кейс: патч с тем же `messageId`, но более новым `updatedAt` — отредактировано последнее сообщение.
    /// Ожидание: взято новое превью, позиция не сменилась.
    func test_sameMessage_newerText_takesLastMessageWithoutMove() throws {
        let edited = LastMessage.make(id: 15, text: "Привет всем!", updatedAt: .stub(3000))
        let patch = ConversationPatch(conversationId: 7, positionUpdatedAt: .stub(1000), lastMessage: edited)

        let result = try XCTUnwrap(ConversationMerger.merge(.patch(patch), into: local))

        XCTAssertEqual(result.conversation.lastMessage, edited)
        XCTAssertEqual(result.conversation.positionUpdatedAt, .stub(1000))
        XCTAssertFalse(result.isPositionChanged)
    }

    /// Кейс: патч с тем же `messageId` и более старым `updatedAt`.
    /// Ожидание: превью не откатывается.
    func test_sameMessage_olderText_keepsLocal() {
        let local = self.local.with(position: .stub(1000), lastMessage: .make(id: 15, text: "Новое", updatedAt: .stub(5000)))
        let patch = ConversationPatch(conversationId: 7, positionUpdatedAt: .stub(1000), lastMessage: .make(id: 15, text: "Старое", updatedAt: .stub(1000)))

        XCTAssertNil(ConversationMerger.merge(.patch(patch), into: local))
    }

    // MARK: - Правило 3: информация

    /// Кейс: полная версия с более новой информацией и той же позицией.
    /// Ожидание: взяты название и `updatedInfoAt`, позиция не сменилась.
    func test_full_newerInfo_takesInfo() throws {
        let incoming = local.with(name: "Новое название", updatedInfoAt: .stub(9000))

        let result = try XCTUnwrap(ConversationMerger.merge(.full(incoming), into: local))

        XCTAssertEqual(result.conversation.name, "Новое название")
        XCTAssertEqual(result.conversation.updatedInfoAt, .stub(9000))
        XCTAssertFalse(result.isPositionChanged)
    }

    /// Кейс: полная версия с более поздней позицией, но более старой информацией.
    /// Ожидание: версии независимы — позиция взята, информация осталась локальной.
    func test_full_newerPositionOlderInfo_takesOnlyPosition() throws {
        let localWithNewInfo = local.with(name: "Новое", updatedInfoAt: .stub(9000))
        let incoming = local
            .with(name: "Старое", updatedInfoAt: .stub(1))
            .with(position: .stub(2000), lastMessage: .make(id: 16, updatedAt: .stub(2000)))

        let result = try XCTUnwrap(ConversationMerger.merge(.full(incoming), into: localWithNewInfo))

        XCTAssertEqual(result.conversation.name, "Новое")
        XCTAssertEqual(result.conversation.updatedInfoAt, .stub(9000))
        XCTAssertEqual(result.conversation.positionUpdatedAt, .stub(2000))
    }

    /// Кейс: патч поднимает переписку.
    /// Ожидание: патч информацию не меняет — название и `updatedInfoAt` прежние.
    func test_patch_doesNotChangeInfo() throws {
        let patch = ConversationPatch(conversationId: 7, positionUpdatedAt: .stub(2000), lastMessage: .make(id: 16, updatedAt: .stub(2000)))

        let result = try XCTUnwrap(ConversationMerger.merge(.patch(patch), into: local))

        XCTAssertEqual(result.conversation.name, local.name)
        XCTAssertEqual(result.conversation.updatedInfoAt, local.updatedInfoAt)
    }

    // MARK: - Порядок доставки

    /// Кейс: повтор той же версии — полной и патча.
    /// Ожидание: `nil` — ничего не меняется.
    func test_sameVersion_isNoOp() {
        let patch = ConversationPatch(conversationId: 7, positionUpdatedAt: .stub(1000), lastMessage: .make(id: 15, updatedAt: .stub(1000)))

        XCTAssertNil(ConversationMerger.merge(.full(local), into: local))
        XCTAssertNil(ConversationMerger.merge(.patch(patch), into: local))
    }

    /// Кейс: `edited` по старому сообщению M15 пришло после `received` по M16.
    /// Ожидание: позиция M15 меньше, `messageId` не совпадает — превью не откатывается.
    func test_editedOlderMessage_afterReceivedNewer_doesNotRollBack() throws {
        let received = ConversationPatch(conversationId: 7, positionUpdatedAt: .stub(2000), lastMessage: .make(id: 16, text: "M16", updatedAt: .stub(2000)))
        let afterReceived = try XCTUnwrap(ConversationMerger.merge(.patch(received), into: local)).conversation
        let editedM15 = ConversationPatch(conversationId: 7, positionUpdatedAt: .stub(1000), lastMessage: .make(id: 15, text: "M15 правка", updatedAt: .stub(3000)))

        XCTAssertNil(ConversationMerger.merge(.patch(editedM15), into: afterReceived))
    }

    /// Кейс: `edited` по M16 пришло раньше `received` по M16.
    /// Ожидание: переписка сразу поднимается с отредактированным текстом, а позднее `received` ничего не меняет.
    func test_editedBeforeReceived_liftsWithEditedText() throws {
        let edited = ConversationPatch(conversationId: 7, positionUpdatedAt: .stub(2000), lastMessage: .make(id: 16, text: "M16 правка", updatedAt: .stub(3000)))
        let received = ConversationPatch(conversationId: 7, positionUpdatedAt: .stub(2000), lastMessage: .make(id: 16, text: "M16", updatedAt: .stub(2000)))

        let afterEdited = try XCTUnwrap(ConversationMerger.merge(.patch(edited), into: local))

        XCTAssertTrue(afterEdited.isPositionChanged)
        XCTAssertEqual(afterEdited.conversation.lastMessage?.text, "M16 правка")
        XCTAssertNil(ConversationMerger.merge(.patch(received), into: afterEdited.conversation))
    }
}
