//
//  ConversationRemoval.swift
//  Chatik
//

import Foundation

/// Почему текущий пользователь перестал быть участником переписки — по ней выбирается уведомление.
enum ConversationRemovalReason: Equatable, Sendable {
    /// Вышел сам на этом устройстве: ответ `/groups/leave` или событие о нём, пока запрос выхода в полёте.
    case left
    /// Вышел сам на другом устройстве: событие `memberLeft` без запроса выхода здесь.
    case leftOnOtherDevice
    /// Удалил владелец: событие `membersRemoved`.
    case removed
    /// Причина неизвестна: метка из синхронизации или проверка членства после `5002`.
    case lostAccess
}

/// Удалённая переписка — то, что получают наблюдатели каскада. Переписки в списке к их вызову уже нет.
struct RemovedConversationInfo: Equatable, Sendable {
    let conversationId: Int
    /// Название группы на момент удаления; `nil` — переписка не была загружена или без названия.
    let name: String?
    /// Тип переписки; `nil` — переписка не была загружена.
    let type: ConversationType?
    let reason: ConversationRemovalReason
    /// Версия метки удаления: данные, полученные после неё (повторное добавление), наблюдатели не удаляют.
    let changeVersion: Int
}

/// Наблюдатель удаления переписки (`docs/group-chats.md`, решение 6): каждый удаляет только свои данные о ней.
@MainActor
protocol ConversationRemovalObserver: AnyObject {
    /// Текущий пользователь перестал быть участником переписки; её локальные данные нужно удалить.
    /// - Parameter info: удалённая переписка и причина.
    func conversationWasRemoved(_ info: RemovedConversationInfo) async
}

/// Применение переписки, полученной из REST, — для экранов, которые создают переписку и открывают её.
@MainActor
protocol ConversationApplying: AnyObject {
    /// Применяет полную версию переписки из REST (`createSingle`, `/groups/create`).
    func apply(_ conversation: Conversation)
}

/// Проверка «пропущенного удаления»: метод по известной группе ответил `5002` (или `6002`).
@MainActor
protocol ConversationMembershipVerifying: AnyObject {
    /// Запрашивает переписку через `getBatch`; если её нет — удаляет локально. Склеивает повторы.
    /// - Parameter conversationId: переписка, по которой пришёл `5002`.
    func verifyMembership(conversationId: Int)
}

/// Метки удаления списка переписок — для тех, кто должен отбрасывать устаревшие события о группе.
@MainActor
protocol ConversationRemovalMarks: AnyObject {
    /// Устарела ли версия переписки: есть метка удаления не меньше неё.
    /// - Parameters:
    ///   - conversationId: переписка.
    ///   - changeVersion: версия пользователя из события.
    func isRemoved(conversationId: Int, changeVersion: Int) -> Bool
}

extension NetworkError {
    /// Ответ означает, что пользователь, возможно, больше не участник переписки: `5002` — переписка не найдена
    /// или пользователь в ней не состоит, `6002` — блок сообщений не найден.
    var indicatesLostMembership: Bool {
        guard case let .api(code) = self else { return false }
        return code == Code.conversationNotFound || code == Code.messageBlockNotFound
    }
}

extension Error {
    /// `NetworkError.indicatesLostMembership` для любой ошибки.
    var indicatesLostMembership: Bool {
        (self as? NetworkError)?.indicatesLostMembership ?? false
    }
}
