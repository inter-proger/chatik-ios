//
//  SignupValidator.swift
//  Chatik
//

import Foundation

protocol SignupValidatorProtocol {
    /// Проверяет имя: не пустое; буквы любого алфавита, цифры, `-`, `_`, пробел.
    func validateName(_ name: String) -> NameValidationError?
    /// Проверяет логин: не пустой; латинские буквы, цифры, `_`.
    func validateLogin(_ login: String) -> LoginValidationError?
    /// Проверяет пароль: не менее 8 символов, есть заглавная и строчная латинские буквы и цифра.
    func validatePassword(_ password: String) -> PasswordValidationError?
    /// `true`, если все поля формы регистрации валидны.
    func isFormValid(name: String, login: String, password: String) -> Bool
}

final class SignupValidator: SignupValidatorProtocol {
    private static let minPasswordLength = 8
    private static let nameRegex = /^[\p{L}0-9_\- ]+$/
    private static let loginRegex = /^[A-Za-z0-9_]+$/

    /// Проверяет имя. Строка из одних пробелов считается пустой.
    /// - Parameter name: введённое имя.
    func validateName(_ name: String) -> NameValidationError? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return .empty }
        guard name.wholeMatch(of: Self.nameRegex) != nil else { return .invalidCharacters }
        return nil
    }

    /// Проверяет логин.
    /// - Parameter login: введённый логин.
    func validateLogin(_ login: String) -> LoginValidationError? {
        guard !login.isEmpty else { return .empty }
        guard login.wholeMatch(of: Self.loginRegex) != nil else { return .invalidCharacters }
        return nil
    }

    /// Проверяет пароль. Символы других алфавитов и знаки препинания допускаются.
    /// - Parameter password: введённый пароль.
    func validatePassword(_ password: String) -> PasswordValidationError? {
        guard password.count >= Self.minPasswordLength else { return .tooShort }
        guard password.contains(where: { $0.isASCII && $0.isUppercase }) else { return .missingUppercase }
        guard password.contains(where: { $0.isASCII && $0.isLowercase }) else { return .missingLowercase }
        guard password.contains(where: { $0.isASCII && $0.isNumber }) else { return .missingDigit }
        return nil
    }

    /// Проверяет всю форму регистрации.
    /// - Parameters:
    ///   - name: имя.
    ///   - login: логин.
    ///   - password: пароль.
    func isFormValid(name: String, login: String, password: String) -> Bool {
        validateName(name) == nil && validateLogin(login) == nil && validatePassword(password) == nil
    }
}
