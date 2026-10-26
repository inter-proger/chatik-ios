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
/// - показывает сохранённые локально элементы, пока грузится первая страница (если владелец передал кэш);
/// - отбрасывает ответы устаревших загрузок (пользователь потянул refresh или сменил поисковый запрос);
/// - отменяет начатую подгрузку следующей страницы при загрузке первой;
/// - сверяет начало списка с сервером, не сбрасывая подгруженные дальше страницы (`syncFirstPage`);
/// - не допускает дубликатов: при постраничной выдаче список на сервере может сдвинуться между запросами;
/// - считает, сколько элементов получено с сервера, — от этого числа отсчитывается следующая страница.
@MainActor
@Observable
final class PaginatedList<Item: Identifiable> where Item.ID: Hashable {
    /// Загрузчик страницы: по контексту (сколько уже получено и какой курсор пришёл) возвращает страницу.
    typealias Load = (PaginationContext) async throws -> PaginatedListPage<Item>
    /// Источник сохранённых локально элементов, которые показываются до ответа загрузчика.
    typealias Cached = () async -> [Item]

    private(set) var items: [Item] = []
    /// `true`, пока грузится первая страница (открытие экрана, pull-to-refresh, смена поискового запроса).
    private(set) var isLoadingFirstPage = false
    /// `true`, пока грузится следующая страница.
    private(set) var isLoadingNextPage = false

    /// За сколько элементов до конца списка начинает грузиться следующая страница.
    private let prefetchThreshold: Int

    /// Есть ли на сервере элементы после загруженных: подгрузка следующей страницы возможна.
    private(set) var hasMorePages = true
    /// Сколько элементов получено с сервера — от этого числа отсчитывается следующая страница.
    private var loadedCount = 0
    /// Курсор из последней страницы — для API, которые продолжают выдачу не сдвигом, а идентификатором.
    private var cursor: Int?
    /// Номер актуальной загрузки: ответы, пришедшие для прежнего номера, отбрасываются.
    private var generation = 0
    /// Номер загрузки, первая страница которой уже применена к списку. Кэш, прочитанный позже ответа сервера,
    /// её не затирает — даже если страница пустая.
    private var appliedFirstPageGeneration = 0
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
    /// - Parameters:
    ///   - cached: источник сохранённых локально элементов. Если список пуст, кэш читается параллельно с загрузкой
    ///     и показывается, пока нет ответа; ответ его заменяет, а кэш, прочитанный позже ответа, отбрасывается.
    ///     При ошибке загрузки кэш остаётся на экране. `nil` — кэша нет.
    ///   - load: загрузчик страницы.
    /// - Returns: что делать владельцу — ошибка, успех или ответ устарел и его нужно игнорировать.
    @discardableResult
    func refresh(cached: Cached? = nil, load: Load) async -> PaginationOutcome {
        nextPageTask?.cancel()
        isLoadingNextPage = false
        generation += 1
        let generation = generation
        isLoadingFirstPage = true
        // Флаг снимает только актуальная загрузка: если за время запроса началась новая, флаг принадлежит ей.
        defer { if generation == self.generation { isLoadingFirstPage = false } }

        // Кэш читается параллельно с запросом — сеть не ждёт БД. Перед возвратом чтение дожидается,
        // чтобы загрузка не оставляла после себя висящих задач.
        let cacheTask = startShowingCached(cached, generation: generation)
        let outcome = await fetchFirstPage(load: load, generation: generation)
        await cacheTask?.value
        // Пока дочитывался кэш, могла начаться новая загрузка — тогда итог этой уже не актуален.
        guard generation == self.generation else { return .superseded }
        return outcome
    }

    /// Сверяет начало списка с сервером, не сбрасывая подгруженные дальше страницы: например, после
    /// переподключения к WebSocket, когда события могли потеряться. Флаг загрузки первой страницы не поднимается,
    /// идущие загрузки не отменяются.
    ///
    /// Страница вклеивается в начало списка, если стыкуется с ним (её последний элемент уже есть в списке);
    /// элементы списка, которых в ней нет, остаются после неё, пагинация продолжается с прежнего места.
    /// Иначе (между страницей и списком мог образоваться разрыв, страница последняя или идёт `refresh`
    /// с ещё не пришедшим ответом) список заменяется страницей, как при `refresh`.
    /// - Parameter load: загрузчик страницы.
    /// - Returns: что делать владельцу — ошибка, успех или ответ устарел. При ошибке список не меняется.
    @discardableResult
    func syncFirstPage(load: Load) async -> PaginationOutcome {
        let generation = generation
        do {
            let page = try await load(PaginationContext(loadedCount: 0, cursor: nil))
            guard generation == self.generation else { return .superseded }
            guard !isLoadingFirstPage, canPrepend(page) else {
                replace(with: page)
                return .applied
            }
            prepend(page)
            return .applied
        } catch {
            guard generation == self.generation, !error.isCancellation else { return .superseded }
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
            guard generation == self.generation, !error.isCancellation else { return .superseded }
            // Повторять на каждом появлении строки не нужно: иначе при недоступном сервере скролл
            // превратится в поток запросов и сообщений. Следующая попытка — по обновлению списка.
            hasMorePages = false
            return .failed(error)
        }
    }

    /// Загружает первую страницу и заменяет ею список.
    /// - Parameters:
    ///   - load: загрузчик страницы.
    ///   - generation: номер загрузки, для которой запрошена страница.
    /// - Returns: итог загрузки для владельца списка.
    private func fetchFirstPage(load: Load, generation: Int) async -> PaginationOutcome {
        do {
            let page = try await load(PaginationContext(loadedCount: 0, cursor: nil))
            guard generation == self.generation else { return .superseded }
            items = []
            loadedCount = 0
            cursor = nil
            appliedFirstPageGeneration = generation
            apply(page)
            return .applied
        } catch {
            // Отменённая загрузка (новый поисковый запрос отменил прежний) — не ошибка: список и пагинация не меняются.
            guard generation == self.generation, !error.isCancellation else { return .superseded }
            // Список остаётся прежним, но пагинация к нему больше не относится: следующая страница
            // ушла бы со сдвигом от неактуальной выдачи.
            hasMorePages = false
            return .failed(error)
        }
    }

    /// Можно ли вклеить первую страницу в начало списка: за ней есть ещё элементы, и её последний элемент уже
    /// в списке — значит, между страницей и остальным списком нет разрыва.
    /// - Parameter page: свежая первая страница.
    private func canPrepend(_ page: PaginatedListPage<Item>) -> Bool {
        guard page.hasNext, let last = page.items.last else { return false }
        return contains(id: last.id)
    }

    /// Ставит первую страницу в начало списка; элементы списка, которых в ней нет, остаются после неё. Сдвиг
    /// следующей страницы растёт на число новых элементов, курсор и признак следующей страницы не меняются:
    /// продолжение выдачи — от прежнего конца списка.
    /// - Parameter page: свежая первая страница, стыкующаяся со списком.
    private func prepend(_ page: PaginatedListPage<Item>) {
        let listedIds = Set(items.map(\.id))
        let pageIds = Set(page.items.map(\.id))
        loadedCount += page.items.filter { !listedIds.contains($0.id) }.count
        items = page.items + items.filter { !pageIds.contains($0.id) }
    }

    /// Заменяет список первой страницей вне `refresh`. Становится актуальной загрузкой: идущие `refresh`
    /// и подгрузка следующей страницы отменяются, их ответы отбрасываются как устаревшие, а кэш больше не показывается.
    /// - Parameter page: свежая первая страница.
    private func replace(with page: PaginatedListPage<Item>) {
        nextPageTask?.cancel()
        isLoadingNextPage = false
        isLoadingFirstPage = false
        generation += 1
        appliedFirstPageGeneration = generation
        items = []
        loadedCount = 0
        cursor = nil
        apply(page)
    }

    /// Начинает читать кэш, если он передан и список пуст (открытие экрана). При непустом списке кэш не нужен:
    /// на экране и так более свежие элементы.
    /// - Parameters:
    ///   - cached: источник сохранённых элементов; `nil` — кэша нет.
    ///   - generation: номер загрузки, для которой читается кэш.
    /// - Returns: задача чтения; `nil`, если кэш не читается.
    private func startShowingCached(_ cached: Cached?, generation: Int) -> Task<Void, Never>? {
        guard let cached, items.isEmpty else { return nil }
        return Task { await showCached(cached, generation: generation) }
    }

    /// Показывает сохранённые локально элементы, пока идёт загрузка первой страницы. Счётчик полученного
    /// с сервера и признак следующей страницы не меняются: кэш не участвует в пагинации, и пока загрузка идёт,
    /// следующая страница не запрашивается.
    /// - Parameters:
    ///   - cached: источник сохранённых элементов.
    ///   - generation: номер загрузки, для которой читается кэш.
    private func showCached(_ cached: Cached, generation: Int) async {
        let cachedItems = await cached()
        // Пока читался кэш, могли прийти ответ сервера, начаться новая загрузка или появиться элементы
        // (сверка первой страницы) — всё это актуальнее кэша.
        guard generation == self.generation,
              appliedFirstPageGeneration != generation,
              items.isEmpty else { return }
        items = cachedItems
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
