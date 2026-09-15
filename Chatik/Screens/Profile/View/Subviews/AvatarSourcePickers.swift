//
//  AvatarSourcePickers.swift
//  Chatik
//

import PhotosUI
import SwiftUI

/// Пикеры изображения для аватара: системная галерея (`PhotosPicker`) и камера.
/// Какой из них показан, определяется значением `presentedSource`.
struct AvatarSourcePickers: ViewModifier {
    @Binding var presentedSource: AvatarSource?
    /// Вызывается с выбранным изображением: снимок с камеры или содержимое файла из галереи.
    let onPick: (PickedImage) -> Void
    /// Вызывается, если выбранный в галерее файл не удалось прочитать как изображение.
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

    /// Читает содержимое выбранного в галерее файла и передаёт его наружу без декодирования —
    /// в уменьшенном размере его декодирует `ImageEncoder`, чтобы полный кадр не попадал в память.
    /// - Parameter item: элемент, выбранный в `PhotosPicker`.
    private func load(_ item: PhotosPickerItem) async {
        defer { selectedItem = nil }
        guard let picked = try? await item.loadTransferable(type: PickedImageFile.self) else {
            onFailure()
            return
        }
        onPick(.file(picked.data))
    }
}

/// Файл изображения из `PhotosPicker` любого поддерживаемого системой формата (HEIC, JPEG, PNG…).
private struct PickedImageFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { PickedImageFile(data: $0) }
    }
}

extension View {
    /// Подключает пикеры галереи и камеры для выбора аватара.
    /// - Parameters:
    ///   - presentedSource: какой пикер показан; `nil` — ни один.
    ///   - onPick: обработчик выбранного изображения.
    ///   - onFailure: обработчик ошибки чтения выбранного файла.
    func avatarSourcePickers(
        presentedSource: Binding<AvatarSource?>,
        onPick: @escaping (PickedImage) -> Void,
        onFailure: @escaping () -> Void
    ) -> some View {
        modifier(AvatarSourcePickers(presentedSource: presentedSource, onPick: onPick, onFailure: onFailure))
    }
}
