//
//  InAppNotificationTimingTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class InAppNotificationTimingTests: XCTestCase {
    /// Время показа ошибки с текстом заданной длины без VoiceOver.
    /// - Parameter length: длина текста.
    private func errorDuration(length: Int) -> Duration {
        InAppNotificationTiming.duration(
            for: .error(message: String(repeating: "а", count: length)),
            isVoiceOverRunning: false
        )
    }

    /// Кейс: короткие тексты ошибки — до `shortTextLength` символов включительно.
    /// Ожидание: базовое время показа.
    func test_shortText_usesBaseDuration() {
        let lengths = [
            0,
            1,
            InAppNotificationTiming.shortTextLength,
        ]

        for length in lengths {
            XCTAssertEqual(errorDuration(length: length), InAppNotificationTiming.baseDuration, "\(length)")
        }
    }

    /// Кейс: текст ошибки на 20 символов длиннее короткого.
    /// Ожидание: к базовому времени добавлено время за каждый лишний символ.
    func test_longText_addsPerCharacterDuration() {
        let duration = errorDuration(length: InAppNotificationTiming.shortTextLength + 20)

        XCTAssertEqual(duration, InAppNotificationTiming.baseDuration + InAppNotificationTiming.perExtraCharacter * 20)
    }

    /// Кейс: очень длинный текст ошибки.
    /// Ожидание: время показа ограничено верхней границей.
    func test_veryLongText_isCappedByMaxDuration() {
        XCTAssertEqual(errorDuration(length: 1000), InAppNotificationTiming.maxDuration)
    }

    /// Кейс: включён VoiceOver, текст короткий и очень длинный.
    /// Ожидание: в обоих случаях — время показа для VoiceOver.
    func test_voiceOver_usesVoiceOverDuration() {
        let messages = [
            "Ошибка",
            String(repeating: "а", count: 1000),
        ]

        for message in messages {
            let duration = InAppNotificationTiming.duration(for: .error(message: message), isVoiceOverRunning: true)
            XCTAssertEqual(duration, InAppNotificationTiming.voiceOverDuration, "\(message.count)")
        }
    }
}
