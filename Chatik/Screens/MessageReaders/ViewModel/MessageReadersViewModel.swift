//
//  MessageReadersViewModel.swift
//  Chatik
//

import Foundation

/// Состояние листа «Кем прочитано» (`docs/read-receipts.md`, решение 9): участники с указателем не меньше id
/// сообщения, кроме текущего пользователя и автора. Лист живой — указатели наблюдаются в `MemberReadService`,
/// и событие `memberRead` при открытом листе добавляет участника. Порядок — по имени: времени прочтения сервер
/// не отдаёт. Пока указателей нет, лист показывает загрузку, а если запрос не удался — ошибку, а не «никто
/// не прочитал».
@MainActor
@Observable
final class MessageReadersViewModel {
    let request: MessageReadersRequest
    private let memberReads: MemberReadProviding
    private let sessionService: SessionServiceProtocol
    private let userCache: UserCacheServiceProtocol
    /// Участники, загрузка которых запрошена и ещё не завершилась неудачей.
    @ObservationIgnored private var requestedUserIds: Set<Int> = []

    /// - Parameters:
    ///   - request: сообщение листа.
    ///   - memberReads: указатели прочтения участников.
    ///   - sessionService: текущий пользователь — его в списке нет.
    ///   - userCache: имена и аватары участников.
    init(
        request: MessageReadersRequest,
        memberReads: MemberReadProviding,
        sessionService: SessionServiceProtocol,
        userCache: UserCacheServiceProtocol
    ) {
        self.request = request
        self.memberReads = memberReads
        self.sessionService = sessionService
        self.userCache = userCache
    }

    /// Содержимое листа: заголовок «Прочитано: X», строки и заглушка. Без указателей — загрузка или ошибка
    /// с заголовком без числа: сколько прочитали, ещё неизвестно.
    var content: MessageReadersContent {
        guard let pointers = memberReads.pointers(conversationId: request.conversationId) else {
            let isFailed = memberReads.isRefreshFailed(conversationId: request.conversationId)
            return MessageReadersContent(
                title: MessageReadersStrings.titleUnknown,
                readers: [],
                placeholder: isFailed ? .failed : .loading
            )
        }
        let readers = readerIds(in: pointers)
            .map { MessageReaderDisplayModel(userId: $0, cachedUser: userCache.user(id: $0)) }
            .sorted(by: Self.isOrderedBefore)
        return MessageReadersContent(
            title: MessageReadersStrings.title(count: readers.count),
            readers: readers,
            placeholder: readers.isEmpty ? .empty : nil
        )
    }

    /// Лист открыт: указатели запрашиваются заново — мета могла устареть, пока экран был открыт. Пока запрос идёт,
    /// показываются известные.
    func didAppear() {
        memberReads.refresh(conversationId: request.conversationId)
    }

    /// Запускает загрузку участников, которых ещё не запрашивали. Лист не ждёт её — пока участника нет, вместо имени
    /// заглушка. Не загрузившиеся участники запрашиваются снова при следующем изменении листа.
    func loadMissingUsers() {
        let pointers = memberReads.pointers(conversationId: request.conversationId) ?? [:]
        let newIds = readerIds(in: pointers).filter { !requestedUserIds.contains($0) && userCache.user(id: $0) == .pending }
        guard !newIds.isEmpty else { return }
        requestedUserIds.formUnion(newIds)
        Task { [weak self, userCache] in
            await userCache.loadUsers(ids: newIds)
            self?.releaseFailedUsers(newIds)
        }
    }

    /// Снимает отметку «запрошен» с участников, которые после загрузки так и не появились в кэше: кэш повторяет
    /// загрузку при следующем запросе.
    /// - Parameter ids: участники завершившейся загрузки.
    private func releaseFailedUsers(_ ids: [Int]) {
        requestedUserIds.subtract(ids.filter { userCache.user(id: $0) == .pending })
    }

    /// Прочитавшие сообщение по возрастанию id — без текущего пользователя и автора сообщения.
    /// - Parameter pointers: указатели прочтения участников по `userId`.
    private func readerIds(in pointers: [Int: Int]) -> [Int] {
        let currentUserId = sessionService.currentUser?.userId
        return pointers
            .filter { $0.value >= request.messageId && $0.key != currentUserId && $0.key != request.senderId }
            .map(\.key)
            .sorted()
    }

    /// Порядок строк: загруженные раньше заглушек, внутри — по имени, при равных именах — по id.
    /// - Parameters:
    ///   - lhs: первая строка.
    ///   - rhs: вторая строка.
    private static func isOrderedBefore(_ lhs: MessageReaderDisplayModel, _ rhs: MessageReaderDisplayModel) -> Bool {
        guard lhs.isPlaceholder == rhs.isPlaceholder else { return !lhs.isPlaceholder }
        switch lhs.name.localizedStandardCompare(rhs.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhs.id < rhs.id
        }
    }
}
