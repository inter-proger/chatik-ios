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
| [Подъём чатов в списке: архитектура клиента](docs/conversation-list-architecture.md) | `ConversationListService`, очередь WS-событий с приостановкой, стартовая синхронизация списка |
| [Синхронизация ленты сообщений: архитектура клиента](docs/messages-sync-architecture.md) | `MessageCacheService` — единый писатель сообщений, `MessagesListService`, признак синхронизации, `receivedAfter` и `getBlockBatch` |

### Изменения серверного API

Каталог `docs/api-changes/`, по файлу на каждое изменение; имя начинается с даты: `ГГГГ-ММ-ДД-<тема>.md`. Новые — сверху.

| Дата | Документ | О чём |
| --- | --- | --- |
| 14.10.2026 | [Синхронизация кэша сообщений: изменения API для клиентов](docs/api-changes/2026-10-14-message-cache-sync.md) | `receivedAfter` и `updatedBlockIds` в `getList`, `getBlockBatch` и `MessageBlock`, пустые блоки, алгоритм синхронизации кэша |
| 13.10.2026 | [ServerAi API: изменения для клиентов](docs/api-changes/2026-10-13-conversation-position-and-ms-time.md) | время в миллисекундах, `lastMessage` и `positionUpdatedAt`, фильтры `getList`, `getBatch`, правила слияния переписки |

Новые документы кладутся в `docs/` и добавляются в таблицы выше.
