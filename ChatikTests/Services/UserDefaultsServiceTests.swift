//
//  UserDefaultsServiceTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class UserDefaultsServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: UserDefaultsService!

    override func setUp() {
        super.setUp()
        suiteName = "ChatikTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sut = UserDefaultsService(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// Кейс: пользователь ещё не сохранялся.
    /// Ожидание: `currentUser() == nil`.
    func test_currentUser_initiallyNil() async {
        let user = await sut.currentUser()

        XCTAssertNil(user)
    }

    /// Кейс: пользователь сохранён; сервис пересоздан над тем же `UserDefaults`.
    /// Ожидание: пользователь читается обратно без потерь.
    func test_currentUser_persistsAcrossInstances() async {
        let user = AuthUser(userId: 42, name: "Иван")

        await sut.setCurrentUser(user)
        let reloaded = await UserDefaultsService(defaults: defaults).currentUser()

        XCTAssertEqual(reloaded, user)
    }

    /// Кейс: сохранённому пользователю присваивается `nil`.
    /// Ожидание: запись удалена из `UserDefaults`, сервис отдаёт `nil`.
    func test_setCurrentUser_nil_removesStoredValue() async {
        await sut.setCurrentUser(AuthUser(userId: 1, name: "Ivan"))

        await sut.setCurrentUser(nil)

        let user = await sut.currentUser()
        XCTAssertNil(user)
        XCTAssertNil(defaults.data(forKey: "currentUser"))
    }

    /// Кейс: значение прочитано один раз, затем запись в `UserDefaults` изменена извне (минуя сервис).
    /// Ожидание: сервис продолжает отдавать закэшированное значение — из `defaults` он читает только при первом обращении.
    func test_currentUser_isReadFromDefaultsOnlyOnce() async throws {
        let first = AuthUser(userId: 1, name: "First")
        await sut.setCurrentUser(first)
        let cached = await sut.currentUser()
        XCTAssertEqual(cached, first)

        let external = AuthUser(userId: 2, name: "External")
        defaults.set(try JSONEncoder().encode(external), forKey: "currentUser")

        let stillCached = await sut.currentUser()
        let freshInstance = await UserDefaultsService(defaults: defaults).currentUser()
        XCTAssertEqual(stillCached, first)
        XCTAssertEqual(freshInstance, external)
    }

    /// Кейс: первое обращение происходит после того, как значение уже лежит в `UserDefaults`.
    /// Ожидание: при первом чтении кэш инициализируется из `defaults`.
    func test_currentUser_firstAccess_loadsFromDefaults() async throws {
        let stored = AuthUser(userId: 3, name: "Stored")
        defaults.set(try JSONEncoder().encode(stored), forKey: "currentUser")

        let user = await sut.currentUser()

        XCTAssertEqual(user, stored)
    }

    /// Кейс: конкурентные чтения и записи из множества задач, включая первое (ленивое) чтение.
    /// Ожидание: нет гонок и падений; итоговое значение — одно из записанных, и оно же лежит в `UserDefaults`.
    func test_concurrentAccess_isSerializedByActor() async {
        let iterations = 200
        let service = sut!

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<iterations {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        await service.setCurrentUser(AuthUser(userId: index, name: "User \(index)"))
                    } else {
                        _ = await service.currentUser()
                    }
                }
            }
        }

        let final = await service.currentUser()
        let persisted = await UserDefaultsService(defaults: defaults).currentUser()
        XCTAssertNotNil(final)
        XCTAssertTrue(final.map { $0.userId.isMultiple(of: 2) && $0.userId < iterations } ?? false)
        XCTAssertEqual(persisted, final)
    }
}
