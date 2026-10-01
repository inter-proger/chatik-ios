//
//  UserStorageServiceTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

final class UserStorageServiceTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var sut: UserStorageService!

    override func setUp() {
        super.setUp()
        container = CoreDataStack.makeContainer(inMemory: true)
        sut = UserStorageService(container: container)
    }

    override func tearDown() {
        sut = nil
        container = nil
        super.tearDown()
    }

    /// Кейс: сохранён пользователь с аватаром.
    /// Ожидание: из БД читается тот же пользователь с аватаром; аватар попал и в хранилище файлов.
    func test_save_withAvatar_roundTripsUserAndStoresFile() async throws {
        let user = User(userId: 1, login: "ivan", name: "Ivan", avatar: .stub)

        try await sut.save(user: user)

        let found = try await sut.find(byId: 1)
        let files = try await FileStorageService(container: container).fetchAll()
        XCTAssertEqual(found, user)
        XCTAssertEqual(files, [.stub])
    }

    /// Кейс: пользователь сохранён, затем сохранён повторно с тем же `userId`, новым именем и без аватара.
    /// Ожидание: в БД одна запись с обновлённым именем и без аватара.
    func test_save_existingId_updatesRecord() async throws {
        try await sut.save(user: User(userId: 1, login: "ivan", name: "Ivan", avatar: .stub))

        try await sut.save(user: User(userId: 1, login: "ivan", name: "Ivan Petrov", avatar: nil))

        let users = try await sut.fetchAll()
        XCTAssertEqual(users, [User(userId: 1, login: "ivan", name: "Ivan Petrov", avatar: nil)])
    }

    /// Кейс: батч из трёх пользователей, два из них с одинаковым `userId`; у двух пользователей общий аватар.
    /// Ожидание: сохранены две записи (для повторного `userId` — последняя версия), общий аватар — одной записью.
    func test_saveUsers_duplicateIds_collapsesToLast() async throws {
        let users = [
            User(userId: 1, login: "ivan", name: "Ivan", avatar: .stub),
            User(userId: 2, login: "anna", name: "Anna", avatar: .stub),
            User(userId: 1, login: "ivan", name: "Petr", avatar: nil),
        ]

        try await sut.save(users: users)

        let saved = try await sut.fetchAll().sorted { $0.userId < $1.userId }
        let files = try await FileStorageService(container: container).fetchAll()
        XCTAssertEqual(saved.map(\.name), ["Petr", "Anna"])
        XCTAssertEqual(files, [.stub])
    }

    /// Кейс: в БД есть запись без обязательного поля `name`.
    /// Ожидание: выборка её пропускает, остальные записи возвращаются.
    func test_fetchAll_skipsBrokenRecords() async throws {
        try await sut.save(user: .stub)
        try await container.performWrite { context in
            let broken = UserEntity(context: context)
            broken.userId = 2
            broken.login = "anna"
            try context.save()
        }

        let users = try await sut.fetchAll()

        XCTAssertEqual(users, [.stub])
    }

    /// Кейс: у пользователя в БД аватар, в записи которого нет обязательного поля.
    /// Ожидание: пользователь пропускается целиком, а не отдаётся «без аватара».
    func test_fetchAll_brokenAvatar_skipsUser() async throws {
        try await container.performWrite { context in
            let avatar = FileEntity(context: context)
            avatar.fileId = 1
            let user = UserEntity(context: context)
            user.userId = 1
            user.login = "ivan"
            user.name = "Ivan"
            user.avatar = avatar
            try context.save()
        }

        let users = try await sut.fetchAll()

        XCTAssertTrue(users.isEmpty)
    }

    /// Кейс: `find` и `delete` по `userId`, которого нет в БД.
    /// Ожидание: не падают; `find` возвращает `nil`, остальные записи не тронуты.
    func test_findAndDelete_missingId_doNothing() async throws {
        try await sut.save(user: .stub)

        let found = try await sut.find(byId: 999)
        try await sut.delete(byId: 999)

        let users = try await sut.fetchAll()
        XCTAssertNil(found)
        XCTAssertEqual(users, [.stub])
    }

    /// Кейс: пользователь сохранён, затем удалён по `userId`.
    /// Ожидание: пользователя больше нет в БД.
    func test_delete_removesRecord() async throws {
        try await sut.save(user: .stub)

        try await sut.delete(byId: User.stub.userId)

        let found = try await sut.find(byId: User.stub.userId)
        XCTAssertNil(found)
    }

    /// Кейс: пользователи сохранены с временем получения, поиск по списку id, часть которых есть в БД, часть — нет.
    /// Ожидание: возвращены только найденные пользователи вместе с сохранённым временем получения.
    func test_findStored_returnsOnlyStoredUsersWithCachedAt() async throws {
        let anna = User(userId: 2, login: "anna", name: "Anna", avatar: nil)
        let cachedAt = Date(timeIntervalSince1970: 1_790_846_400)
        try await sut.save(users: [.stub, anna], cachedAt: cachedAt)

        let found = try await sut.findStored(byIds: [2, 1, 999])

        XCTAssertEqual(
            found.sorted { $0.user.userId < $1.user.userId },
            [StoredUser(user: .stub, cachedAt: cachedAt), StoredUser(user: anna, cachedAt: cachedAt)]
        )
    }

    /// Кейс: пользователь сохранён повторно — данные получены с сервера заново.
    /// Ожидание: время получения обновлено.
    func test_save_again_updatesCachedAt() async throws {
        try await sut.save(users: [.stub], cachedAt: Date(timeIntervalSince1970: 100))

        try await sut.save(users: [.stub], cachedAt: Date(timeIntervalSince1970: 200))

        let found = try await sut.findStored(byIds: [User.stub.userId])
        XCTAssertEqual(found.map(\.cachedAt), [Date(timeIntervalSince1970: 200)])
    }

    /// Кейс: в БД есть запись пользователя без времени получения.
    /// Ожидание: она читается с `.distantPast` — кэш сочтёт её устаревшей и обновит.
    func test_findStored_withoutCachedAt_isDistantPast() async throws {
        try await container.performWrite { context in
            let entity = UserEntity(context: context)
            entity.userId = 1
            entity.login = "ivan"
            entity.name = "Ivan"
            try context.save()
        }

        let found = try await sut.findStored(byIds: [1])

        XCTAssertEqual(found.map(\.cachedAt), [.distantPast])
    }

    /// Кейс: поиск по пустому списку id.
    /// Ожидание: пустой результат без ошибки.
    func test_findStored_emptyIds_returnsEmpty() async throws {
        try await sut.save(user: .stub)

        let found = try await sut.findStored(byIds: [])

        XCTAssertTrue(found.isEmpty)
    }
}
