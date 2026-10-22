# Chatik

iOS-клиент мессенджера на SwiftUI (iOS 17+): авторизация, профиль, список переписок, личные диалоги, лента сообщений с отправкой и события реального времени через WebSocket. Серверные данные кэшируются в CoreData.

## Структура проекта

| Каталог | Что внутри |
| --- | --- |
| `Chatik/Screens` | экраны: View, ViewModel, роутер и строки каждого экрана |
| `Chatik/Services` | сеть, WebSocket, сессия, сервисы API и кэш пользователей |
| `Chatik/Storage` | CoreData: модель, Entity и storage-сервисы |
| `Chatik/Model` | сырые структуры ответов API |
| `Chatik/Common` | общие компоненты и утилиты (пагинация, аватары, локализация) |
| `ChatikTests` | unit-тесты и моки |
| `Config` | xcconfig сборки; локальные настройки — в `Local.xcconfig` (шаблон `Local.xcconfig.example`) |
| `docs` | проектные документы |

## Документы

| Документ | О чём |
| --- | --- |
| [Правила разработки](docs/development-rules.md) | git: ветка на задачу от `develop`, pull request в `develop`; порядок по умолчанию: документ → ревью документа → реализация → ревью реализации → коммит и PR |
| [Архитектура приложения: обзор](docs/app-architecture.md) | слои, `DIContainer` и порядок сборки, структура экрана, навигация и роутеры, жизненный цикл, конкурентность, xcconfig и `AppConfig`, превью, логи |
| [Сетевой слой: архитектура клиента](docs/networking.md) | `NetworkService` и `Endpoint`, разбор `APIResponse`, глобальный 2003, `actions` и `APIActionDispatcher`, multipart-загрузка из файла, `NetworkError`, `NetworkLogger` |
| [Авторизация и сессия: архитектура клиента](docs/auth-and-session.md) | `AuthService` и двухфазный выход, `SessionService`, очистка БД, истечение сессии, `SessionWorkLauncher`, фон, экран авторизации и правила валидации |
| [Соединение реального времени (WebSocket): архитектура клиента](docs/realtime-connection.md) | протокол событий, цикл токен → `auth` → события, исходы закрытия, backoff, heartbeat, `RealtimeConnectionMonitor` |
| [Пользователи: кэш и выбор собеседника](docs/users-cache.md) | `UserCacheService` / `UserCacheStore` / `UserCacheSnapshot`, устаревание и пачки, `/users/getList`, экран создания личного диалога |
| [Профиль и аватар: архитектура клиента](docs/profile-and-avatar.md) | профиль из сессии, выбор фото, `ImageFileStore` и лимиты, загрузка с прогрессом, `AvatarView`, `RemoteFile` |
| [Локальная БД (CoreData): архитектура клиента](docs/local-storage.md) | сущности и их писатели, фоновые контексты, открытие в фоне, пересоздание и миграции, история версий модели |
| [Язык интерфейса и строки: архитектура клиента](docs/localization.md) | `LocalizationService` и свой bundle языка, перерисовка через Observation, `Localized` и таблицы `XxxStrings`, подстановки и `.stringsdict`, `UserDefaultsService` |
| [Постраничный список `PaginatedList`](docs/paginated-list.md) | контракт загрузчика, `refresh` с кэшем, подгрузка у конца, `syncFirstPage`, отбрасывание устаревших ответов, дубликаты |
| [Подъём чатов в списке: архитектура клиента](docs/conversation-list-architecture.md) | `ConversationListService`, очередь WS-событий с приостановкой, стартовая синхронизация списка |
| [Синхронизация ленты сообщений: архитектура клиента](docs/messages-sync-architecture.md) | `MessageCacheService` — единый писатель сообщений, `MessagesListService`, признак синхронизации, `receivedAfter` и `getBlockBatch` |
| [Заголовки дат в ленте сообщений](docs/message-date-headers.md) | правила дат «Сегодня / Вчера / день недели / год», сервис `MessageDateHeaderFormatting` с реализацией для русского, секции по дням, в сообщениях только время, плавающая дата при прокрутке |
| [Черновики сообщений: архитектура клиента](docs/message-drafts.md) | `MessageDraftService` с кэшем в памяти, `MessageDraftEntity` по пользователю и переписке, переживает выход из аккаунта, точки сохранения, «Черновик:» в списке чатов |
| [Неотправленные сообщения в списке чатов: архитектура клиента](docs/unsent-messages.md) | «Не отправлено:» в списке чатов с приоритетом над черновиком, индекс `lastFailedTexts` в `MessageSendQueue`, очередь переживает выход, отправка при выходе прерывается в `.failed` |
| [Редактирование сообщений: архитектура клиента](docs/message-editing.md) | меню по долгому нажатию, режим редактирования в `MessageDraftService` рядом с черновиком, `MessageEditService` с запросом, переживающим уход с экрана, `applyEdited` в кэше и списке, «Редактирование активно» в списке чатов, пометка «Изменено» в ленте |
| [Debug-вход по аргументам запуска: архитектура клиента](docs/debug-auto-login.md) | `-debugLogin` / `-debugPassword` только в Debug, стартовый экран `.debugLogin`, выход прежнего пользователя через `AuthService.logout()`, `DebugLoginService` поверх обычного пути входа |
| [Уведомления в приложении: архитектура клиента](docs/in-app-notifications.md) | `InAppNotificationService`: всегда последнее без очереди, время по длине текста, свайп и пауза как у пушей, только в активном приложении; окно поверх листов, модификатор `.inAppNotifications` на корне; ошибки вместо алертов |
| [Уведомления о входящих сообщениях: архитектура клиента](docs/incoming-message-notifications.md) | `MessageNotificationService` на очереди событий: фильтр «не своё и не открыто», подготовка «последнее побеждает»; вид `.message`; `ConversationNavigator` по сценам, открытие переписки с любого экрана, `.id` экрана переписки для сохранения черновиков |
| [Непрочитанные сообщения: архитектура клиента](docs/unread-messages.md) | прочтение в `ConversationListService`, курсор `changedAfter` вместо `updatedInfoAfter`, единое правило `markRead`, закреплённый заголовок непрочитанных, кнопка «вниз», удержание ленты при вставке, счётчики «99+»; бейдж на иконке отложен до push |
| [Прочтение другими участниками: архитектура клиента](docs/read-receipts.md) | `MemberReadService` с указателями участников и `MemberReadEntity`, галочки по `max(указатели)` в `MessageDeliveryState.read`, «Кем прочитано» только в `group` без автора, системный лист; критика требований |

### Изменения серверного API

Каталог `docs/api-changes/`, по файлу на каждое изменение; имя начинается с даты: `ГГГГ-ММ-ДД-<тема>.md`. Новые — сверху.

| Дата | Документ | О чём |
| --- | --- | --- |
| 14.10.2026 | [Синхронизация кэша сообщений: изменения API для клиентов](docs/api-changes/2026-10-14-message-cache-sync.md) | `receivedAfter` и `updatedBlockIds` в `getList`, `getBlockBatch` и `MessageBlock`, пустые блоки, алгоритм синхронизации кэша |
| 13.10.2026 | [ServerAi API: изменения для клиентов](docs/api-changes/2026-10-13-conversation-position-and-ms-time.md) | время в миллисекундах, `lastMessage` и `positionUpdatedAt`, фильтры `getList`, `getBatch`, правила слияния переписки |

Новые документы кладутся в `docs/` и добавляются в таблицы выше.
