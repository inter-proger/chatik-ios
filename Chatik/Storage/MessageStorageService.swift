//
//  MessageStorageService.swift
//  Chatik
//

import CoreData

protocol MessageStorageServiceProtocol {
    /// Сохраняет сообщение (upsert по `messageId`); его неотправленная копия удаляется.
    func save(message: Message) async throws
    /// Сохраняет список сообщений одним фоновым контекстом; их неотправленные копии удаляются.
    func save(messages: [Message]) async throws
    /// Возвращает не больше `limit` самых новых сохранённых сообщений переписки, сначала самые новые.
    func fetchLatest(conversationId: Int, limit: Int) async throws -> [Message]
    /// Ищет сообщение по идентификатору.
    func find(byId id: Int) async throws -> Message?
    /// Удаляет сообщение по идентификатору, если оно найдено.
    func delete(byId id: Int) async throws
}

/// Хранилище сообщений в CoreData — чтобы переписку можно было открыть без сети. Все операции выполняются
/// в фоновых контекстах.
///
/// Сообщения, которых нет в ответе сервера, из БД не удаляются: API не умеет удалять сообщения, а изменения
/// (редактирование) приходят тем же сообщением и перезаписывают запись по `messageId`.
///
/// Серверное сообщение с тем же отправителем и `clientId`, что у неотправленного (`OutgoingMessageEntity`), —
/// подтверждение его доставки: неотправленная копия удаляется в той же записи. Так очередь отправки очищается,
/// откуда бы ни пришло сообщение — из ответа `/messages/send`, события WebSocket или страницы переписки.
final class MessageStorageService: MessageStorageServiceProtocol {
    private let container: PersistentContainerProvider

    init(container: PersistentContainerProvider) {
        self.container = container
    }

    /// Сохраняет одно сообщение: обновляет существующую запись с тем же `messageId` или создаёт новую.
    /// - Parameter message: сырая структура сообщения.
    func save(message: Message) async throws {
        try await save(messages: [message])
    }

    /// Сохраняет список сообщений одним фоновым контекстом (upsert по `messageId`) и удаляет их неотправленные копии.
    /// - Parameter messages: сырые структуры; повторы `messageId` схлопываются в одну запись.
    func save(messages: [Message]) async throws {
        guard !messages.isEmpty else { return }
        try await container.performWrite { context in
            try MessageEntity.upsert(messages, in: context)
            try OutgoingMessageEntity.deleteConfirmed(by: messages, in: context)
            try context.save()
        }
    }

    /// Возвращает самые новые сообщения переписки по убыванию `messageId` — в порядке выдачи сервера.
    /// Записи с битыми данными пропускаются, поэтому сообщений может вернуться меньше `limit`.
    /// - Parameters:
    ///   - conversationId: переписка, сообщения которой нужны.
    ///   - limit: максимальное число сообщений.
    func fetchLatest(conversationId: Int, limit: Int) async throws -> [Message] {
        try await container.performRead { context in
            let request = MessageEntity.makeFetchRequest()
            request.predicate = NSPredicate(format: "%K == %lld", MessageEntity.conversationIdKey, Int64(conversationId))
            request.sortDescriptors = [NSSortDescriptor(key: MessageEntity.idKey, ascending: false)]
            request.fetchLimit = limit
            return try context.fetch(request).compactMap(Message.init(entity:))
        }
    }

    /// Ищет сообщение по идентификатору.
    /// - Parameter id: идентификатор искомого сообщения.
    func find(byId id: Int) async throws -> Message? {
        try await container.performRead { context in
            try context.fetch(MessageEntity.makeFetchRequest(id: id)).first.flatMap(Message.init(entity:))
        }
    }

    /// Удаляет сообщение по идентификатору.
    /// - Parameter id: идентификатор удаляемого сообщения.
    func delete(byId id: Int) async throws {
        try await container.performWrite { context in
            guard let entity = try context.fetch(MessageEntity.makeFetchRequest(id: id)).first else { return }
            context.delete(entity)
            try context.save()
        }
    }
}
