//
//  AuthServiceObserverMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Наблюдатель за выходом: записывает уведомления в общий журнал — по нему проверяется порядок
/// уведомлений относительно запроса и других наблюдателей.
@MainActor
final class AuthServiceObserverMock: AuthServiceObserver {
    private let name: String
    private let log: EventLog

    /// - Parameters:
    ///   - name: имя наблюдателя в журнале.
    ///   - log: общий журнал событий теста.
    init(name: String = "observer", log: EventLog) {
        self.name = name
        self.log = log
    }

    /// Причины из `authServiceDidLogout(reason:)` по порядку.
    private(set) var reasons: [LogoutReason] = []

    /// Записывает в журнал начало выхода.
    func authServiceWillLogout() async {
        log.events.append("\(name).willLogout")
    }

    /// Записывает в журнал завершение выхода и запоминает причину.
    /// - Parameter reason: причина выхода.
    func authServiceDidLogout(reason: LogoutReason) async {
        reasons.append(reason)
        log.events.append("\(name).didLogout")
    }
}

/// Журнал событий теста в порядке появления.
@MainActor
final class EventLog {
    var events: [String] = []
}
