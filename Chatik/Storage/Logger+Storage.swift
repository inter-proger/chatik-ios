//
//  Logger+Storage.swift
//  Chatik
//

import Foundation
import os

extension Logger {
    /// Лог ошибок локальной БД: они не показываются пользователю, но и не должны теряться молча.
    static let storage = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Chatik", category: "Storage")
}
