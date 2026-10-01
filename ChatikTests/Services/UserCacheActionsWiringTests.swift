//
//  UserCacheActionsWiringTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

/// Кэш пользователей в сборке, как в приложении: настоящие `NetworkService`, `UsersService`, `APIActionDispatcher`
/// и `UserCacheService`, ответы сервера — через `URLProtocolStub`. Проверяет то, что не видно на моках по отдельности:
/// кэш ходит в сеть через тот же сетевой слой, который передаёт ему actions.
@MainActor
final class UserCacheActionsWiringTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    /// Кейс: ответ `/users/getBatch` сам содержит action `users` с теми же пользователями.
    /// Ожидание: загрузка завершается, пользователь `.loaded` — action из ответа `getBatch` не заставляет
    /// загрузку ждать саму себя.
    func test_loadUsers_getBatchResponseWithUsersAction_doesNotHang() async {
        stubResponse(
            #"""
            {"status":1,
             "response":{"users":[{"userId":2,"login":"petr","name":"Petr","avatar":null}],"notFoundIds":[]},
             "actions":[{"type":"users","data":{"userIds":[2]}}]}
            """#
        )
        let cache = makeCache()
        var isLoaded = false

        Task {
            await cache.loadUsers(ids: [2])
            isLoaded = true
        }
        await waitUntil { isLoaded }

        XCTAssertEqual(cache.user(id: 2), .loaded(User(userId: 2, login: "petr", name: "Petr", avatar: nil)))
    }

    // MARK: - Helpers

    /// Собирает кэш поверх стаба `URLSession`, связывая диспетчер actions так же, как `DIContainer`.
    /// Лимит ожидания диспетчера больше, чем тест ждёт загрузки: иначе зависание прерывалось бы лимитом
    /// и выглядело бы как медленная, но успешная загрузка.
    private func makeCache() -> UserCacheService {
        let dispatcher = APIActionDispatcher(usersWaitLimit: .seconds(30))
        let networkService = NetworkService(
            session: URLProtocolStub.makeSession(),
            baseURL: URL(string: "http://localhost:8080")!,
            cookieStorage: HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "ChatikTests.\(UUID().uuidString)"),
            onActions: { await dispatcher.dispatch($0) }
        )
        let cache = UserCacheService(
            usersService: UsersService(networkService: networkService),
            userStorage: UserStorageService(container: CoreDataStack.makeContainer(inMemory: true))
        )
        dispatcher.userCache = cache
        return cache
    }

    /// Отвечает на любой запрос заданным телом со статусом 200.
    /// - Parameter json: тело ответа.
    private func stubResponse(_ json: String) {
        URLProtocolStub.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
    }
}
