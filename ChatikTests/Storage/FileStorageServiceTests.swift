//
//  FileStorageServiceTests.swift
//  ChatikTests
//

import CoreData
import XCTest
@testable import Chatik

final class FileStorageServiceTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var sut: FileStorageService!

    override func setUp() {
        super.setUp()
        container = CoreDataStack.makeContainer(inMemory: true)
        sut = FileStorageService(container: container)
    }

    override func tearDown() {
        sut = nil
        container = nil
        super.tearDown()
    }

    /// Кейс: сохранён файл со всеми полями, включая уменьшенную копию.
    /// Ожидание: из БД читается тот же файл без потерь.
    func test_save_roundTripsAllFields() async throws {
        try await sut.save(file: .stub)

        let found = try await sut.find(byId: RemoteFile.stub.fileId)

        XCTAssertEqual(found, .stub)
    }

    /// Кейс: файл сохранён, затем сохранён повторно с тем же `fileId` и новым именем.
    /// Ожидание: в БД одна запись с обновлённым именем.
    func test_save_existingId_updatesRecord() async throws {
        try await sut.save(file: .stub)

        try await sut.save(file: makeFile(id: RemoteFile.stub.fileId, filename: "new.jpg"))

        let files = try await sut.fetchAll()
        XCTAssertEqual(files.map(\.filename), ["new.jpg"])
    }

    /// Кейс: батч из трёх файлов, два из них с одинаковым `fileId`.
    /// Ожидание: сохранены две записи, для повторного `fileId` — последняя версия.
    func test_saveFiles_duplicateIds_collapsesToLast() async throws {
        let files = [
            makeFile(id: 1, filename: "a.jpg"),
            makeFile(id: 2, filename: "b.jpg"),
            makeFile(id: 1, filename: "c.jpg"),
        ]

        try await sut.save(files: files)

        let saved = try await sut.fetchAll().sorted { $0.fileId < $1.fileId }
        XCTAssertEqual(saved.map(\.filename), ["c.jpg", "b.jpg"])
    }

    /// Кейс: в БД есть запись без обязательного поля `url`.
    /// Ожидание: выборка её пропускает, остальные записи возвращаются.
    func test_fetchAll_skipsBrokenRecords() async throws {
        try await sut.save(file: makeFile(id: 1, filename: "a.jpg"))
        try await container.performWrite { context in
            let broken = FileEntity(context: context)
            broken.fileId = 2
            broken.type = RemoteFileType.image.rawValue
            broken.filename = "b.jpg"
            broken.fileExtension = "jpg"
            try context.save()
        }

        let files = try await sut.fetchAll()

        XCTAssertEqual(files.map(\.fileId), [1])
    }

    /// Кейс: файл сохранён, затем удалён по `fileId`.
    /// Ожидание: файла больше нет в БД.
    func test_delete_removesRecord() async throws {
        try await sut.save(file: .stub)

        try await sut.delete(byId: RemoteFile.stub.fileId)

        let found = try await sut.find(byId: RemoteFile.stub.fileId)
        XCTAssertNil(found)
    }

    /// Кейс: `find` и `delete` по `fileId`, которого нет в БД.
    /// Ожидание: не падают; `find` возвращает `nil`, остальные записи не тронуты.
    func test_findAndDelete_missingId_doNothing() async throws {
        try await sut.save(file: .stub)

        let found = try await sut.find(byId: 999)
        try await sut.delete(byId: 999)

        let files = try await sut.fetchAll()
        XCTAssertNil(found)
        XCTAssertEqual(files, [.stub])
    }

    // MARK: - Helpers

    /// Изображение без уменьшенной копии с указанными идентификатором и именем.
    /// - Parameters:
    ///   - id: идентификатор файла.
    ///   - filename: имя файла.
    private func makeFile(id: Int, filename: String) -> RemoteFile {
        RemoteFile(
            fileId: id,
            type: .image,
            url: URL(string: "http://localhost:8080/static/uploads/\(filename)")!,
            size: 100,
            filename: filename,
            fileExtension: "jpg",
            smallURL: nil
        )
    }
}
