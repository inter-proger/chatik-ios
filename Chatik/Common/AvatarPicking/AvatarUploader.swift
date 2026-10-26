//
//  AvatarUploader.swift
//  Chatik
//

import Foundation
import Observation

/// Подготовка и загрузка изображения для аватара с прогрессом — общая часть профиля и создания группы
/// (`docs/profile-and-avatar.md`, `docs/group-chats.md`, решение 10). Что делать с загруженным файлом (назначить
/// аватаром профиля или запомнить для группы), решает владелец.
///
/// `progress`: `nil` — загрузка не идёт; 0 — файл готовится; доля отправленного; 1 — файл отправлен. Владелец
/// сбрасывает прогресс (`finish()`), когда закончит свой последний шаг.
@MainActor
@Observable
final class AvatarUploader {
    private(set) var progress: Double?

    @ObservationIgnored private let filesService: FilesServiceProtocol
    @ObservationIgnored let imageFileStore: ImageFileStoreProtocol

    /// `true`, пока файл готовится, отправляется и владелец не вызвал `finish()`.
    var isUploading: Bool {
        progress != nil
    }

    /// - Parameters:
    ///   - filesService: загрузка файлов.
    ///   - imageFileStore: временные файлы изображений.
    init(filesService: FilesServiceProtocol, imageFileStore: ImageFileStoreProtocol) {
        self.filesService = filesService
        self.imageFileStore = imageFileStore
    }

    /// Имя загружаемого файла по его формату.
    /// - Parameter type: формат изображения.
    static func filename(for type: ImageMIMEType) -> String {
        "avatar.\(type.fileExtension)"
    }

    /// Готовит файл изображения и загружает его на сервер как есть. Временный файл удаляется сразу после
    /// подготовки — даже если задача отменится до начала загрузки. После отправки прогресс — 1 до `finish()`.
    /// - Parameter image: снимок с камеры или файл из галереи.
    /// - Returns: загруженный файл.
    /// - Throws: `ImageFileStoreError` — изображение не подготовилось; ошибки сети и `CancellationError`.
    func upload(_ image: PickedImage) async throws -> RemoteFile {
        progress = 0
        let file = try await imageFileStore.storeForUpload(image)
        defer { imageFileStore.remove(file) }
        try Task.checkCancellation()
        let remoteFile = try await filesService.uploadImage(
            file: file,
            filename: Self.filename(for: file.type),
            onProgress: { [weak self] value in
                // Колбэк приходит не на main: обновление состояния — отдельной задачей на main actor.
                Task { @MainActor [weak self] in self?.didSendBytes(value) }
            }
        )
        // Отправка завершена независимо от того, какие значения успел доставить делегат сессии.
        progress = 1
        return remoteFile
    }

    /// Загрузка и последний шаг владельца закончены (успехом, ошибкой или отменой): прогресс сбрасывается.
    func finish() {
        progress = nil
    }

    /// Удаляет временный файл изображения, от загрузки которого отказались (выбрано во время загрузки).
    /// - Parameter image: изображение.
    func discard(_ image: PickedImage) {
        guard case .file(let file) = image else { return }
        imageFileStore.remove(file)
    }

    /// Обновляет прогресс отправки. Порядок доставки на main не гарантирован, поэтому прогресс только растёт;
    /// вне загрузки поздний колбэк игнорируется.
    /// - Parameter value: доля отправленных данных от 0 до 1.
    func didSendBytes(_ value: Double) {
        guard let current = progress else { return }
        progress = max(current, value)
    }
}
