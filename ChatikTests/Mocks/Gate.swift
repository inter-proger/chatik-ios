//
//  Gate.swift
//  ChatikTests
//

import Foundation

/// Задерживает асинхронный вызов (загрузчик, запрос мока), пока тест его не отпустит: так порядок событий
/// задаётся тестом, а не планировщиком.
@MainActor
final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?

    /// `true`, пока вызывающий ждёт у шлагбаума.
    var isWaiting: Bool {
        continuation != nil
    }

    /// Приостанавливает вызывающего до `open()`.
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    /// Отпускает ждущего.
    func open() {
        continuation?.resume()
        continuation = nil
    }
}
