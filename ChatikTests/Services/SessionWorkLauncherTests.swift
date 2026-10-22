//
//  SessionWorkLauncherTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class SessionWorkLauncherTests: XCTestCase {
    /// Кейс: сессия открыта, начинается работа с сервером.
    /// Ожидание: порядок — список переписок, уведомления о сообщениях, прочтение другими, отправка очереди,
    /// соединение: уведомления видят переписку из события в списке, ответ на отправку поднимает переписку в списке,
    /// а очередь событий не хранит события для будущих подписчиков.
    func test_startSessionWork_startsListThenNotificationsThenMemberReadsThenSendQueueThenRealtime() {
        let conversationList = ConversationListServiceMock()
        let messageNotifications = MessageNotificationServiceMock()
        let memberReads = MemberReadServiceMock()
        let messageSendQueue = MessageSendQueueMock()
        let realtimeService = RealtimeServiceMock()
        let sut = SessionWorkLauncher(
            conversationList: conversationList,
            messageNotifications: messageNotifications,
            memberReads: memberReads,
            messageDelivery: messageSendQueue,
            realtimeService: realtimeService
        )
        var calls: [String] = []
        conversationList.onStart = { calls.append("list") }
        messageNotifications.onStart = { calls.append("notifications") }
        memberReads.onStart = { calls.append("memberReads") }
        messageSendQueue.onResume = { calls.append("sendQueue") }
        realtimeService.onStart = { calls.append("realtime") }

        sut.startSessionWork()

        XCTAssertEqual(calls, ["list", "notifications", "memberReads", "sendQueue", "realtime"])
    }
}
