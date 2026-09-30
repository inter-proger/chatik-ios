//
//  LocalStorageCleanerMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок очистки локальной БД: считает вызовы и отвечает заданной ошибкой.
final class LocalStorageCleanerMock: LocalStorageCleanerProtocol {
    /// Ошибка, которой завершается очистка; `nil` — очистка успешна.
    var stubbedError: Error?
    private(set) var clearAllCallCount = 0
    /// Вызывается внутри `clearAll` — пока очистка ещё не завершилась.
    var onClearAll: (@MainActor () -> Void)?

    func clearAll() async throws {
        clearAllCallCount += 1
        await onClearAll?()
        if let stubbedError {
            throw stubbedError
        }
    }
}
