//
//  ChatListRouterTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class ChatListRouterTests: XCTestCase {
    /// Кейс: открытие переписки из уведомления с разных экранов — список, профиль, другая переписка.
    /// Ожидание: стек заменён одной перепиской — назад ведёт к списку.
    func test_openConversation_replacesStack() {
        let stacks: [[ChatListRoute]] = [
            [],
            [.profile],
            [.conversation(.groupStub)],
        ]

        for stack in stacks {
            let sut = ChatListRouter()
            sut.path = stack

            sut.openConversation(.singleStub)

            XCTAssertEqual(sut.path, [.conversation(.singleStub)], "\(stack)")
        }
    }

    /// Кейс: открыт лист создания переписки; открытие переписки из уведомления.
    /// Ожидание: лист закрыт, переписка открыта.
    func test_openConversation_dismissesSheet() {
        let sut = ChatListRouter()
        sut.showCreateSingleConversation()

        sut.openConversation(.singleStub)

        XCTAssertNil(sut.presentedSheet)
        XCTAssertEqual(sut.openedConversationId, Conversation.singleStub.id)
    }

    /// Кейс: эта переписка уже открыта; открытие её из уведомления.
    /// Ожидание: стек не меняется — экран не пересоздаётся.
    func test_openConversation_alreadyOpen_keepsStack() {
        let sut = ChatListRouter()
        let opened = Conversation.singleStub.with(position: .stub(1000), lastMessage: nil)
        sut.path = [.conversation(opened)]

        sut.openConversation(.singleStub)

        XCTAssertEqual(sut.path, [.conversation(opened)])
    }
}
