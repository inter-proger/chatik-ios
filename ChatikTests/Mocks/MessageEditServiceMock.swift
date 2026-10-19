//
//  MessageEditServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса правок: запоминает запуски, держит запрос, пока тест не завершит его (`finish`), и отдаёт исход
/// и тому, кто запустил запрос, и ожидающим. Ошибку запроса, кроме отмены, хранит до `takeFailure`, как сервис.
@MainActor
@Observable
final class MessageEditServiceMock: MessageEditServiceProtocol {
    private(set) var submittingConversationIds: Set<Int> = []
    @ObservationIgnored private(set) var submits: [(conversationId: Int, userId: Int)] = []
    /// `false` — `submit` не начинает запрос и возвращает `nil`, как при выключенном режиме.
    @ObservationIgnored var acceptsSubmit = true
    @ObservationIgnored private var tasks: [Int: Task<Void, Error>] = [:]
    @ObservationIgnored private var outcomes: [Int: CheckedContinuation<Void, Error>] = [:]
    /// Непоказанные ошибки запросов по `conversationId`.
    @ObservationIgnored var failures: [Int: Error] = [:]

    func isSubmitting(conversationId: Int) -> Bool {
        submittingConversationIds.contains(conversationId)
    }

    @discardableResult
    func submit(conversationId: Int, userId: Int) -> Task<Void, Error>? {
        submits.append((conversationId, userId))
        guard acceptsSubmit, tasks[conversationId] == nil else { return nil }
        let task = startSubmission(conversationId: conversationId)
        tasks[conversationId] = task
        submittingConversationIds.insert(conversationId)
        return task
    }

    func waitForSubmission(conversationId: Int) async throws {
        try await tasks[conversationId]?.value
    }

    func takeFailure(conversationId: Int) -> Error? {
        failures.removeValue(forKey: conversationId)
    }

    /// Начинает запрос переписки, как будто его запустил прошлый экран.
    /// - Parameter conversationId: переписка.
    func startPendingSubmission(conversationId: Int) {
        tasks[conversationId] = startSubmission(conversationId: conversationId)
        submittingConversationIds.insert(conversationId)
    }

    /// Завершает идущий запрос переписки.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - result: исход запроса.
    func finish(conversationId: Int, with result: Result<Void, Error>) async {
        await waitUntilStarted(conversationId: conversationId)
        if case let .failure(error) = result, !(error is CancellationError) {
            failures[conversationId] = error
        }
        outcomes.removeValue(forKey: conversationId)?.resume(with: result)
        _ = await tasks[conversationId]?.result
        tasks[conversationId] = nil
        submittingConversationIds.remove(conversationId)
    }

    /// Задача запроса: ждёт исхода от теста.
    /// - Parameter conversationId: переписка.
    private func startSubmission(conversationId: Int) -> Task<Void, Error> {
        Task {
            try await withCheckedThrowingContinuation { continuation in
                outcomes[conversationId] = continuation
            }
        }
    }

    /// Дожидается, пока задача запроса начнёт ждать исход.
    /// - Parameter conversationId: переписка.
    private func waitUntilStarted(conversationId: Int) async {
        while outcomes[conversationId] == nil {
            await Task.yield()
        }
    }
}
