//
//  AssetColorTests.swift
//  ChatikTests
//

import UIKit
import XCTest
@testable import Chatik

final class AssetColorTests: XCTestCase {
    /// Кейс: цвет подписи «не отправлено» на синем пузыре в светлой и тёмной теме.
    /// Ожидание: светло-розовый `#FFD6D6` в обеих темах — превью списка чатов этот цвет не меняет.
    func test_failedLabel_keepsBubbleColor() throws {
        let themes: [UIUserInterfaceStyle] = [
            .light,
            .dark,
        ]

        for theme in themes {
            XCTAssertEqual(try rgb(named: "FailedLabel", style: theme), [255, 214, 214], "\(theme.rawValue)")
        }
    }

    /// Кейс: цвет префикса «Не отправлено:» в списке чатов в светлой и тёмной теме.
    /// Ожидание: `#C62828` в светлой и `#FF6B6B` в тёмной — оттенки с контрастом WCAG AA.
    func test_chatListFailedLabel_matchesAcceptedShades() throws {
        XCTAssertEqual(try rgb(named: "ChatListFailedLabel", style: .light), [198, 40, 40])
        XCTAssertEqual(try rgb(named: "ChatListFailedLabel", style: .dark), [255, 107, 107])
    }

    // MARK: - Helpers

    /// Компоненты цвета из каталога приложения в 0...255.
    /// - Parameters:
    ///   - name: имя цвета в `Assets.xcassets`.
    ///   - style: тема.
    private func rgb(named name: String, style: UIUserInterfaceStyle) throws -> [Int] {
        let color = try XCTUnwrap(UIColor(named: name, in: Bundle(for: UserEntity.self), compatibleWith: nil))
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return [red, green, blue].map { Int(($0 * 255).rounded()) }
    }
}
