//
//  UserCacheStore.swift
//  Chatik
//

import Foundation
import os

/// Логика кэша пользователей вне главного потока: что есть в памяти и в БД, что устарело, какие запросы идут.
/// Источник истины о пользователях; экраны видят его состояние через `UserCacheSnapshot`, куда хранилище
/// передаёт каждое изменение.
///
/// Стратегия `loadUsers`:
/// - пользователя нет в кэше (ни в памяти, ни в БД) — вызывающий ждёт его загрузки;
/// - пользователь есть, но устарел (`freshnessInterval` после получения с сервера) — он перезапрашивается
///   в фоне, вызывающий не ждёт.
///
/// Actor реентерабелен: на каждом `await` (чтение БД, запрос к серверу, доставка в копию) могут выполниться
/// другие вызовы, поэтому после `await` состояние перепроверяется, а не берётся из прочитанного до него.
/// Каждое изменение получает номер (`revision`) в момент, когда происходит, — копия по нему отличает новое
/// состояние от опоздавшего старого.
actor UserCacheStore {
    /// Через сколько после получения с сервера пользователь считается устаревшим.
    static let freshnessInterval: TimeInterval = 3 * 60

    private struct Entry {
        let stored: StoredUser
        let revision: UInt64
    }

    private var entriesById: [Int: Entry] = [:]
    /// Ненайденные на сервере — с номером изменения, на котором это стало известно. Повторно не запрашиваются.
    private var notFoundRevisions: [Int: UInt64] = [:]
    /// Идущие запросы по id пользователя — повторное упоминание дожидается идущего запроса, а не шлёт свой.
    private var requestsById: [Int: Task<Void, Never>] = [:]
    private var lastRevision: UInt64 = 0

    private let usersService: UsersServiceProtocol
    private let userStorage: UserStorageServiceProtocol
    private let snapshot: UserCacheSnapshot
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - usersService: сервис пользователей — источник `/users/getBatch`.
    ///   - userStorage: хранилище пользователей в БД.
    ///   - snapshot: копия на main actor, куда передаются изменения.
    ///   - now: текущее время; подменяется в тестах устаревания.
    init(
        usersService: UsersServiceProtocol,
        userStorage: UserStorageServiceProtocol,
        snapshot: UserCacheSnapshot,
        now: @escaping @Sendable () -> Date
    ) {
        self.usersService = usersService
        self.userStorage = userStorage
        self.snapshot = snapshot
        self.now = now
    }

    /// Подтягивает недостающих в памяти пользователей из БД, затем запрашивает с сервера пачками
    /// по `UsersEndpoint.batchLimit`: отсутствующих — дожидаясь ответа, устаревших — в фоне. Перед возвратом
    /// передаёт состояние запрошенных пользователей в копию и дожидается применения: вызывающий (сетевой слой)
    /// отдаёт ответ экрану, и экран должен сразу увидеть имена.
    /// Ошибки не пробрасываются: незагруженные пользователи остаются `.pending` и запрашиваются снова
    /// при следующем упоминании, ошибка логируется.
    /// - Parameter ids: идентификаторы пользователей; повторы допустимы.
    func loadUsers(ids: [Int]) async {
        let ids = Self.unique(ids)
        await loadFromStorage(ids: ids.filter { entriesById[$0] == nil && notFoundRevisions[$0] == nil })
        let missingIds = ids.filter { entriesById[$0] == nil && notFoundRevisions[$0] == nil }
        let staleIds = ids.filter { entriesById[$0].map { isStale($0.stored) } ?? false }
        request(ids: staleIds)
        for task in request(ids: missingIds) {
            await task.value
        }
        await publish(ids: ids)
    }

    /// Устарел ли пользователь.
    /// - Parameter stored: пользователь со временем получения.
    private func isStale(_ stored: StoredUser) -> Bool {
        now().timeIntervalSince(stored.cachedAt) >= Self.freshnessInterval
    }

    /// Выдаёт номер следующего изменения.
    private func nextRevision() -> UInt64 {
        lastRevision += 1
        return lastRevision
    }

    /// Подставляет в память пользователей из БД. Пока шло чтение, мог прийти ответ сервера: пришедших
    /// с ним пользователей не затирает, а тех, кого сервер назвал ненайденными, не возвращает из БД.
    /// В копию не передаёт — это делает `loadUsers` перед возвратом.
    /// - Parameter ids: идентификаторы пользователей, которых нет в памяти.
    private func loadFromStorage(ids: [Int]) async {
        guard !ids.isEmpty else { return }
        do {
            for stored in try await userStorage.findStored(byIds: ids) {
                let id = stored.user.userId
                guard entriesById[id] == nil, notFoundRevisions[id] == nil else { continue }
                entriesById[id] = Entry(stored: stored, revision: nextRevision())
            }
        } catch {
            Logger.storage.error("Не удалось прочитать пользователей из БД: \(String(describing: error), privacy: .public)")
        }
    }

    /// Запускает запросы пользователей, которых ещё не запрашивают, пачками по `UsersEndpoint.batchLimit`.
    /// - Parameter ids: идентификаторы пользователей.
    /// - Returns: запросы — новые и уже идущие, — которые покрывают все переданные id.
    @discardableResult
    private func request(ids: [Int]) -> Set<Task<Void, Never>> {
        let idsToRequest = ids.filter { requestsById[$0] == nil }
        for batch in Self.split(idsToRequest, size: UsersEndpoint.batchLimit) {
            let task = Task { await fetch(ids: batch) }
            batch.forEach { requestsById[$0] = task }
        }
        return Set(ids.compactMap { requestsById[$0] })
    }

    /// Запрашивает одну пачку пользователей с сервера, кладёт их в память, передаёт в копию и сохраняет в БД.
    /// Запрос считается идущим, пока результат не передан в копию: дождавшийся его вызывающий уже видит имена.
    /// - Parameter ids: не больше `UsersEndpoint.batchLimit` идентификаторов.
    private func fetch(ids: [Int]) async {
        let batch: UsersBatch
        do {
            batch = try await usersService.fetchUsers(ids: ids)
        } catch {
            ids.forEach { requestsById[$0] = nil }
            Logger.users.error("Не удалось загрузить пользователей: \(String(describing: error), privacy: .public)")
            return
        }
        let cachedAt = now()
        for user in batch.users {
            entriesById[user.userId] = Entry(stored: StoredUser(user: user, cachedAt: cachedAt), revision: nextRevision())
        }
        for id in batch.notFoundIds {
            entriesById[id] = nil
            notFoundRevisions[id] = nextRevision()
        }
        await publish(ids: ids)
        ids.forEach { requestsById[$0] = nil }
        await save(batch.users, cachedAt: cachedAt)
    }

    /// Передаёт в копию текущее состояние пользователей и дожидается применения. Пользователи без данных
    /// и без отметки «не найден» не передаются — в копии они и так `.pending`.
    /// - Parameter ids: идентификаторы пользователей.
    private func publish(ids: [Int]) async {
        var states: [Int: VersionedUserState] = [:]
        for id in ids {
            if let entry = entriesById[id] {
                states[id] = VersionedUserState(state: .loaded(entry.stored.user), revision: entry.revision)
            } else if let revision = notFoundRevisions[id] {
                states[id] = VersionedUserState(state: .notFound, revision: revision)
            }
        }
        guard !states.isEmpty else { return }
        await snapshot.apply(states)
    }

    /// Сохраняет пользователей в БД. Ошибка записи не мешает показать их из памяти.
    /// - Parameters:
    ///   - users: пользователи из ответа сервера.
    ///   - cachedAt: когда они получены.
    private func save(_ users: [User], cachedAt: Date) async {
        do {
            try await userStorage.save(users: users, cachedAt: cachedAt)
        } catch {
            Logger.storage.error("Не удалось сохранить пользователей в БД: \(String(describing: error), privacy: .public)")
        }
    }

    /// Убирает повторы, сохраняя порядок первого появления.
    /// - Parameter ids: идентификаторы с возможными повторами.
    private static func unique(_ ids: [Int]) -> [Int] {
        var seen: Set<Int> = []
        return ids.filter { seen.insert($0).inserted }
    }

    /// Делит список на пачки не длиннее `size`.
    /// - Parameters:
    ///   - ids: идентификаторы.
    ///   - size: максимальный размер пачки.
    private static func split(_ ids: [Int], size: Int) -> [[Int]] {
        stride(from: 0, to: ids.count, by: size).map { Array(ids[$0..<min($0 + size, ids.count)]) }
    }
}

private extension Logger {
    /// Лог ошибок загрузки пользователей в кэш: пользователю не показываются — вместо имени остаётся заглушка.
    static let users = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Chatik", category: "Users")
}
