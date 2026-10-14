//
//  ConversationStorageService.swift
//  Chatik
//

import CoreData

protocol ConversationStorageServiceProtocol {
    /// Все сохранённые переписки в порядке списка и состояние синхронизации.
    func fetchList() async throws -> (conversations: [Conversation], state: ConversationListState)
    /// Сохраняет переписки (upsert с правилами слияния) и состояние синхронизации одной транзакцией;
    /// `state == nil` — состояние не трогается.
    func save(conversations: [Conversation], state: ConversationListState?) async throws
    /// Заменяет список целиком: переписки, которых нет в `conversations`, удаляются (полная загрузка, инвалидация).
    func replaceList(with conversations: [Conversation], state: ConversationListState) async throws
    /// Ищет переписку по идентификатору.
    func find(byId id: Int) async throws -> Conversation?
}

/// Хранилище списка переписок в CoreData. Переписка сохраняется вместе с аватаром — он попадает в хранилище файлов;
/// собеседник хранится только как id, сами пользователи — в кэше пользователей. Рядом хранится состояние
/// синхронизации списка (`ConversationListState`). Все операции выполняются в фоновых контекстах.
///
/// Пишет в хранилище только `ConversationListService`: один писатель — один порядок записей.
final class ConversationStorageService: ConversationStorageServiceProtocol {
    private let container: PersistentContainerProvider

    init(container: PersistentContainerProvider) {
        self.container = container
    }

    /// Возвращает все сохранённые переписки по убыванию позиции (при равенстве — `conversationId`) и состояние
    /// синхронизации. Записи с битыми данными пропускаются; без записи состояния возвращается состояние по умолчанию.
    func fetchList() async throws -> (conversations: [Conversation], state: ConversationListState) {
        try await container.performRead { context in
            let request = ConversationEntity.makeFetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: ConversationEntity.positionKey, ascending: false),
                NSSortDescriptor(key: ConversationEntity.idKey, ascending: false),
            ]
            let conversations = try context.fetch(request).compactMap(Conversation.init(entity:))
            let stateEntity = try context.fetch(ConversationListStateEntity.makeFetchRequest()).first
            return (conversations, stateEntity.map(ConversationListState.init(entity:)) ?? ConversationListState())
        }
    }

    /// Сохраняет переписки одним фоновым контекстом (upsert по `conversationId` с правилами слияния)
    /// и состояние синхронизации.
    /// - Parameters:
    ///   - conversations: сырые структуры; повторы `conversationId` схлопываются в одну запись.
    ///   - state: состояние синхронизации списка; `nil` — сохранённое состояние не меняется (кэш ещё не прочитан,
    ///     и состояние в памяти — значение по умолчанию).
    func save(conversations: [Conversation], state: ConversationListState?) async throws {
        try await container.performWrite { context in
            try ConversationEntity.upsert(conversations, in: context)
            if let state {
                try ConversationListStateEntity.store(state, in: context)
            }
            try context.save()
        }
    }

    /// Заменяет список целиком одним фоновым контекстом: переписки вне `conversations` удаляются, остальные
    /// перезаписываются без слияния — так БД совпадает со списком в памяти, даже если версия сервера «старше»
    /// сохранённой (последнее сообщение удалено, позиция ушла назад). Состояние синхронизации записывается.
    /// Аватары удалённых переписок остаются в хранилище файлов.
    /// - Parameters:
    ///   - conversations: новый список.
    ///   - state: состояние синхронизации списка.
    func replaceList(with conversations: [Conversation], state: ConversationListState) async throws {
        try await container.performWrite { context in
            let request = ConversationEntity.makeFetchRequest()
            request.predicate = NSPredicate(
                format: "NOT (%K IN %@)",
                ConversationEntity.idKey, conversations.map { Int64($0.conversationId) }
            )
            try context.fetch(request).forEach(context.delete)
            try ConversationEntity.upsert(conversations, mergingWithStored: false, in: context)
            try ConversationListStateEntity.store(state, in: context)
            try context.save()
        }
    }

    /// Ищет переписку по идентификатору.
    /// - Parameter id: идентификатор искомой переписки.
    func find(byId id: Int) async throws -> Conversation? {
        try await container.performRead { context in
            try context.fetch(ConversationEntity.makeFetchRequest(id: id)).first.flatMap(Conversation.init(entity:))
        }
    }
}
