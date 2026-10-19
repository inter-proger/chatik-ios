//
//  MessageEditService.swift
//  Chatik
//

import Foundation

/// Отправка правок сообщений — всё, что о ней знает экран переписки.
@MainActor
protocol MessageEditServiceProtocol: AnyObject, AuthServiceObserver {
    /// Идёт ли запрос правки в переписке. Отслеживается Observation.
    func isSubmitting(conversationId: Int) -> Bool
    /// Начинает отправку текущей правки переписки (`MessageDraftService.edit(for:)`). Синхронно: к возврату
    /// переписка уже в `isSubmitting`, и кнопка с полем ввода блокируются в том же кадре, что и нажатие.
    /// Запрос живёт в сервисе и не отменяется при уходе с экрана.
    /// - Returns: задача запроса — её исход получает и тот, кто начал запрос, даже если запрос завершится раньше, чем
    ///   его начнут ждать; `nil` — запрос не начат: режим выключен, запрос по переписке уже идёт или идёт выход.
    @discardableResult
    func submit(conversationId: Int, userId: Int) -> Task<Void, Error>?
    /// Дожидается идущего запроса переписки и получает его исход; запроса нет — сразу возвращается.
    /// Все ожидающие получают один и тот же исход одного запроса.
    /// - Throws: ошибка сервера или сети; `CancellationError` — запрос отменён выходом.
    func waitForSubmission(conversationId: Int) async throws
    /// Забирает ошибку последнего запроса переписки, которую ещё не показали. Ошибка хранится до показа: если запрос
    /// упал, пока экран был закрыт, её покажет следующее открытие экрана.
    /// - Returns: ошибка запроса; `nil` — запрос не падал или ошибку уже забрали.
    func takeFailure(conversationId: Int) -> Error?
}

/// Отправка правок сообщений. Запрос живёт в сервисе, а не на экране: по требованию списка чатов он должен
/// завершиться и выключить режим редактирования, даже если экран уже закрыт.
///
/// После успеха сервис по очереди записывает сообщение в кэш, обновляет превью в списке чатов и выключает режим
/// в сервисе черновиков. Порядок важен: экран узнаёт об успехе по выключенному режиму, и к этому моменту лента
/// уже получила новую версию. По одной переписке одновременно идёт не больше одного запроса.
///
/// Выход из аккаунта отменяет запросы, и их ответы не применяются: кэш и список закрывающейся сессии не меняются,
/// а режим редактирования остаётся в БД у сервиса черновиков. Повторная отправка после входа безвредна — сервер
/// вернёт сообщение без изменений.
@MainActor
@Observable
final class MessageEditService: MessageEditServiceProtocol {
    /// Идущий запрос правки переписки.
    private struct Submission {
        let id: UUID
        let task: Task<Void, Error>
    }

    /// Переписки, по которым идёт запрос.
    private(set) var submittingConversationIds: Set<Int> = []
    @ObservationIgnored private var submissions: [Int: Submission] = [:]
    /// Ошибки запросов, которые ещё не показали, по `conversationId`.
    @ObservationIgnored private var failures: [Int: Error] = [:]
    /// Растёт при каждом выходе: ответы запросов прошлой сессии не применяются.
    @ObservationIgnored private var sessionGeneration = 0
    /// Идёт выход: новые запросы не начинаются — их не отменил бы уже начатый выход.
    @ObservationIgnored private var isLoggingOut = false

    private let messageService: MessageServiceProtocol
    private let messageCache: MessageCacheServiceProtocol
    private let positionUpdater: ConversationPositionUpdating
    private let draftService: MessageDraftServiceProtocol

    /// - Parameters:
    ///   - messageService: запрос `/messages/edit`.
    ///   - messageCache: кэш сообщений — в него пишется новая версия сообщения.
    ///   - positionUpdater: список чатов — в нём обновляется превью.
    ///   - draftService: состояние поля ввода — из него берётся правка, в нём выключается режим.
    init(
        messageService: MessageServiceProtocol,
        messageCache: MessageCacheServiceProtocol,
        positionUpdater: ConversationPositionUpdating,
        draftService: MessageDraftServiceProtocol
    ) {
        self.messageService = messageService
        self.messageCache = messageCache
        self.positionUpdater = positionUpdater
        self.draftService = draftService
    }

    /// Идёт ли запрос правки в переписке.
    /// - Parameter conversationId: переписка.
    func isSubmitting(conversationId: Int) -> Bool {
        submittingConversationIds.contains(conversationId)
    }

    /// Начинает отправку текущей правки переписки.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - userId: пользователь, открывший экран переписки, — владелец правки.
    /// - Returns: задача запроса; `nil` — режим выключен, запрос уже идёт или идёт выход.
    @discardableResult
    func submit(conversationId: Int, userId: Int) -> Task<Void, Error>? {
        guard !isLoggingOut, submissions[conversationId] == nil,
              let edit = draftService.edit(for: conversationId) else { return nil }
        let id = UUID()
        let generation = sessionGeneration
        failures[conversationId] = nil
        let task = Task {
            defer { finishSubmission(id: id, conversationId: conversationId) }
            do {
                try await perform(edit, conversationId: conversationId, userId: userId, generation: generation)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures[conversationId] = error
                throw error
            }
        }
        submissions[conversationId] = Submission(id: id, task: task)
        submittingConversationIds.insert(conversationId)
        return task
    }

    /// Дожидается идущего запроса переписки.
    /// - Parameter conversationId: переписка.
    func waitForSubmission(conversationId: Int) async throws {
        try await submissions[conversationId]?.task.value
    }

    /// Забирает непоказанную ошибку запроса переписки.
    /// - Parameter conversationId: переписка.
    func takeFailure(conversationId: Int) -> Error? {
        failures.removeValue(forKey: conversationId)
    }

    /// Отменяет запросы и дожидается их; до конца выхода новые запросы не начинаются. Поколение растёт
    /// до ожидания: ответ, пришедший во время отмены, уже не применяется. Запросы убирают себя из идущих сами,
    /// по завершении. Непоказанные ошибки отбрасываются: они относятся к закончившейся сессии.
    func authServiceWillLogout() async {
        isLoggingOut = true
        sessionGeneration += 1
        failures = [:]
        let tasks = submissions.values.map(\.task)
        tasks.forEach { $0.cancel() }
        for task in tasks {
            _ = await task.result
        }
    }

    /// Выход завершён: запросы снова принимаются.
    /// - Parameter reason: причина выхода — не важна.
    func authServiceDidLogout(reason: LogoutReason) async {
        isLoggingOut = false
    }

    /// Отправляет правку и применяет ответ. Поколение сессии проверяется перед каждым шагом: выход мог начаться
    /// во время любого ожидания.
    /// - Parameters:
    ///   - edit: отправляемая правка.
    ///   - conversationId: переписка.
    ///   - userId: владелец правки.
    ///   - generation: поколение сессии на момент начала.
    /// - Throws: ошибка запроса; `CancellationError` — запрос отменён или сессия закончилась.
    private func perform(_ edit: MessageEditDraft, conversationId: Int, userId: Int, generation: Int) async throws {
        let result: MessageEditResult
        do {
            result = try await messageService.edit(messageId: edit.messageId, newText: edit.text)
        } catch where Task.isCancelled {
            throw CancellationError()
        }
        try ensureCurrent(generation)
        await messageCache.applyEdited(result.message)
        try ensureCurrent(generation)
        positionUpdater.applyEditedMessage(result.message, lastMessage: result.lastMessage)
        draftService.endEditing(messageId: edit.messageId, conversationId: conversationId, userId: userId)
    }

    /// Убирает запрос из идущих, если на его месте не стоит уже другой.
    /// - Parameters:
    ///   - id: запрос.
    ///   - conversationId: переписка.
    private func finishSubmission(id: UUID, conversationId: Int) {
        guard submissions[conversationId]?.id == id else { return }
        submissions[conversationId] = nil
        submittingConversationIds.remove(conversationId)
    }

    /// Бросает `CancellationError`, если сессия сменилась.
    /// - Parameter generation: поколение сессии на момент начала запроса.
    private func ensureCurrent(_ generation: Int) throws {
        guard generation == sessionGeneration, !Task.isCancelled else { throw CancellationError() }
    }
}
