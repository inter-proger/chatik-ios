//
//  APIActionDispatcherTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class APIActionDispatcherTests: XCTestCase {
    /// Кейс: из ответа пришёл action `users`, кэш загружает пользователей.
    /// Ожидание: id переданы кэшу, и `dispatch` завершается только после того, как кэш закончил загрузку.
    func test_dispatch_usersAction_waitsForCache() async {
        let userCache = UserCacheServiceMock()
        let gate = Gate()
        userCache.onLoad = { await gate.wait() }
        let sut = APIActionDispatcher()
        sut.userCache = userCache
        var isDispatched = false

        let dispatch = Task {
            await sut.dispatch([.users(userIds: [1, 2])])
            isDispatched = true
        }
        await yieldUntil { gate.isWaiting }
        XCTAssertFalse(isDispatched)
        gate.open()
        await dispatch.value

        XCTAssertTrue(isDispatched)
        XCTAssertEqual(userCache.loadRequests, [[1, 2]])
    }

    /// Кейс: из ответа пришёл action `users`, а загрузка пользователей не заканчивается дольше лимита ожидания.
    /// Ожидание: `dispatch` возвращается по истечении лимита, не дожидаясь загрузки, — ответ экрану не задерживается;
    /// сама загрузка не прерывается и завершается позже.
    func test_dispatch_slowUsersLoad_returnsAfterWaitLimit() async {
        let userCache = UserCacheServiceMock()
        let gate = Gate()
        var isLoadFinished = false
        userCache.onLoad = {
            await gate.wait()
            isLoadFinished = true
        }
        let sut = APIActionDispatcher(usersWaitLimit: .milliseconds(50))
        sut.userCache = userCache

        await sut.dispatch([.users(userIds: [1])])

        XCTAssertTrue(gate.isWaiting)
        XCTAssertFalse(isLoadFinished)
        gate.open()
        await waitUntil { isLoadFinished }
    }

    /// Кейс: action пришёл, когда кэш уже не связан с диспетчером.
    /// Ожидание: ничего не происходит, диспетчер не падает.
    func test_dispatch_withoutCache_doesNothing() async {
        let sut = APIActionDispatcher()

        await sut.dispatch([.users(userIds: [1])])
    }
}
