//
//  LoginValidatorTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class LoginValidatorTests: XCTestCase {
    private let sut = LoginValidator()

    /// Кейс: логин и пароль содержат хотя бы один непробельный символ (любой, без ограничений формата).
    /// Ожидание: форма валидна.
    func test_isFormValid_nonBlankFields_returnsTrue() {
        XCTAssertTrue(sut.isFormValid(login: "ivan", password: "1"))
        XCTAssertTrue(sut.isFormValid(login: " иван ", password: " x "))
    }

    /// Кейс: одно из полей пустое.
    /// Ожидание: форма невалидна.
    func test_isFormValid_emptyField_returnsFalse() {
        XCTAssertFalse(sut.isFormValid(login: "", password: "Password1"))
        XCTAssertFalse(sut.isFormValid(login: "ivan", password: ""))
    }

    /// Кейс: одно из полей состоит только из пробелов / переводов строк.
    /// Ожидание: поле считается пустым, форма невалидна.
    func test_isFormValid_whitespaceOnlyField_returnsFalse() {
        XCTAssertFalse(sut.isFormValid(login: "   ", password: "Password1"))
        XCTAssertFalse(sut.isFormValid(login: "ivan", password: " \n\t"))
    }
}
