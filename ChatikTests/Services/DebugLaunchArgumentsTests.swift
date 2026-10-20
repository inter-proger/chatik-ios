//
//  DebugLaunchArgumentsTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class DebugLaunchArgumentsTests: XCTestCase {
    private let credentials = DebugLoginCredentials(login: "ivan", password: "Password1")

    /// Кейс: среди аргументов нет ключей debug-входа (только путь к приложению и системные аргументы Xcode).
    /// Ожидание: `nil` — обычный старт.
    func test_parse_withoutKeys_returnsNil() {
        let argumentSets = [
            [],
            ["/path/Chatik"],
            ["/path/Chatik", "-NSDocumentRevisionsDebugMode", "YES"],
        ]

        for arguments in argumentSets {
            XCTAssertNil(DebugLaunchArguments.parse(arguments), "\(arguments)")
        }
    }

    /// Кейс: оба ключа со значениями — в любом порядке и вперемешку с системными аргументами.
    /// Ожидание: логин и пароль разобраны.
    func test_parse_bothKeys_returnsCredentials() {
        let argumentSets = [
            ["/path/Chatik", "-debugLogin", "ivan", "-debugPassword", "Password1"],
            ["/path/Chatik", "-debugPassword", "Password1", "-debugLogin", "ivan"],
            ["/path/Chatik", "-NSDocumentRevisionsDebugMode", "YES", "-debugLogin", "ivan", "-debugPassword", "Password1"],
        ]

        for arguments in argumentSets {
            XCTAssertEqual(DebugLaunchArguments.parse(arguments), .success(credentials), "\(arguments)")
        }
    }

    /// Кейс: логин и пароль с краевыми пробелами.
    /// Ожидание: логин обрезан, пароль передан как есть.
    func test_parse_trimsLoginOnly() {
        let arguments = ["-debugLogin", " ivan ", "-debugPassword", " Password1 "]

        let result = DebugLaunchArguments.parse(arguments)

        XCTAssertEqual(result, .success(DebugLoginCredentials(login: "ivan", password: " Password1 ")))
    }

    /// Кейс: у логина нет значения — ключа нет, ключ последний, значение пустое или из пробелов, вместо значения
    /// следующий ключ.
    /// Ожидание: ошибка `.missingLogin`.
    func test_parse_missingLogin_returnsMissingLogin() {
        let argumentSets = [
            ["-debugPassword", "Password1"],
            ["-debugPassword", "Password1", "-debugLogin"],
            ["-debugLogin", "", "-debugPassword", "Password1"],
            ["-debugLogin", "   ", "-debugPassword", "Password1"],
            ["-debugLogin", "-debugPassword", "Password1"],
        ]

        for arguments in argumentSets {
            XCTAssertEqual(DebugLaunchArguments.parse(arguments), .failure(.missingLogin), "\(arguments)")
        }
    }

    /// Кейс: логин передан, у пароля нет значения — ключа нет, ключ последний, значение пустое, вместо значения
    /// следующий ключ.
    /// Ожидание: ошибка `.missingPassword`.
    func test_parse_missingPassword_returnsMissingPassword() {
        let argumentSets = [
            ["-debugLogin", "ivan"],
            ["-debugLogin", "ivan", "-debugPassword"],
            ["-debugLogin", "ivan", "-debugPassword", ""],
            ["-debugPassword", "-debugLogin", "ivan"],
        ]

        for arguments in argumentSets {
            XCTAssertEqual(DebugLaunchArguments.parse(arguments), .failure(.missingPassword), "\(arguments)")
        }
    }

    /// Кейс: процесс запущен под XCTest (задан `XCTestConfigurationFilePath`), аргументы debug-входа переданы — верные
    /// или неполные.
    /// Ожидание: `nil` — тестовый хост стартует обычно, без входа на сервере.
    func test_parse_underXCTest_returnsNil() {
        let environment = ["XCTestConfigurationFilePath": "/tmp/Chatik.xctestconfiguration"]
        let argumentSets = [
            ["-debugLogin", "ivan", "-debugPassword", "Password1"],
            ["-debugLogin", "ivan"],
        ]

        for arguments in argumentSets {
            XCTAssertNil(DebugLaunchArguments.parse(arguments, environment: environment), "\(arguments)")
        }
    }

    /// Кейс: окружение без `XCTestConfigurationFilePath`, но с другими переменными.
    /// Ожидание: аргументы разбираются как обычно.
    func test_parse_regularEnvironment_parsesArguments() {
        let arguments = ["-debugLogin", "ivan", "-debugPassword", "Password1"]

        let result = DebugLaunchArguments.parse(arguments, environment: ["HOME": "/Users/ivan"])

        XCTAssertEqual(result, .success(credentials))
    }
}
