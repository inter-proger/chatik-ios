//
//  AvatarSourcePickerViewModifier.swift
//  Chatik
//

import PhotosUI
import SwiftUI

/// Пикеры изображения для аватара: системная галерея (`PhotosPicker`) и камера.
/// Какой из них показан, определяется значением `presentedSource`.
struct AvatarSourcePickerViewModifier: ViewModifier {
    @Binding var presentedSource: AvatarSource?
    /// Вызывается с выбранным изображением: снимок с камеры или оригинальный файл из галереи.
    let onPick: (PickedImage) -> Void
    /// Вызывается, если выбранный в галерее файл не удалось получить в поддерживаемом формате.
    let onFailure: () -> Void

    @State private var selectedItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $presentedSource.isPresent(.gallery), selection: $selectedItem, matching: .images)
            .fullScreenCover(isPresented: $presentedSource.isPresent(.camera)) {
                CameraPicker(onPick: { onPick(.image($0)) })
                    .ignoresSafeArea()
            }
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
    }

    /// Получает выбранный в галерее файл копией во временной директории и передаёт его наружу без декодирования —
    /// на сервер уходит оригинал, без перекодирования и уменьшения.
    /// - Parameter item: элемент, выбранный в `PhotosPicker`.
    private func load(_ item: PhotosPickerItem) async {
        defer { selectedItem = nil }
        guard let picked = try? await item.loadTransferable(type: PickedImageFile.self) else {
            onFailure()
            return
        }
        onPick(.file(picked.file))
    }
}

/// Файл изображения из `PhotosPicker` в формате, который принимает сервер. Оригинал JPEG, PNG или WebP копируется
/// как есть; HEIC система сама отдаёт как JPEG. Формат вне списка (GIF и т.п.) — ошибка `loadTransferable`.
private struct PickedImageFile: Transferable {
    let file: ImageFile

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: ImageMIMEType.jpeg.utType) { try Self(copying: $0, type: .jpeg) }
        FileRepresentation(importedContentType: ImageMIMEType.png.utType) { try Self(copying: $0, type: .png) }
        FileRepresentation(importedContentType: ImageMIMEType.webp.utType) { try Self(copying: $0, type: .webp) }
    }

    /// Копирует полученный файл во временную директорию: за пределами замыкания импорта исходный файл недоступен.
    /// - Parameters:
    ///   - received: файл, предоставленный системой на время импорта.
    ///   - type: формат, в котором файл был запрошен.
    private init(copying received: ReceivedTransferredFile, type: ImageMIMEType) throws {
        let url = ImageFile.makeTemporaryURL(type: type)
        try FileManager.default.copyItem(at: received.file, to: url)
        file = ImageFile(url: url, type: type)
    }
}

extension View {
    /// Подключает пикеры галереи и камеры для выбора аватара.
    /// - Parameters:
    ///   - presentedSource: какой пикер показан; `nil` — ни один.
    ///   - onPick: обработчик выбранного изображения.
    ///   - onFailure: обработчик ошибки получения выбранного файла.
    func avatarSourcePickers(
        presentedSource: Binding<AvatarSource?>,
        onPick: @escaping (PickedImage) -> Void,
        onFailure: @escaping () -> Void
    ) -> some View {
        modifier(AvatarSourcePickerViewModifier(presentedSource: presentedSource, onPick: onPick, onFailure: onFailure))
    }
}
