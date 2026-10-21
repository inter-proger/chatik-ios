//
//  SessionWorkLauncherTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class SessionWorkLauncherTests: XCTestCase {
    /// Кейс: сессия открыта, начинается работа с сервером.
    /// Ожидание: порядок — список переписок, уведомления о сообщениях, отправка очереди, соединение: уведомления
    /// видят переписку из события в списке, ответ на отправку поднимает переписку в списке, а очередь событий
    /// не хранит события для будущих подписчиков.
    func test_startSessionWork_startsListThenNotificationsThenSendQueueThenRealtime() {
        let conversationList = ConversationListServiceMock()
        let messageNotifications = MessageNotificationServiceMock()
        let messageSendQueue = MessageSendQueueMock()
        let realtimeService = RealtimeServiceMock()
        let sut = SessionWorkLauncher(
            conversationList: conversationList,
            messageNotifications: messageNotifications,
            messageDelivery: messageSendQueue,
            realtimeService: realtimeService
        )
        var calls: [String] = []
        conversationList.onStart = { calls.append("list") }
        messageNotifications.onStart = { calls.append("notifications") }
        messageSendQueue.onResume = { calls.append("sendQueue") }
        realtimeService.onStart = { calls.append("realtime") }

        sut.startSessionWork()

        XCTAssertEqual(calls, ["list", "notifications", "sendQueue", "realtime"])
    }
}
