//
//  SignupValidatorTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class SignupValidatorTests: XCTestCase {
    private let sut = SignupValidator()

    // MARK: - Имя

    /// Кейс: имена из букв разных алфавитов, цифр, дефиса, подчёркивания и пробела.
    /// Ожидание: все валидны.
    func test_validateName_acceptsAllowedCharacters() {
        let names = [
            "Иван",
            "John Doe",
            "Anna-Maria_2",
            "李雷",
            "Ünsal 7",
        ]

        for name in names {
            XCTAssertNil(sut.validateName(name), name)
        }
    }

    /// Кейс: пустая строка и строка из одних пробелов.
    /// Ожидание: ошибка `.empty`.
    func test_validateName_blank_returnsEmpty() {
        XCTAssertEqual(sut.validateName(""), .empty)
        XCTAssertEqual(sut.validateName("   "), .empty)
    }

    /// Кейс: имя содержит знаки препинания, точку, emoji или символ `@`.
    /// Ожидание: ошибка `.invalidCharacters`.
    func test_validateName_forbiddenCharacters_returnsInvalidCharacters() {
        let names = [
            "Ivan!",
            "Ivan.Petrov",
            "Ivan😀",
            "ivan@mail",
        ]

        for name in names {
            XCTAssertEqual(sut.validateName(name), .invalidCharacters, name)
        }
    }

    // MARK: - Логин

    /// Кейс: логины из латиницы, цифр и подчёркивания.
    /// Ожидание: все валидны.
    func test_validateLogin_acceptsAllowedCharacters() {
        let logins = [
            "ivan",
            "Ivan_Petrov",
            "user_123",
            "_",
            "A1",
        ]

        for login in logins {
            XCTAssertNil(sut.validateLogin(login), login)
        }
    }

    /// Кейс: пустой логин.
    /// Ожидание: ошибка `.empty`.
    func test_validateLogin_empty_returnsEmpty() {
        XCTAssertEqual(sut.validateLogin(""), .empty)
    }

    /// Кейс: логин с кириллицей, пробелом, дефисом, точкой или только из пробелов.
    /// Ожидание: ошибка `.invalidCharacters`.
    func test_validateLogin_forbiddenCharacters_returnsInvalidCharacters() {
        let logins = [
            "иван",
            "ivan petrov",
            "ivan-petrov",
            "ivan.petrov",
            " ",
        ]

        for login in logins {
            XCTAssertEqual(sut.validateLogin(login), .invalidCharacters, login)
        }
    }

    // MARK: - Пароль

    /// Кейс: пароли с латинской заглавной, строчной, цифрой и длиной ≥ 8, в т.ч. с кириллицей и пунктуацией.
    /// Ожидание: все валидны.
    func test_validatePassword_acceptsStrongPasswords() {
        let passwords = [
            "Password1",
            "Aa1!?.,;",
            "Пароль-Aa1",
            "aaaaaaA1",
            "A1bcdefg",
        ]

        for password in passwords {
            XCTAssertNil(sut.validatePassword(password), password)
        }
    }

    /// Кейс: пароль короче 8 символов, даже если остальные требования выполнены.
    /// Ожидание: ошибка `.tooShort` (проверяется первой).
    func test_validatePassword_short_returnsTooShort() {
        XCTAssertEqual(sut.validatePassword("Aa1"), .tooShort)
        XCTAssertEqual(sut.validatePassword("Abcdef1"), .tooShort)
        XCTAssertEqual(sut.validatePassword(""), .tooShort)
    }

    /// Кейс: нет заглавной латинской буквы (в т.ч. когда заглавная — кириллическая).
    /// Ожидание: ошибка `.missingUppercase`.
    func test_validatePassword_noLatinUppercase_returnsMissingUppercase() {
        XCTAssertEqual(sut.validatePassword("password1"), .missingUppercase)
        XCTAssertEqual(sut.validatePassword("Пassword1"), .missingUppercase)
    }

    /// Кейс: нет строчной латинской буквы (в т.ч. когда строчная — кириллическая).
    /// Ожидание: ошибка `.missingLowercase`.
    func test_validatePassword_noLatinLowercase_returnsMissingLowercase() {
        XCTAssertEqual(sut.validatePassword("PASSWORD1"), .missingLowercase)
        XCTAssertEqual(sut.validatePassword("PASSWORDп1"), .missingLowercase)
    }

    /// Кейс: нет цифры (в т.ч. когда есть только не-ASCII цифры).
    /// Ожидание: ошибка `.missingDigit`.
    func test_validatePassword_noDigit_returnsMissingDigit() {
        XCTAssertEqual(sut.validatePassword("Password!"), .missingDigit)
        XCTAssertEqual(sut.validatePassword("Password٣٣"), .missingDigit)
    }

    // MARK: - Форма

    /// Кейс: все поля валидны / одно из полей невалидно.
    /// Ожидание: `true` только когда валидны все три.
    func test_isFormValid_requiresAllFieldsValid() {
        XCTAssertTrue(sut.isFormValid(name: "Иван", login: "ivan", password: "Password1"))
        XCTAssertFalse(sut.isFormValid(name: "", login: "ivan", password: "Password1"))
        XCTAssertFalse(sut.isFormValid(name: "Иван", login: "иван", password: "Password1"))
        XCTAssertFalse(sut.isFormValid(name: "Иван", login: "ivan", password: "password"))
    }
}
