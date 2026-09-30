//
//  PaginatedList.swift
//  Chatik
//

import Foundation

/// Постраничный список для ViewModel: хранит элементы, флаги загрузки и всё, что нужно для бесшовной
/// подгрузки следующих страниц. Как именно загружается страница, знает владелец — он передаёт загрузчик
/// в каждый вызов, поэтому список не хранит загрузчик между вызовами и не знает про сервисы. Пока идёт
/// подгрузка следующей страницы, загрузчик (а с ним и владелец) удерживается её задачей — до её завершения.
///
/// Что он берёт на себя:
/// - отбрасывает ответы устаревших загрузок (пользователь потянул refresh или сменил поисковый запрос);
/// - отменяет начатую подгрузку следующей страницы при загрузке первой;
/// - не допускает дубликатов: при постраничной выдаче список на сервере может сдвинуться между запросами;
/// - считает, сколько элементов получено с сервера, отдельно от `items` — вставленные локально
///   (например, только что созданная переписка) сдвиг следующей страницы не смещают.
@MainActor
@Observable
final class PaginatedList<Item: Identifiable> where Item.ID: Hashable {
    /// Загрузчик страницы: по контексту (сколько уже получено и какой курсор пришёл) возвращает страницу.
    typealias Load = (PaginationContext) async throws -> PaginatedListPage<Item>

    private(set) var items: [Item] = []
    /// `true`, пока грузится первая страница (открытие экрана, pull-to-refresh, смена поискового запроса).
    private(set) var isLoadingFirstPage = false
    /// `true`, пока грузится следующая страница.
    private(set) var isLoadingNextPage = false

    /// За сколько элементов до конца списка начинает грузиться следующая страница.
    private let prefetchThreshold: Int

    private var hasMorePages = true
    /// Сколько элементов получено с сервера — от этого числа отсчитывается следующая страница.
    private var loadedCount = 0
    /// Курсор из последней страницы — для API, которые продолжают выдачу не сдвигом, а идентификатором.
    private var cursor: Int?
    /// Номер актуальной загрузки: ответы, пришедшие для прежнего номера, отбрасываются.
    private var generation = 0
    private var nextPageTask: Task<Void, Never>?

    /// - Parameter prefetchThreshold: за сколько элементов до конца списка начинать подгрузку следующей страницы.
    init(prefetchThreshold: Int = 5) {
        self.prefetchThreshold = prefetchThreshold
    }

    /// `true`, если показывать нечего: список пуст и первая страница не грузится.
    var isEmpty: Bool {
        items.isEmpty && !isLoadingFirstPage
    }

    /// Есть ли элемент с таким идентификатором в списке.
    /// - Parameter id: идентификатор элемента.
    func contains(id: Item.ID) -> Bool {
        items.contains { $0.id == id }
    }

    /// Загружает первую страницу, заменяя ею список. Прежние элементы остаются на экране до ответа.
    /// Начатая подгрузка следующей страницы отменяется, а её опоздавший ответ отбрасывается.
    /// - Parameter load: загрузчик страницы.
    /// - Returns: что делать владельцу — ошибка, успех или ответ устарел и его нужно игнорировать.
    @discardableResult
    func refresh(load: Load) async -> PaginationOutcome {
        nextPageTask?.cancel()
        isLoadingNextPage = false
        generation += 1
        let generation = generation
        isLoadingFirstPage = true
        // Флаг снимает только актуальная загрузка: если за время запроса началась новая, флаг принадлежит ей.
        defer { if generation == self.generation { isLoadingFirstPage = false } }

        do {
            let page = try await load(PaginationContext(loadedCount: 0, cursor: nil))
            guard generation == self.generation else { return .superseded }
            items = []
            loadedCount = 0
            cursor = nil
            apply(page)
            return .applied
        } catch {
            guard generation == self.generation else { return .superseded }
            // Список остаётся прежним, но пагинация к нему больше не относится: следующая страница
            // ушла бы со сдвигом от неактуальной выдачи.
            hasMorePages = false
            return .failed(error)
        }
    }

    /// Начинает подгрузку следующей страницы, если показан один из последних элементов списка.
    /// - Parameters:
    ///   - item: элемент, который появился на экране.
    ///   - load: загрузчик страницы.
    ///   - onOutcome: результат подгрузки — владелец решает, показывать ли ошибку.
    func prefetchNextPageIfNeeded(
        currentItem item: Item,
        load: @escaping Load,
        onOutcome: @escaping (PaginationOutcome) -> Void
    ) {
        guard hasMorePages, !isLoadingFirstPage, !isLoadingNextPage else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard index >= items.count - prefetchThreshold else { return }
        // Флаг поднимаем до старта задачи, чтобы повторные появления строк не запускали вторую загрузку.
        isLoadingNextPage = true
        nextPageTask = Task { onOutcome(await loadNextPage(load: load)) }
    }

    /// Загружает следующую страницу и дописывает её к списку.
    ///
    /// Не проверяет `hasMorePages` и уже идущую загрузку и не поднимает `isLoadingNextPage` — это делает
    /// `prefetchNextPageIfNeeded`. Владельцы списка вызывают только её; напрямую метод вызывается в тестах.
    /// - Parameter load: загрузчик страницы.
    /// - Returns: что делать владельцу — ошибка, успех или ответ устарел.
    @discardableResult
    func loadNextPage(load: Load) async -> PaginationOutcome {
        let generation = generation
        defer { if generation == self.generation { isLoadingNextPage = false } }

        do {
            let page = try await load(PaginationContext(loadedCount: loadedCount, cursor: cursor))
            guard generation == self.generation else { return .superseded }
            apply(page)
            return .applied
        } catch {
            guard generation == self.generation else { return .superseded }
            // Повторять на каждом появлении строки не нужно: иначе при недоступном сервере скролл
            // превратится в поток запросов и сообщений. Следующая попытка — по обновлению списка.
            hasMorePages = false
            return .failed(error)
        }
    }

    /// Вставляет элемент в начало списка, если его там ещё нет. Счётчик полученного с сервера не меняется:
    /// локальная вставка не сдвигает выдачу, из которой берётся следующая страница.
    /// - Parameter item: элемент, появившийся помимо загрузки (например, только что созданная переписка).
    func insertIfAbsent(_ item: Item) {
        guard !contains(id: item.id) else { return }
        items.insert(item, at: 0)
    }

    /// Дописывает страницу, пропуская элементы, которые уже есть в списке.
    /// - Parameter page: загруженная страница.
    private func apply(_ page: PaginatedListPage<Item>) {
        let listedIds = Set(items.map(\.id))
        items += page.items.filter { !listedIds.contains($0.id) }
        loadedCount += page.items.count
        cursor = page.nextCursor
        hasMorePages = page.hasNext
    }
}

/// Что известно загрузчику о том, какую страницу от него ждут.
struct PaginationContext: Equatable {
    /// Сколько элементов уже получено с сервера — для API со сдвигом (`offset`). Для первой страницы — 0.
    let loadedCount: Int
    /// Курсор из предыдущей страницы — для API с продолжением по идентификатору (`maxId`).
    /// Для первой страницы — `nil`.
    let cursor: Int?

    /// `true`, если запрашивается первая страница.
    var isFirstPage: Bool {
        loadedCount == 0 && cursor == nil
    }
}

/// Страница, приведённая к элементам списка.
struct PaginatedListPage<Item> {
    let items: [Item]
    /// Есть ли элементы после этой страницы.
    let hasNext: Bool
    /// Курсор для следующей страницы; `nil` — API продолжает выдачу сдвигом.
    let nextCursor: Int?

    /// - Parameters:
    ///   - items: элементы страницы.
    ///   - hasNext: есть ли следующая страница.
    ///   - nextCursor: курсор следующей страницы, если API работает по курсору.
    init(items: [Item], hasNext: Bool, nextCursor: Int? = nil) {
        self.items = items
        self.hasNext = hasNext
        self.nextCursor = nextCursor
    }
}

/// Итог загрузки страницы для владельца списка.
enum PaginationOutcome {
    /// Страница применена к списку.
    case applied
    /// Ответ относится к устаревшей загрузке — ни списка, ни ошибки он не касается.
    case superseded
    /// Загрузка не удалась; владелец решает, как показать ошибку.
    case failed(Error)
}
