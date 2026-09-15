//
//  CameraPicker.swift
//  Chatik
//

import SwiftUI
import UIKit

/// Системная камера (`UIImagePickerController`) для SwiftUI. Показывать только если
/// `UIImagePickerController.isSourceTypeAvailable(.camera)`. Закрывается сама и после съёмки, и по отмене.
struct CameraPicker: UIViewControllerRepresentable {
    /// Вызывается со снятым изображением.
    let onPick: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onPick: (UIImage) -> Void
        private let dismiss: () -> Void

        init(onPick: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onPick = onPick
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Сначала закрыть, потом отдать снимок: обработчик `onPick` может менять состояние,
            // от которого зависит показ пикера, и не должен конкурировать с закрытием.
            dismiss()
            guard let image = info[.originalImage] as? UIImage else { return }
            onPick(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
