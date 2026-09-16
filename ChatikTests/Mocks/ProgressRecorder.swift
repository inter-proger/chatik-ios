//
//  ProgressRecorder.swift
//  ChatikTests
//

import Foundation

/// Потокобезопасно копит значения прогресса из `@Sendable`-обработчика `onProgress`.
final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    var values: [Double] {
        lock.withLock { storage }
    }

    func append(_ value: Double) {
        lock.withLock { storage.append(value) }
    }
}
