//
//  LoginValidator.swift
//  Chatik
//

import Foundation

protocol LoginValidatorProtocol {
    /// `true`, если логин и пароль непустые (строка из одних пробелов считается пустой).
    func isFormValid(login: String, password: String) -> Bool
}

final class LoginValidator: LoginValidatorProtocol {
    /// Проверяет форму входа: оба поля должны содержать хотя бы один непробельный символ.
    /// - Parameters:
    ///   - login: логин.
    ///   - password: пароль.
    func isFormValid(login: String, password: String) -> Bool {
        !isBlank(login) && !isBlank(password)
    }

    /// `true`, если строка пуста или состоит только из пробелов и переводов строк.
    /// - Parameter value: проверяемая строка.
    private func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
