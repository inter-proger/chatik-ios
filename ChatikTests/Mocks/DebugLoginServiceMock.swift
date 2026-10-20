//
//  DebugLoginServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок debug-входа: запоминает переданные данные и возвращает заданный результат после хука `onLogin`.
@MainActor
final class DebugLoginServiceMock: DebugLoginPerforming {
    var stubbedResult: Result<Void, Error> = .success(())
    private(set) var receivedCredentials: [DebugLoginCredentials] = []
    /// Ожидается внутри `login` до возврата результата — пока роутер гарантированно в состоянии входа.
    var onLogin: (@MainActor () async -> Void)?

    /// Запоминает данные, ждёт хук `onLogin` и возвращает `stubbedResult`.
    /// - Parameter credentials: логин и пароль из аргументов запуска.
    func login(_ credentials: DebugLoginCredentials) async throws {
        receivedCredentials.append(credentials)
        await onLogin?()
        try stubbedResult.get()
    }
}
