//
//  UploadProgressDelegate.swift
//  Chatik
//

import Foundation

/// Делегат задачи `URLSession`, который переводит отправленные байты в долю от 0 до 1
/// и передаёт её в `onProgress`. Вызывается на очереди делегатов сессии, не на main.
final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: @Sendable (Double) -> Void

    /// - Parameter onProgress: получает долю отправленного тела запроса; последнее значение — `1`.
    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(Double(totalBytesSent) / Double(totalBytesExpectedToSend), 1))
    }
}
