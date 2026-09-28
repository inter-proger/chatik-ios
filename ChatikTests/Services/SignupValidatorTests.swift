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

    /// Кейс: логин с кириллицей, внутренним пробелом, дефисом или точкой.
    /// Ожидание: ошибка `.invalidCharacters`. Логин из одних пробелов — отдельный кейс: он считается пустым.
    func test_validateLogin_forbiddenCharacters_returnsInvalidCharacters() {
        let logins = [
            "иван",
            "ivan petrov",
            "ivan-petrov",
            "ivan.petrov",
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

    /// Кейс: логин и имя ровно по лимиту сервера.
    /// Ожидание: валидны — граничная длина допустима.
    func test_validate_maxLengthValues_areValid() {
        let login = String(repeating: "a", count: SignupValidator.maxLoginLength)
        let name = String(repeating: "и", count: SignupValidator.maxNameLength)

        XCTAssertNil(sut.validateLogin(login))
        XCTAssertNil(sut.validateName(name))
    }

    /// Кейс: логин длиннее 64 символов.
    /// Ожидание: `.tooLong` с лимитом — сервер ответил бы кодом 1001, запрос не нужен.
    func test_validateLogin_tooLong_returnsTooLong() {
        let login = String(repeating: "a", count: SignupValidator.maxLoginLength + 1)

        XCTAssertEqual(sut.validateLogin(login), .tooLong(maxLength: SignupValidator.maxLoginLength))
    }

    /// Кейс: имя длиннее 128 символов.
    /// Ожидание: `.tooLong` с лимитом — сервер ответил бы кодом 1003, запрос не нужен.
    func test_validateName_tooLong_returnsTooLong() {
        let name = String(repeating: "и", count: SignupValidator.maxNameLength + 1)

        XCTAssertEqual(sut.validateName(name), .tooLong(maxLength: SignupValidator.maxNameLength))
    }

    /// Кейс: логин с краевыми пробелами — например, вставленный из буфера.
    /// Ожидание: валиден — пробелы отсекаются, как и у имени; на сервер уходит логин без них.
    func test_validateLogin_surroundingSpaces_isValid() {
        let logins = [
            " ivan",
            "ivan ",
            "  ivan_1  ",
        ]

        for login in logins {
            XCTAssertNil(sut.validateLogin(login), login)
        }
    }

    /// Кейс: логин из одних пробелов.
    /// Ожидание: считается пустым.
    func test_validateLogin_whitespaceOnly_returnsEmpty() {
        XCTAssertEqual(sut.validateLogin("   "), .empty)
    }

    /// Кейс: имя по лимиту, но с краевыми пробелами — в запрос уходит имя после их отсечения.
    /// Ожидание: валидно — длина считается по тому же значению, что уходит на сервер.
    func test_validateName_maxLengthWithSurroundingSpaces_isValid() {
        let name = "  " + String(repeating: "и", count: SignupValidator.maxNameLength) + "  "

        XCTAssertNil(sut.validateName(name))
    }
}
