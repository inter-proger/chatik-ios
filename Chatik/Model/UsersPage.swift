//
//  UsersPage.swift
//  Chatik
//

import Foundation

/// Страница списка пользователей — ответ `/users/getList`.
struct UsersPage: Decodable, Equatable {
    let users: [User]
    /// `userId` последнего пользователя страницы; передаётся в `maxId` за следующей страницей.
    /// `nil`, если список пуст.
    let nextMaxId: Int?
}
