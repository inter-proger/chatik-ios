//
//  AddGroupMembersViewModel.swift
//  Chatik
//

import Foundation
import Observation

/// Добавление участников в группу (`docs/group-chats.md`, решение 14).
///
/// **Состав — снимок.** Экран не следит за событиями: снимок берётся при открытии и обновляется только ответом
/// `addMembers`. Лимит выбора — `GroupLimits.maxMembers` минус участники снимка.
///
/// **Фильтр — при сборке строк.** `PaginatedList` хранит всех пользователей выдачи; «Не в группе» отбрасывает
/// участников при сборке, поэтому смена фильтра и новый снимок меняют список без запроса. Если видимых строк
/// меньше порога, а у выдачи есть продолжение, следующая страница запрашивается сама: иначе подгрузка встала бы —
/// строк нет, и `onAppear` не придёт.
@MainActor
@Observable
final class AddGroupMembersViewModel {
    /// Размер страницы списка пользователей.
    static let pageSize = 30
    /// Меньше стольких видимых строк — следующая страница запрашивается без прокрутки.
    static let minVisibleRows = 20
    /// За сколько видимых строк до конца списка начинается загрузка следующей страницы.
    static let prefetchThreshold = 5

    /// Содержимое поля поиска.
    var searchText = ""
    /// Фильтр списка.
    var filter = AddGroupMembersFilter.all {
        didSet { loadMoreIfFewVisible() }
    }
    /// Выбранные пользователи; сохраняются при смене поиска и фильтра.
    private(set) var selectedIds: Set<Int> = []
    /// Состав группы на момент открытия или последнего добавления; `nil` — ещё не загружен.
    private(set) var snapshot: GroupInfo?
    /// Снимок не загрузился.
    private(set) var isSnapshotFailed = false
    /// `true`, пока идёт запрос добавления.
    private(set) var isAdding = false
    /// Попап не добавленных; `nil` — скрыт.
    var presentedNotAdded: NotAddedReport?

    @ObservationIgnored private let conversationId: Int
    @ObservationIgnored private let list = PaginatedList<UserRowDisplayModel>()
    @ObservationIgnored private var listedQuery = ""
    @ObservationIgnored private let searchDebounce: Duration
    @ObservationIgnored private let groupInfo: GroupInfoProviding
    @ObservationIgnored private let groupService: GroupServiceProtocol
    @ObservationIgnored private let usersService: UsersServiceProtocol
    @ObservationIgnored private let membership: ConversationMembershipVerifying
    @ObservationIgnored private let sessionService: SessionServiceProtocol
    @ObservationIgnored private let userCache: UserCacheServiceProtocol
    @ObservationIgnored private let notifications: InAppNotificationServiceProtocol
    @ObservationIgnored private let navigator: GroupNavigating

    /// - Parameters:
    ///   - conversationId: группа.
    ///   - groupInfo: состав групп — снимок и применение ответа.
    ///   - groupService: запрос `/groups/addMembers`.
    ///   - usersService: список пользователей с поиском.
    ///   - membership: проверка членства при `5002`.
    ///   - sessionService: текущий пользователь — исключается из списка.
    ///   - userCache: имена не добавленных в попапе.
    ///   - notifications: уведомления.
    ///   - navigator: закрытие экрана, если право добавлять пропало.
    ///   - searchDebounce: пауза после ввода в поле поиска.
    init(
        conversationId: Int,
        groupInfo: GroupInfoProviding,
        groupService: GroupServiceProtocol,
        usersService: UsersServiceProtocol,
        membership: ConversationMembershipVerifying,
        sessionService: SessionServiceProtocol,
        userCache: UserCacheServiceProtocol,
        notifications: InAppNotificationServiceProtocol,
        navigator: GroupNavigating,
        searchDebounce: Duration = .milliseconds(300)
    ) {
        self.conversationId = conversationId
        self.groupInfo = groupInfo
        self.groupService = groupService
        self.usersService = usersService
        self.membership = membership
        self.sessionService = sessionService
        self.userCache = userCache
        self.notifications = notifications
        self.navigator = navigator
        self.searchDebounce = searchDebounce
    }

    // MARK: - Состояние

    /// Участники снимка.
    private var memberIds: Set<Int> {
        Set(snapshot?.members.map(\.userId) ?? [])
    }

    /// Сколько ещё можно выбрать: лимит минус участники снимка.
    var capacity: Int {
        max(0, GroupLimits.maxMembers - (snapshot?.members.count ?? GroupLimits.maxMembers))
    }

    /// Выбрано столько, сколько помещается.
    var isLimitReached: Bool {
        snapshot != nil && selectedIds.count >= capacity
    }

    /// Строки списка по фильтру и снимку.
    var rows: [AddMemberRowDisplayModel] {
        let memberIds = memberIds
        let isLimitReached = isLimitReached
        return list.items
            .filter { filter == .all || !memberIds.contains($0.id) }
            .map { user in
                let isMember = memberIds.contains(user.id)
                let isSelected = selectedIds.contains(user.id)
                return AddMemberRowDisplayModel(
                    user: user,
                    isMember: isMember,
                    isSelected: isSelected,
                    isDisabled: isAdding || isMember || (isLimitReached && !isSelected)
                )
            }
    }

    /// Заголовок: «Добавить участников» или «Добавить: X».
    var title: String {
        selectedIds.isEmpty ? AddGroupMembersStrings.title : AddGroupMembersStrings.titleSelected(count: selectedIds.count)
    }

    /// Активна ли «Добавить».
    var isAddButtonEnabled: Bool {
        !isAdding && !selectedIds.isEmpty
    }

    /// `true`, пока грузится первая страница.
    var isLoadingFirstPage: Bool {
        list.isLoadingFirstPage
    }

    /// `true`, пока грузится следующая страница.
    var isLoadingNextPage: Bool {
        list.isLoadingNextPage
    }

    /// Показывать ли пустой список: строк нет и ничего не грузится.
    var isEmpty: Bool {
        rows.isEmpty && !list.isLoadingFirstPage && !list.isLoadingNextPage && !list.hasMorePages
    }

    // MARK: - Снимок состава

    /// Экран открыт: берётся снимок состава (из памяти, БД или запросом).
    func loadSnapshot() async {
        guard snapshot == nil else { return }
        isSnapshotFailed = false
        do {
            snapshot = try await groupInfo.snapshot(conversationId: conversationId)
            loadMoreIfFewVisible()
        } catch {
            isSnapshotFailed = true
            if error.indicatesLostMembership {
                membership.verifyMembership(conversationId: conversationId)
            }
        }
    }

    // MARK: - Список

    /// Загружает список под текущий запрос; непустой выдерживается паузой (`task(id:)` отменяет прежний вызов).
    func searchTextDidChange() async {
        if !searchText.isEmpty {
            try? await Task.sleep(for: searchDebounce)
        }
        guard !Task.isCancelled else { return }
        await loadFirstPage()
    }

    /// Загружает список заново (поиск, pull-to-refresh). Выбор сохраняется.
    func loadFirstPage() async {
        let query = searchText
        let outcome = await list.refresh { [weak self] context in
            guard let self else { throw CancellationError() }
            return try await self.loadPage(context, query: query)
        }
        if case .applied = outcome {
            listedQuery = query
            loadMoreIfFewVisible()
        }
        show(outcome)
    }

    /// Строка появилась на экране: за `prefetchThreshold` видимых строк до конца подгружается следующая страница —
    /// заранее, чтобы пользователь в норме не видел прелоадера. Порог считается по видимым строкам: при фильтре
    /// их меньше, чем загруженных.
    /// - Parameter row: появившаяся строка.
    func prefetchNextPageIfNeeded(currentRow row: AddMemberRowDisplayModel) {
        let rows = rows
        guard let index = rows.firstIndex(where: { $0.id == row.id }), index >= rows.count - Self.prefetchThreshold else { return }
        loadNextPage()
    }

    /// Запрашивает следующую страницу под запрос, по которому загружен список.
    private func loadNextPage() {
        guard let last = list.items.last else { return }
        let query = listedQuery
        list.prefetchNextPageIfNeeded(
            currentItem: last,
            load: { [weak self] context in
                guard let self else { throw CancellationError() }
                return try await self.loadPage(context, query: query)
            },
            onOutcome: { [weak self] outcome in
                self?.show(outcome)
                guard case .applied = outcome else { return }
                self?.loadMoreIfFewVisible()
            }
        )
    }

    /// Видимых строк меньше порога, а у выдачи есть продолжение — следующая страница без прокрутки.
    private func loadMoreIfFewVisible() {
        guard list.hasMorePages, !list.isLoadingFirstPage, rows.count < Self.minVisibleRows else { return }
        loadNextPage()
    }

    /// Страница пользователей без текущего пользователя.
    /// - Parameters:
    ///   - context: курсор `maxId` предыдущей страницы.
    ///   - query: поисковый запрос.
    private func loadPage(_ context: PaginationContext, query: String) async throws -> PaginatedListPage<UserRowDisplayModel> {
        let page = try await usersService.fetchUsers(query: query, maxId: context.cursor, count: Self.pageSize)
        let currentUserId = sessionService.currentUser?.userId
        return PaginatedListPage(
            items: page.users.filter { $0.userId != currentUserId }.map(UserRowDisplayModel.init),
            hasNext: page.hasNext,
            nextCursor: page.nextMaxId
        )
    }

    /// Показывает ошибку загрузки страницы.
    /// - Parameter outcome: итог загрузки.
    private func show(_ outcome: PaginationOutcome) {
        guard case .failed(let error) = outcome else { return }
        notifications.showError(ErrorMessages.message(for: error))
    }

    // MARK: - Выбор и добавление

    /// Нажатие на строку: выбор или снятие выбора. Участников и сверх лимита выбрать нельзя.
    /// - Parameter row: строка.
    func didToggle(_ row: AddMemberRowDisplayModel) {
        guard !isAdding, !row.isMember else { return }
        if selectedIds.contains(row.id) {
            selectedIds.remove(row.id)
            return
        }
        guard selectedIds.count < capacity else { return }
        selectedIds.insert(row.id)
    }

    /// «Добавить»: запрос по выбранным.
    func didTapAdd() {
        guard isAddButtonEnabled else { return }
        isAdding = true
        let userIds = selectedIds.sorted()
        Task { await add(userIds) }
    }

    /// Запрос добавления: новый снимок, сброс выбора и уведомление по итогу.
    /// - Parameter userIds: выбранные пользователи.
    private func add(_ userIds: [Int]) async {
        defer { isAdding = false }
        do {
            let result = try await groupService.addMembers(conversationId: conversationId, userIds: userIds)
            groupInfo.apply(result.groupInfo)
            snapshot = result.groupInfo
            selectedIds = []
            showResult(result)
            loadMoreIfFewVisible()
        } catch {
            handleAddError(error)
        }
    }

    /// Уведомление по итогу: не добавленные — предупреждение с подробностями по нажатию, иначе — «Участники добавлены».
    /// - Parameter result: ответ `addMembers`.
    private func showResult(_ result: AddMembersResult) {
        guard !result.notAddedUsersInfo.isEmpty else {
            notifications.showInfo(AddGroupMembersStrings.allAdded)
            return
        }
        let report = NotAddedReport(users: result.notAddedUsersInfo)
        Task { [userCache] in await userCache.loadUsers(ids: report.users.map(\.userId)) }
        notifications.show(InAppNotification(
            content: .warning(message: AddGroupMembersStrings.notAdded(count: report.users.count)),
            onTap: { [weak self] in self?.presentedNotAdded = report }
        ))
    }

    /// Ошибка запроса: `5004` — права уже нет, экран закрывается; `5002` — проверка членства.
    /// - Parameter error: ошибка.
    private func handleAddError(_ error: Error) {
        notifications.showError(ErrorMessages.message(for: error))
        if case NetworkError.api(code: NetworkError.Code.groupOwnerOnly) = error {
            groupInfo.refresh(conversationId: conversationId)
            navigator.pop()
        } else if error.indicatesLostMembership {
            membership.verifyMembership(conversationId: conversationId)
        }
    }

    // MARK: - Попап не добавленных

    /// Секции попапа: причина и пользователи с одинаковой ошибкой.
    /// - Parameter report: не добавленные.
    func notAddedSections(for report: NotAddedReport) -> [NotAddedSectionDisplayModel] {
        report.groups.map { group in
            NotAddedSectionDisplayModel(
                id: group.errorCode,
                reason: Self.reason(for: group.errorCode),
                users: group.userIds.map { GroupMemberDisplayModel(userId: $0, cachedUser: userCache.user(id: $0)) }
            )
        }
    }

    /// Текст причины по коду ошибки.
    /// - Parameter code: код из `notAddedUsersInfo`.
    private static func reason(for code: Int) -> String {
        switch code {
        case NetworkError.Code.userNotFound: AddGroupMembersStrings.reasonUserNotFound
        case NetworkError.Code.groupMemberLimitReached: AddGroupMembersStrings.reasonLimitReached
        case NetworkError.Code.alreadyGroupMember: AddGroupMembersStrings.reasonAlreadyMember
        default: ErrorMessages.message(for: NetworkError.api(code: code))
        }
    }
}
