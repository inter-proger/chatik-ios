//
//  APIActionDispatcher.swift
//  Chatik
//

import Foundation

/// Передаёт указания клиенту (`actions` из ответов сервера) сервисам, которые их выполняют.
/// Сетевой слой отдаёт сюда actions каждого успешного ответа и ждёт `dispatch`, прежде чем вернуть данные
/// вызывающему: так экран обычно получает ответ, когда всё нужное для его показа уже на месте.
@MainActor
final class APIActionDispatcher {
    /// Исполнитель action `users`. Связывается после сборки: кэш сам ходит в сеть через сетевой слой,
    /// которому нужен этот диспетчер, — `weak`, чтобы не замыкать цикл ссылок.
    weak var userCache: UserCacheServiceProtocol?

    /// Сколько ответ ждёт загрузки упомянутых пользователей.
    private let usersWaitLimit: Duration

    /// - Parameter usersWaitLimit: сколько ответ ждёт загрузки упомянутых пользователей. Дольше ждать не стоит:
    ///   медленный или зависший `/users/getBatch` задерживал бы любой ответ — список чатов, отправку сообщения,
    ///   выход из аккаунта, — а экраны и так показывают заглушку вместо незагруженного пользователя.
    init(usersWaitLimit: Duration = .seconds(2)) {
        self.usersWaitLimit = usersWaitLimit
    }

    /// Выполняет actions по очереди. Для `users` ждёт загрузки пользователей, которых нет в кэше, но не дольше
    /// `usersWaitLimit`: дальше загрузка продолжается в фоне, а экран обновится, когда она закончится.
    /// Устаревших пользователей кэш обновляет в фоне сам, не задерживая ответ.
    /// - Parameter actions: actions из ответа сервера.
    func dispatch(_ actions: [APIAction]) async {
        for action in actions {
            switch action {
            case let .users(userIds):
                guard let userCache else { continue }
                await wait(for: Task { await userCache.loadUsers(ids: userIds) }, atMost: usersWaitLimit)
            }
        }
    }

    /// Ждёт завершения задачи, но не дольше лимита; по истечении лимита задача продолжает работу.
    /// - Parameters:
    ///   - task: задача, завершения которой ждём.
    ///   - limit: сколько ждать.
    private func wait(for task: Task<Void, Never>, atMost limit: Duration) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumption = OneTimeResumption(continuation)
            let timer = Task { @MainActor in
                try? await Task.sleep(for: limit)
                resumption.resume()
            }
            Task { @MainActor in
                await task.value
                timer.cancel()
                resumption.resume()
            }
        }
    }
}

/// Продолжение, которое возобновляется только первым из нескольких вызовов `resume()`:
/// ожидание заканчивается либо завершением задачи, либо истечением лимита — что случится раньше.
@MainActor
private final class OneTimeResumption {
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    /// Возобновляет ожидание при первом вызове; повторные вызовы ничего не делают.
    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
