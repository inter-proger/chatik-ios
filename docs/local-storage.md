# Локальная БД (CoreData): архитектура клиента

22.10.2026 · Mikhail Kuzmin

Статус: описание реализованного.

## Назначение

БД — в основном кэш серверных данных текущего пользователя: переписки, сообщения, пользователи, файлы, состояние синхронизации. Исключение — черновики и очередь отправки: их нет на сервере, и они переживают выход из аккаунта.

## Состав

| Тип | Роль |
| --- | --- |
| `CoreDataStack` | фабрика `NSPersistentContainer`: модель, миграция, пересоздание повреждённого хранилища |
| `PersistentContainerProvider` | источник контейнера; `performRead` / `performWrite` в новом фоновом контексте |
| `BackgroundLoadedContainer` | открывает хранилище в фоне при старте |
| `StorageEntity` | общие выборка по id и upsert для Entity с серверным id |
| `*Entity` | записи БД; сырые структуры — в `Model` |
| `*StorageService` | чтение и запись одного вида данных |
| `LocalStorageCleaner` | очистка при входе и выходе ([авторизация и сессия](auth-and-session.md)) |
| `Logger.storage` | ошибки БД: пользователю не показываются, но логируются |

## Сущности (версия `Chatik 12`)

| Entity | Ключ (unique) | Писатель | Документ |
| --- | --- | --- | --- |
| `ConversationEntity` | `conversationId` | `ConversationListService` | [conversation-list-architecture.md](conversation-list-architecture.md) |
| `ConversationListStateEntity` | — (одна запись) | `ConversationListService` | там же, [unread-messages.md](unread-messages.md) |
| `MessageEntity` | `messageId` | `MessageCacheService` | [messages-sync-architecture.md](messages-sync-architecture.md) |
| `MessageCacheStateEntity` | `conversationId` | `MessageCacheService` | там же |
| `OutgoingMessageEntity` | `senderId, clientId` | `MessageSendQueue` | [unsent-messages.md](unsent-messages.md) |
| `MessageDraftEntity` | `userId, conversationId` | `MessageDraftService` | [message-drafts.md](message-drafts.md), [message-editing.md](message-editing.md) |
| `MemberReadEntity` | `conversationId, userId` | `MemberReadService` | [read-receipts.md](read-receipts.md) |
| `UserEntity` | `userId` | `UserCacheStore` | [users-cache.md](users-cache.md) |
| `FileEntity` | `fileId` | вместе с владельцем (аватар пользователя или переписки) | [profile-and-avatar.md](profile-and-avatar.md) |

Правило: **у каждого вида данных один писатель**. Остальные читают через узкие протоколы (например, `MessageStorageReading`). Связи `avatar` → `FileEntity` — с правилом `Nullify`.

## Контексты и потоки

- `viewContext` не используется. Каждая операция — новый короткоживущий фоновый контекст (`performBackgroundTask`), поэтому мержить изменения между контекстами не нужно.
- `performWrite` ставит политику слияния `NSMergeByPropertyObjectTrumpMergePolicy`; `save()` вызывается внутри блока.
- Storage-сервисы — `@unchecked Sendable`: единственное состояние — источник контейнера, используемый только через `performBackgroundTask`.
- `StorageEntity.upsert` достаёт существующие записи одним запросом `IN`, повторы id в списке схлопываются в одну запись с данными последнего элемента; возвращает словарь `id → Entity` для проставления связей.
- Записи с битыми данными при чтении пропускаются (`init?(entity:)` возвращает `nil`).

## Открытие хранилища

1. `DIContainer` создаёт `BackgroundLoadedContainer { CoreDataStack.makeContainer() }`: открытие SQLite и миграция идут в `Task.detached`, первый кадр их не ждёт; запросы, пришедшие раньше, дожидаются открытия.
2. Модель `Chatik.momd` загружается один раз на процесс — иначе в тестах несколько моделей претендуют на одни классы Entity.
3. Миграция — лёгкая (автоматическая, с выводом mapping model); `.xcmappingmodel` в проекте нет.
4. **Не открылось** (файл повреждён, миграция не справилась) — хранилище удаляется вместе с `-wal` и `-shm` и создаётся заново: БД — кэш, лучше потерять его, чем падать на каждом запуске. Если не открылось и новое — `fatalError`.
5. **Хранилище версий 1–5** (`Chatik` … `Chatik 5`, серверное время в секундах) после миграции очищается от `ConversationEntity` и `MessageEntity`: время не переводится в миллисекунды, данные загрузятся заново. Целиком хранилище не пересоздаётся — пропали бы неотправленные сообщения. Версия определяется по метаданным до открытия.

## Версии модели

Новая версия — новый `Chatik N.xcdatamodel` и `_XCCurrentVersionName` в `.xccurrentversion`; изменения должны укладываться в лёгкую миграцию. История:

| Версия | Что появилось |
| --- | --- |
| `Chatik`, 2 | переписки, файлы, пользователи |
| 3–4 | сообщения |
| 5 | очередь отправки |
| 6 | время в миллисекундах, состояние списка переписок |
| 7 | состояние кэша сообщений |
| 8 | черновики |
| 9 | уникальность очереди отправки по `senderId, clientId` |
| 10 | режим редактирования в черновике |
| 11 | прочтение и счётчики непрочитанных; курсор изменений — следующая синхронизация списка полная |
| 12 | прочтение другими участниками (`MemberReadEntity`) |

## Тесты

- `CoreDataStackTests`: повреждённое хранилище пересоздаётся, корректное сохраняет данные, `BackgroundLoadedContainer` дожидается открытия; миграция с каждой прежней версии (1, 2, 5–10) сохраняет нужные данные и очищает кэш со временем в секундах.
- `*StorageServiceTests` по каждому хранилищу, `LocalStorageCleanerTests`.
- В тестах и превью хранилище — SQLite по адресу `/dev/null` (`makeContainer(inMemory: true)`): работают unique constraints и `NSBatchDeleteRequest`.
