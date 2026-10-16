//
//  UnsentMessagePreviewProvidingMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок превью неотправленных сообщений для списка чатов: тексты задаёт тест, они наблюдаются через Observation.
@MainActor
@Observable
final class UnsentMessagePreviewProvidingMock: UnsentMessagePreviewProviding {
    /// Тексты последних неотправленных сообщений по `conversationId`.
    var lastFailedTexts: [Int: String] = [:]

    func lastFailedText(for conversationId: Int) -> String? {
        lastFailedTexts[conversationId]
    }
}
