//
//  MessageDraftStorageService.swift
//  Chatik
//

import CoreData

/// Локальное состояние поля ввода переписки: черновик нового сообщения и незавершённое редактирование.
struct MessageDraft: Equatable, Sendable {
    /// Черновик нового сообщения; `nil` — черновика нет.
    var text: String?
    /// Незавершённое редактирование; `nil` — режим выключен.
    var edit: MessageEditDraft?

    /// - Parameters:
    ///   - text: черновик нового сообщения.
    ///   - edit: незавершённое редактирование.
    init(text: String? = nil, edit: MessageEditDraft? = nil) {
        self.text = text
        self.edit = edit
    }

    /// `true` — нет ни черновика, ни редактирования: записи не нужно.
    var isEmpty: Bool { text == nil && edit == nil }
}

/// Незавершённое редактирование своего сообщения.
struct MessageEditDraft: Equatable, Sendable {
    let messageId: Int
    /// Текст сообщения на момент включения режима.
    let originalText: String
    /// Набранный текст правки; хранится как есть, пустая строка допустима.
    var text: String
}

/// Изменение записи одной переписки: меняются только переданные поля. Запись частичная, потому что сервис
/// черновиков не всегда знает оба поля (черновик не загрузился, пользователь вышел), и запись целиком стёрла бы
/// невидимое поле.
struct MessageDraftChange: Equatable, Sendable {
    /// `nil` — не трогать; `.some(nil)` — удалить черновик; `.some(text)` — записать.
    var text: String??
    /// `nil` — не трогать; `.some(nil)` — выключить режим редактирования; `.some(edit)` — записать.
    var edit: MessageEditDraft??

    /// - Parameters:
    ///   - text: изменение черновика; по умолчанию — не трогать.
    ///   - edit: изменение редактирования; по умолчанию — не трогать.
    init(text: String?? = nil, edit: MessageEditDraft?? = nil) {
        self.text = text
        self.edit = edit
    }

    /// Изменение только черновика.
    /// - Parameter text: новый черновик; `nil` — удалить.
    static func draft(_ text: String?) -> MessageDraftChange {
        MessageDraftChange(text: .some(text))
    }

    /// Изменение только редактирования.
    /// - Parameter edit: новое состояние; `nil` — выключить режим.
    static func edit(_ edit: MessageEditDraft?) -> MessageDraftChange {
        MessageDraftChange(edit: .some(edit))
    }

    /// `true` — изменение что-то записывает, а не только удаляет: для него может понадобиться новая запись.
    var writesValue: Bool {
        text.flatMap { $0 } != nil || edit.flatMap { $0 } != nil
    }
}

protocol MessageDraftStorageServiceProtocol {
    /// Состояния полей ввода пользователя по `conversationId`.
    func fetchAll(userId: Int) async throws -> [Int: MessageDraft]
    /// Применяет изменения к записям пользователя одним фоновым контекстом: upsert по `userId`
    /// и `conversationId`; запись, в которой не осталось ни черновика, ни правки, удаляется.
    func apply(_ changes: [Int: MessageDraftChange], userId: Int) async throws
    /// Удаляет записи всех пользователей, сохранённые последний раз раньше `date`.
    func deleteAll(updatedBefore date: Date) async throws
}

/// Хранилище полей ввода переписок (черновики и незавершённые правки) в CoreData. Эти записи переживают выход
/// из аккаунта; пользователей разделяет ключ записи `(userId, conversationId)`.
final class MessageDraftStorageService: MessageDraftStorageServiceProtocol {
    private let container: PersistentContainerProvider
    private let now: () -> Date

    /// - Parameters:
    ///   - container: хранилище CoreData.
    ///   - now: текущее время — момент сохранения черновика (`updatedAt`); подменяется в тестах.
    init(container: PersistentContainerProvider, now: @escaping () -> Date = { Date() }) {
        self.container = container
        self.now = now
    }

    /// Возвращает состояния полей ввода пользователя. Записи без черновика и без правки пропускаются.
    /// - Parameter userId: пользователь, набравший черновики.
    func fetchAll(userId: Int) async throws -> [Int: MessageDraft] {
        try await container.performRead { context in
            let pairs = try context.fetch(MessageDraftEntity.makeFetchRequest(userId: userId)).compactMap { entity in
                let draft = entity.draft
                return draft.isEmpty ? nil : (Int(entity.conversationId), draft)
            }
            return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        }
    }

    /// Применяет изменения одним `context.save()`: переданные поля обновляют запись с тем же `userId`
    /// и `conversationId` или новую; запись, ставшая пустой, удаляется. Для отсутствующей записи изменение, которое
    /// только удаляет, ничего не делает.
    /// - Parameters:
    ///   - changes: изменения по `conversationId`.
    ///   - userId: пользователь, набравший черновики.
    func apply(_ changes: [Int: MessageDraftChange], userId: Int) async throws {
        guard !changes.isEmpty else { return }
        let now = now()
        try await container.performWrite { context in
            let request = MessageDraftEntity.makeFetchRequest(userId: userId, conversationIds: Array(changes.keys))
            let pairs = try context.fetch(request).map { (Int($0.conversationId), $0) }
            let existing = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
            for (conversationId, change) in changes {
                guard let entity = existing[conversationId] ?? (change.writesValue ? MessageDraftEntity(context: context) : nil) else {
                    continue
                }
                entity.userId = Int64(userId)
                entity.conversationId = Int64(conversationId)
                entity.apply(change)
                entity.updatedAt = now
                if entity.draft.isEmpty {
                    context.delete(entity)
                }
            }
            try context.save()
        }
    }

    /// Удаляет черновики всех пользователей с `updatedAt` раньше `date` одним пакетным запросом, не загружая
    /// записи в память. Записи без `updatedAt` не трогаются: дата пишется при каждом сохранении, и такая запись —
    /// не просроченный черновик, а неизвестное состояние. Сервисы работают через короткоживущие фоновые контексты,
    /// поэтому мержить удаление в другие контексты не нужно.
    /// - Parameter date: граница: черновики, сохранённые раньше неё, удаляются.
    func deleteAll(updatedBefore date: Date) async throws {
        try await container.performWrite { context in
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: MessageDraftEntity.entityName)
            request.predicate = NSPredicate(format: "%K < %@", MessageDraftEntity.updatedAtKey, date as NSDate)
            try context.execute(NSBatchDeleteRequest(fetchRequest: request))
        }
    }
}

private extension MessageDraftEntity {
    /// Состояние поля ввода из записи. Правка без `editOriginalText` или `editText` (повреждённая запись) читается
    /// как выключенный режим.
    var draft: MessageDraft {
        MessageDraft(text: text, edit: edit)
    }

    /// Незавершённое редактирование; `nil` — режим выключен или запись повреждена.
    var edit: MessageEditDraft? {
        guard editMessageId != 0, let editOriginalText, let editText else { return nil }
        return MessageEditDraft(messageId: Int(editMessageId), originalText: editOriginalText, text: editText)
    }

    /// Переносит в запись переданные поля изменения.
    /// - Parameter change: изменение; непереданные поля не трогаются.
    func apply(_ change: MessageDraftChange) {
        if let text = change.text {
            self.text = text
        }
        if let edit = change.edit {
            editMessageId = Int64(edit?.messageId ?? 0)
            editOriginalText = edit?.originalText
            editText = edit?.text
        }
    }
}
