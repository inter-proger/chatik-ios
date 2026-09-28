//
//  User+Stub.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

extension User {
    /// Пользователь без аватара — типовой элемент ответа `/users/getList`.
    static let stub = User(userId: 1, login: "ivan", name: "Ivan Petrov", avatar: nil)
}
