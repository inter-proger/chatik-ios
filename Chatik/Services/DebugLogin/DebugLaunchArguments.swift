//
//  DebugLaunchArguments.swift
//  Chatik
//

#if DEBUG
import Foundation

/// Логин и пароль для debug-входа из аргументов запуска.
struct DebugLoginCredentials: Equatable {
    let login: String
    let password: String
}

/// Ошибка разбора аргументов debug-входа.
enum DebugLaunchArgumentsError: Error, Equatable {
    case missingLogin
    case missingPassword
}

/// Разбор аргументов запуска `-debugLogin <логин> -debugPassword <пароль>` — только в Debug-сборке.
/// Аргументы читаются из процесса, а не из `UserDefaults` (домен `NSArgumentDomain`): прямой доступ к `UserDefaults`
/// запрещён, а явный разбор отличает «аргументов нет» от «передан только один».
enum DebugLaunchArguments {
    static let loginKey = "-debugLogin"
    static let passwordKey = "-debugPassword"
    /// Переменная окружения, которую XCTest задаёт процессу тестового хоста.
    static let testConfigurationKey = "XCTestConfigurationFilePath"

    /// Значение ключа в аргументах.
    private enum ArgumentValue: Equatable {
        /// Ключа нет.
        case absent
        /// Ключ есть, но значения нет: он последний, значение пустое или вместо него идёт следующий ключ.
        case missing
        case value(String)
    }

    /// Достаёт логин и пароль из аргументов запуска. Логин обрезается от краевых пробелов, пароль остаётся как есть.
    /// Под XCTest аргументы игнорируются: Test-действие схемы по умолчанию берёт аргументы Run-действия, и тестовый
    /// хост выполнил бы настоящий выход и вход на сервере, очистив БД во время юнит-тестов.
    /// - Parameters:
    ///   - arguments: аргументы процесса (`ProcessInfo.processInfo.arguments`).
    ///   - environment: окружение процесса (`ProcessInfo.processInfo.environment`).
    /// - Returns: `nil` — ключей нет или процесс запущен под XCTest, обычный старт; иначе данные для входа или ошибка
    ///   разбора.
    static func parse(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) -> Result<DebugLoginCredentials, DebugLaunchArgumentsError>? {
        guard environment[testConfigurationKey] == nil else { return nil }
        let login = argumentValue(for: loginKey, in: arguments)
        let password = argumentValue(for: passwordKey, in: arguments)
        guard login != .absent || password != .absent else { return nil }
        guard case .value(let rawLogin) = login else { return .failure(.missingLogin) }
        let trimmedLogin = rawLogin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLogin.isEmpty else { return .failure(.missingLogin) }
        guard case .value(let password) = password else { return .failure(.missingPassword) }
        return .success(DebugLoginCredentials(login: trimmedLogin, password: password))
    }

    /// Ищет значение ключа — следующий за ним аргумент.
    /// - Parameters:
    ///   - key: ключ вида `-debugLogin`.
    ///   - arguments: аргументы процесса.
    private static func argumentValue(for key: String, in arguments: [String]) -> ArgumentValue {
        guard let keyIndex = arguments.firstIndex(of: key) else { return .absent }
        let valueIndex = arguments.index(after: keyIndex)
        guard valueIndex < arguments.endIndex else { return .missing }
        let value = arguments[valueIndex]
        guard !value.isEmpty, !value.hasPrefix("-") else { return .missing }
        return .value(value)
    }
}
#endif
