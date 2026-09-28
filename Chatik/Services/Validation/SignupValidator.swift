//
//  SignupValidator.swift
//  Chatik
//

import Foundation

protocol SignupValidatorProtocol {
    /// Проверяет имя: не пустое; буквы любого алфавита, цифры, `-`, `_`, пробел; не длиннее лимита сервера.
    func validateName(_ name: String) -> NameValidationError?
    /// Проверяет логин: не пустой; латинские буквы, цифры, `_`; не длиннее лимита сервера.
    func validateLogin(_ login: String) -> LoginValidationError?
    /// Проверяет пароль: не менее 8 символов, есть заглавная и строчная латинские буквы и цифра.
    func validatePassword(_ password: String) -> PasswordValidationError?
    /// `true`, если все поля формы регистрации валидны.
    func isFormValid(name: String, login: String, password: String) -> Bool
}

final class SignupValidator: SignupValidatorProtocol {
    private static let minPasswordLength = 8
    /// Лимиты длины на стороне сервера: при превышении он отвечает кодами 1003 и 1001.
    static let maxNameLength = 128
    static let maxLoginLength = 64
    private static let nameRegex = /^[\p{L}0-9_\- ]+$/
    private static let loginRegex = /^[A-Za-z0-9_]+$/

    /// Проверяет имя. Строка из одних пробелов считается пустой; длина считается по символам,
    /// как её считает сервер, — по имени после отсечения краевых пробелов, которое и уходит в запрос.
    /// - Parameter name: введённое имя.
    func validateName(_ name: String) -> NameValidationError? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .empty }
        guard name.wholeMatch(of: Self.nameRegex) != nil else { return .invalidCharacters }
        guard name.count <= Self.maxNameLength else { return .tooLong(maxLength: Self.maxNameLength) }
        return nil
    }

    /// Проверяет логин. Краевые пробелы отсекаются, как и у имени: в запрос уходит логин без них,
    /// поэтому вставленный из буфера `" ivan "` не должен выглядеть как логин с недопустимыми символами.
    /// - Parameter login: введённый логин.
    func validateLogin(_ login: String) -> LoginValidationError? {
        let login = login.trimmingCharacters(in: .whitespaces)
        guard !login.isEmpty else { return .empty }
        guard login.wholeMatch(of: Self.loginRegex) != nil else { return .invalidCharacters }
        guard login.count <= Self.maxLoginLength else { return .tooLong(maxLength: Self.maxLoginLength) }
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
