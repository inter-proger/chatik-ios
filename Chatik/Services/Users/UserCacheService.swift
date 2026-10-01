//
//  UserCacheService.swift
//  Chatik
//

import Foundation

/// Что кэш знает о пользователе.
enum CachedUser: Equatable, Sendable {
    /// Данные есть — возможно, устаревшие (тогда они обновляются с сервера в фоне).
    case loaded(User)
    /// Данных пока нет: загрузка идёт или не удалась и повторится при следующем упоминании пользователя.
    case pending
    /// Сервер сообщил, что такого пользователя нет; повторно он не запрашивается.
    case notFound
}

/// Кэш доступен из любого потока: реализация изолирована на main actor, а `Sendable` в требованиях протокола
/// не даёт подставить реализацию без изоляции — ссылку на кэш можно передавать между задачами и потоками.
@MainActor
protocol UserCacheServiceProtocol: AnyObject, Sendable {
    /// Состояние пользователя в кэше. Чтение отслеживается Observation: экран перерисуется, когда пользователь загрузится.
    func user(id: Int) -> CachedUser
    /// Обеспечивает пользователей в кэше: дожидается загрузки тех, кого в кэше нет, а устаревших перезапрашивает
    /// в фоне, не дожидаясь.
    func loadUsers(ids: [Int]) async
}

/// Кэш пользователей по `userId`. Сервер не присылает пользователей внутри переписок и сообщений — только их id
/// (поля и action `users`); имена и аватары клиент берёт отсюда.
///
/// Уровни: память → БД (переживает перезапуск) → сервер (`/users/getBatch`). Вся работа кэша — решения, что
/// читать из БД и что запрашивать, учёт идущих запросов, сеть и БД — выполняется вне главного потока
/// в `UserCacheStore`. На main actor только копия состояний (`UserCacheSnapshot`): экраны читают её синхронно,
/// и Observation перерисовывает их, когда пользователь загрузится. Стратегия загрузки и устаревания описана
/// у `UserCacheStore`.
///
/// При выходе из аккаунта кэш в памяти не очищается: профили пользователей не принадлежат текущему пользователю —
/// любой из них отдаёт `/users/getList` — и остаются верными для следующего. БД при этом очищается целиком
/// (`LocalStorageCleaner` при выходе и при входе), поэтому после перезапуска приложения такие пользователи
/// загрузятся с сервера заново.
@MainActor
final class UserCacheService: UserCacheServiceProtocol {
    /// Через сколько после получения с сервера пользователь считается устаревшим.
    static var freshnessInterval: TimeInterval { UserCacheStore.freshnessInterval }

    private let snapshot = UserCacheSnapshot()
    private let store: UserCacheStore

    /// - Parameters:
    ///   - usersService: сервис пользователей — источник `/users/getBatch`.
    ///   - userStorage: хранилище пользователей в БД.
    ///   - now: текущее время; подменяется в тестах устаревания.
    init(
        usersService: UsersServiceProtocol,
        userStorage: UserStorageServiceProtocol,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        store = UserCacheStore(usersService: usersService, userStorage: userStorage, snapshot: snapshot, now: now)
    }

    /// Возвращает состояние пользователя из копии на main actor; устаревший пользователь тоже `.loaded`.
    /// - Parameter id: идентификатор пользователя.
    func user(id: Int) -> CachedUser {
        snapshot.state(id: id)
    }

    /// Загружает пользователей вне главного потока; возвращается, когда отсутствовавшие загружены и видны в `user(id:)`.
    /// - Parameter ids: идентификаторы пользователей; повторы допустимы.
    func loadUsers(ids: [Int]) async {
        await store.loadUsers(ids: ids)
    }
}
