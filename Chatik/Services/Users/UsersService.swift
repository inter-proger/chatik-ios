//
//  UsersService.swift
//  Chatik
//

import Foundation

/// `Sendable`: сервис вызывают и экраны с main actor, и кэш пользователей из своего actor.
protocol UsersServiceProtocol: Sendable {
    /// Возвращает страницу списка пользователей по возрастанию `userId`.
    /// Параметры передаются явно: значения по умолчанию в требовании протокола Swift не поддерживает,
    /// а объявленные только в реализации через протокол всё равно не работают.
    func fetchUsers(query: String?, maxId: Int?, count: Int?) async throws -> UsersPage
    /// Возвращает пользователей по списку id.
    func fetchUsers(ids: [Int]) async throws -> UsersBatch
}

final class UsersService: UsersServiceProtocol {
    private let networkService: NetworkServiceProtocol

    init(networkService: NetworkServiceProtocol) {
        self.networkService = networkService
    }

    /// Загружает страницу пользователей через `GET /users/getList`.
    /// - Parameters:
    ///   - query: подстрока для фильтра по `name` или `login` без учёта регистра; `nil` — без фильтра.
    ///     Пустая строка и строка из пробелов равносильны `nil`: очищенное поле поиска не уходит в запрос.
    ///   - maxId: отдавать только пользователей с `userId` больше указанного; за следующей страницей
    ///     передаётся `nextMaxId` предыдущего ответа. `nil` — с начала списка.
    ///   - count: размер страницы; `nil` — значение сервера по умолчанию (30), максимум 100.
    /// - Returns: страница пользователей; если их меньше, чем `count`, — страниц больше нет.
    func fetchUsers(query: String?, maxId: Int?, count: Int?) async throws -> UsersPage {
        try await networkService.request(UsersEndpoint.getList(query: Self.filter(from: query), maxId: maxId, count: count))
    }

    /// Загружает пользователей через `GET /users/getBatch`.
    /// - Parameter ids: от 1 до `UsersEndpoint.batchLimit` id; повторы сервер игнорирует. Больше — ошибка 1004,
    ///   поэтому длинный список вызывающий делит на пачки.
    /// - Returns: найденные пользователи и id, для которых пользователя нет.
    func fetchUsers(ids: [Int]) async throws -> UsersBatch {
        try await networkService.request(UsersEndpoint.getBatch(userIds: ids))
    }

    /// Приводит фильтр к виду, в котором его ждёт сервер: пустой ввод — отсутствие параметра.
    /// - Parameter query: содержимое поля поиска.
    private static func filter(from query: String?) -> String? {
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return query
    }
}
