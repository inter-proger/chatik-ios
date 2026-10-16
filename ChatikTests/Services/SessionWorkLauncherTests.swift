//
//  SessionWorkLauncherTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class SessionWorkLauncherTests: XCTestCase {
    /// Кейс: сессия открыта, начинается работа с сервером.
    /// Ожидание: порядок — список переписок, отправка очереди, соединение: ответ на отправку поднимает переписку
    /// в списке, а очередь событий не хранит события для будущих подписчиков.
    func test_startSessionWork_startsListThenSendQueueThenRealtime() {
        let conversationList = ConversationListServiceMock()
        let messageSendQueue = MessageSendQueueMock()
        let realtimeService = RealtimeServiceMock()
        let sut = SessionWorkLauncher(
            conversationList: conversationList,
            messageDelivery: messageSendQueue,
            realtimeService: realtimeService
        )
        var calls: [String] = []
        conversationList.onStart = { calls.append("list") }
        messageSendQueue.onResume = { calls.append("sendQueue") }
        realtimeService.onStart = { calls.append("realtime") }

        sut.startSessionWork()

        XCTAssertEqual(calls, ["list", "sendQueue", "realtime"])
    }
}
