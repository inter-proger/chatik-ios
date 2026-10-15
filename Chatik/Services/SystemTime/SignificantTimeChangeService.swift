//
//  SignificantTimeChangeService.swift
//  Chatik
//

import Foundation
import UIKit

/// Значимые изменения системного времени: наступила полночь, сменился часовой пояс, перевели часы.
protocol SignificantTimeChangeServiceProtocol: Sendable {
    /// События изменения; поток завершается, когда подписчик перестаёт его читать.
    func changes() -> AsyncStream<Void>
}

/// События `UIApplication.significantTimeChangeNotification`. Если изменение случилось, пока приложение было
/// в фоне, система присылает уведомление при возврате.
final class SignificantTimeChangeService: SignificantTimeChangeServiceProtocol {
    /// Новый поток событий изменения времени.
    func changes() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await _ in NotificationCenter.default.notifications(named: UIApplication.significantTimeChangeNotification) {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
