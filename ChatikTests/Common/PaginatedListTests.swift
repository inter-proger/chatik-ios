//
//  PaginatedListTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

@MainActor
final class PaginatedListTests: XCTestCase {
    private var sut: PaginatedList<Item>!

    override func setUp() {
        super.setUp()
        sut = PaginatedList<Item>(prefetchThreshold: 2)
    }

    // MARK: - Первая страница

    /// Кейс: первая страница загружена.
    /// Ожидание: элементы показаны, загрузчику передан контекст первой страницы, флаг загрузки снят.
    func test_refresh_success_showsItemsAndReportsApplied() async {
        let recorder = ContextRecorder()

        let outcome = await sut.refresh(load: page(ids: [1, 2], hasNext: false, recorder: recorder))

        XCTAssertEqual(sut.items.map(\.id), [1, 2])
        XCTAssertEqual(recorder.contexts, [PaginationContext(loadedCount: 0, cursor: nil)])
        XCTAssertFalse(sut.isLoadingFirstPage)
        assertApplied(outcome)
    }

    /// Кейс: загрузка первой страницы завершилась ошибкой.
    /// Ожидание: наружу отдана ошибка, прежний список остаётся на экране.
    func test_refresh_failure_keepsItemsAndReportsError() async {
        await sut.refresh(load: page(ids: [1], hasNext: true))

        let outcome = await sut.refresh(load: failing())

        XCTAssertEqual(sut.items.map(\.id), [1])
        guard case .failed(let error) = outcome else { return XCTFail("Ожидалась ошибка, получено \(outcome)") }
        XCTAssertEqual(error as? TestError, .any)
    }

    /// Кейс: во время загрузки началась новая загрузка первой страницы.
    /// Ожидание: опоздавший ответ отброшен — в списке результат последней загрузки, итог первой — `superseded`.
    func test_refresh_staleResponse_isDiscarded() async {
        let gate = Gate()
        var staleOutcome: PaginationOutcome?
        let stale = Task { staleOutcome = await self.sut.refresh(load: self.page(ids: [1], hasNext: true, gate: gate)) }
        await yieldUntil { gate.isWaiting }

        await sut.refresh(load: page(ids: [2], hasNext: false))
        gate.open()
        await stale.value

        XCTAssertEqual(sut.items.map(\.id), [2])
        guard case .superseded = try? XCTUnwrap(staleOutcome) else { return XCTFail("Ожидался superseded") }
        XCTAssertFalse(sut.isLoadingFirstPage)
    }

    /// Кейс: после подгрузки следующей страницы список обновлён, затем снова грузится следующая страница.
    /// Ожидание: обновление запрашивает первую страницу с нуля, а следующая считается от новой выдачи —
    /// ни сдвиг, ни курсор прежней выдачи не переносятся.
    func test_refresh_afterNextPage_resetsPaginationContext() async {
        let recorder = ContextRecorder()
        await sut.refresh(load: page(ids: [1, 2], hasNext: true, cursor: 2))
        await sut.loadNextPage(load: page(ids: [3], hasNext: true, cursor: 3))

        await sut.refresh(load: page(ids: [5], hasNext: true, recorder: recorder))
        await sut.loadNextPage(load: page(ids: [6], hasNext: false, recorder: recorder))

        let expectedContexts = [
            PaginationContext(loadedCount: 0, cursor: nil),
            PaginationContext(loadedCount: 1, cursor: nil),
        ]
        XCTAssertEqual(recorder.contexts, expectedContexts)
        XCTAssertEqual(sut.items.map(\.id), [5, 6])
    }

    /// Кейс: во время подгрузки следующей страницы список обновлён.
    /// Ожидание: опоздавшая следующая страница отброшена — в списке только новая выдача, итог подгрузки — `superseded`.
    func test_refresh_duringNextPage_discardsNextPage() async throws {
        let gate = Gate()
        var nextPageOutcome: PaginationOutcome?
        await sut.refresh(load: page(ids: [1, 2], hasNext: true))
        sut.prefetchNextPageIfNeeded(
            currentItem: try XCTUnwrap(sut.items.last),
            load: page(ids: [3], hasNext: true, gate: gate),
            onOutcome: { nextPageOutcome = $0 }
        )
        await yieldUntil { gate.isWaiting }

        await sut.refresh(load: page(ids: [7], hasNext: false))
        gate.open()
        await yieldUntil { nextPageOutcome != nil }

        XCTAssertEqual(sut.items.map(\.id), [7])
        guard case .superseded = try XCTUnwrap(nextPageOutcome) else { return XCTFail("Ожидался superseded") }
        XCTAssertFalse(sut.isLoadingNextPage)
    }

    // MARK: - Следующие страницы

    /// Кейс: показан один из последних элементов полной страницы.
    /// Ожидание: следующая страница запрошена с контекстом предыдущей и дописана к списку.
    func test_prefetch_nearEnd_appendsNextPage() async throws {
        let recorder = ContextRecorder()
        await sut.refresh(load: page(ids: [1, 2, 3], hasNext: true, cursor: 3, recorder: recorder))

        sut.prefetchNextPageIfNeeded(
            currentItem: try XCTUnwrap(sut.items.last),
            load: page(ids: [4], hasNext: false, recorder: recorder),
            onOutcome: { _ in }
        )
        await yieldUntil { [unowned self] in !sut.isLoadingNextPage }

        XCTAssertEqual(sut.items.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(recorder.contexts.last, PaginationContext(loadedCount: 3, cursor: 3))
    }

    /// Кейс: на экране элемент из начала списка, до конца дальше порога подгрузки.
    /// Ожидание: следующая страница не запрашивается.
    func test_prefetch_farFromEnd_doesNotLoad() async throws {
        let recorder = ContextRecorder()
        await sut.refresh(load: page(ids: [1, 2, 3, 4, 5], hasNext: true))

        sut.prefetchNextPageIfNeeded(
            currentItem: try XCTUnwrap(sut.items.first),
            load: page(ids: [9], hasNext: false, recorder: recorder),
            onOutcome: { _ in }
        )

        XCTAssertFalse(sut.isLoadingNextPage)
        XCTAssertTrue(recorder.contexts.isEmpty)
    }

    /// Кейс: страница последняя (`hasNext: false`), на экране её последний элемент.
    /// Ожидание: следующая страница не запрашивается.
    func test_prefetch_lastPage_doesNotLoad() async throws {
        let recorder = ContextRecorder()
        await sut.refresh(load: page(ids: [1, 2], hasNext: false))

        sut.prefetchNextPageIfNeeded(
            currentItem: try XCTUnwrap(sut.items.last),
            load: page(ids: [9], hasNext: false, recorder: recorder),
            onOutcome: { _ in }
        )

        XCTAssertFalse(sut.isLoadingNextPage)
        XCTAssertTrue(recorder.contexts.isEmpty)
    }

    /// Кейс: следующая страница вернула элемент, который уже есть в списке (выдача сдвинулась между запросами).
    /// Ожидание: дубликат не добавляется.
    func test_loadNextPage_duplicate_isNotAppended() async {
        await sut.refresh(load: page(ids: [1, 2], hasNext: true))

        await sut.loadNextPage(load: page(ids: [2, 3], hasNext: false))

        XCTAssertEqual(sut.items.map(\.id), [1, 2, 3])
    }

    /// Кейс: загрузка следующей страницы завершилась ошибкой, затем снова показан последний элемент.
    /// Ожидание: повторная подгрузка не запускается — до обновления списка запросы прекращаются.
    func test_loadNextPage_failure_stopsPagination() async throws {
        let recorder = ContextRecorder()
        await sut.refresh(load: page(ids: [1, 2], hasNext: true))
        await sut.loadNextPage(load: failing())

        sut.prefetchNextPageIfNeeded(
            currentItem: try XCTUnwrap(sut.items.last),
            load: page(ids: [3], hasNext: false, recorder: recorder),
            onOutcome: { _ in }
        )

        XCTAssertFalse(sut.isLoadingNextPage)
        XCTAssertTrue(recorder.contexts.isEmpty)
    }

    // MARK: - Локальная вставка

    /// Кейс: элемент вставлен локально, затем грузится следующая страница.
    /// Ожидание: элемент в начале списка, сдвиг следующей страницы считается по полученному с сервера.
    func test_insertIfAbsent_doesNotShiftNextPageContext() async {
        let recorder = ContextRecorder()
        await sut.refresh(load: page(ids: [1, 2], hasNext: true))

        sut.insertIfAbsent(Item(id: 99))
        await sut.loadNextPage(load: page(ids: [3], hasNext: false, recorder: recorder))

        XCTAssertEqual(sut.items.map(\.id), [99, 1, 2, 3])
        XCTAssertEqual(recorder.contexts.last?.loadedCount, 2)
    }

    /// Кейс: вставляется элемент, который уже есть в списке.
    /// Ожидание: список не меняется — дубликата не появляется.
    func test_insertIfAbsent_alreadyListed_doesNothing() async {
        await sut.refresh(load: page(ids: [1, 2], hasNext: false))

        sut.insertIfAbsent(Item(id: 2))

        XCTAssertEqual(sut.items.map(\.id), [1, 2])
    }

    /// Кейс: список пуст и ничего не грузится / грузится первая страница.
    /// Ожидание: пустым считается только список без активной загрузки — иначе экран мигал бы заглушкой.
    func test_isEmpty_accountsForFirstPageLoading() async {
        XCTAssertTrue(sut.isEmpty)
        var isEmptyDuringLoad = true

        await sut.refresh(load: { [unowned self] _ in
            isEmptyDuringLoad = sut.isEmpty
            return PaginatedListPage(items: [Item(id: 1)], hasNext: false)
        })

        XCTAssertFalse(isEmptyDuringLoad)
        XCTAssertFalse(sut.isEmpty)
    }

    // MARK: - Отмена

    /// Кейс: идёт загрузка первой страницы, вызван `cancelLoading()`; затем загрузчик всё-таки ответил.
    /// Ожидание: флаг загрузки снят сразу, опоздавший ответ отброшен — итог `superseded`, список прежний.
    func test_cancelLoading_duringRefresh_discardsResponse() async {
        await sut.refresh(load: page(ids: [1], hasNext: false))
        let gate = Gate()
        var outcome: PaginationOutcome?
        let refresh = Task { outcome = await self.sut.refresh(load: self.page(ids: [2], hasNext: false, gate: gate)) }
        await yieldUntil { gate.isWaiting }

        await sut.cancelLoading()
        let isLoadingAfterCancel = sut.isLoadingFirstPage
        gate.open()
        await refresh.value

        XCTAssertFalse(isLoadingAfterCancel)
        XCTAssertEqual(sut.items.map(\.id), [1])
        guard case .superseded = try? XCTUnwrap(outcome) else { return XCTFail("Ожидался superseded") }
    }

    /// Кейс: идёт подгрузка следующей страницы, вызван `cancelLoading()`.
    /// Ожидание: `cancelLoading()` возвращается только после завершения подгрузки; её страница не дописана,
    /// флаг подгрузки снят, а сама задача подгрузки отменена.
    func test_cancelLoading_duringNextPage_waitsAndDiscardsPage() async throws {
        await sut.refresh(load: page(ids: [1, 2], hasNext: true))
        let gate = Gate()
        var isLoaderCancelled = false
        let load: PaginatedList<Item>.Load = { _ in
            await gate.wait()
            isLoaderCancelled = Task.isCancelled
            return PaginatedListPage(items: [Item(id: 3)], hasNext: false)
        }
        sut.prefetchNextPageIfNeeded(currentItem: try XCTUnwrap(sut.items.last), load: load, onOutcome: { _ in })
        await yieldUntil { gate.isWaiting }

        var isCancelFinished = false
        let cancel = Task { await self.sut.cancelLoading(); isCancelFinished = true }
        await yieldUntil { [unowned self] in !sut.isLoadingNextPage }
        let isFinishedBeforeLoaderReturned = isCancelFinished
        gate.open()
        await cancel.value

        XCTAssertFalse(isFinishedBeforeLoaderReturned)
        XCTAssertTrue(isLoaderCancelled)
        XCTAssertEqual(sut.items.map(\.id), [1, 2])
    }

    // MARK: - Кэш

    /// Кейс: список пуст, передан кэш; загрузка первой страницы ещё идёт.
    /// Ожидание: до ответа загрузчика показаны элементы кэша, после — они заменены страницей.
    func test_refresh_withCache_showsCacheUntilPageLoaded() async {
        let gate = Gate()
        let refresh = Task {
            await self.sut.refresh(cached: { [Item(id: 10), Item(id: 11)] }, load: self.page(ids: [1], hasNext: false, gate: gate))
        }
        await yieldUntil { gate.isWaiting }

        await yieldUntil { [unowned self] in sut.items.map(\.id) == [10, 11] }
        gate.open()
        await refresh.value

        XCTAssertEqual(sut.items.map(\.id), [1])
    }

    /// Кейс: список пуст, передан кэш, чтение которого не завершается, пока тест его не отпустит.
    /// Ожидание: загрузчик вызван до завершения чтения кэша — сеть не ждёт БД.
    func test_refresh_withCache_loadsWithoutWaitingForCache() async {
        let cacheGate = Gate()
        var isLoaderCalled = false
        let cached: PaginatedList<Item>.Cached = {
            await cacheGate.wait()
            return [Item(id: 10)]
        }

        let refresh = Task {
            await self.sut.refresh(cached: cached, load: { _ in
                isLoaderCalled = true
                return PaginatedListPage(items: [Item(id: 1)], hasNext: false)
            })
        }
        await yieldUntil { isLoaderCalled && cacheGate.isWaiting }
        cacheGate.open()
        await refresh.value

        XCTAssertEqual(sut.items.map(\.id), [1])
    }

    /// Кейс: ответ сервера пришёл раньше, чем дочитался кэш; набор ответов — непустая и пустая страница.
    /// Ожидание: опоздавший кэш отброшен — на экране ответ сервера, даже если он пустой.
    func test_refresh_cacheReadAfterPage_isDiscarded() async {
        let pages = [
            [1],
            [],
        ]

        for ids in pages {
            let list = PaginatedList<Item>()
            let cacheGate = Gate()
            let cached: PaginatedList<Item>.Cached = {
                await cacheGate.wait()
                return [Item(id: 10)]
            }
            var isPageLoaded = false
            let refresh = Task {
                await list.refresh(cached: cached, load: { _ in
                    isPageLoaded = true
                    return PaginatedListPage(items: ids.map(Item.init), hasNext: false)
                })
            }
            await yieldUntil { cacheGate.isWaiting && isPageLoaded }

            cacheGate.open()
            await refresh.value

            XCTAssertEqual(list.items.map(\.id), ids, "\(ids)")
        }
    }

    /// Кейс: список пуст, передан кэш; загрузка первой страницы завершилась ошибкой.
    /// Ожидание: на экране остаются элементы кэша, наружу отдана ошибка.
    func test_refresh_withCache_failure_keepsCachedItems() async {
        let outcome = await sut.refresh(cached: { [Item(id: 10)] }, load: failing())

        XCTAssertEqual(sut.items.map(\.id), [10])
        guard case .failed = outcome else { return XCTFail("Ожидалась ошибка, получено \(outcome)") }
    }

    /// Кейс: список уже показан (pull-to-refresh), передан кэш.
    /// Ожидание: кэш не читается — на экране до ответа остаются текущие, более свежие элементы.
    func test_refresh_withCache_nonEmptyList_doesNotReadCache() async {
        await sut.refresh(load: page(ids: [1], hasNext: false))
        var isCacheRead = false
        var itemsDuringLoad: [Int] = []

        await sut.refresh(cached: { isCacheRead = true; return [Item(id: 10)] }, load: { [unowned self] _ in
            itemsDuringLoad = sut.items.map(\.id)
            return PaginatedListPage(items: [Item(id: 2)], hasNext: false)
        })

        XCTAssertFalse(isCacheRead)
        XCTAssertEqual(itemsDuringLoad, [1])
    }

    /// Кейс: показаны элементы кэша, загрузчик ответил полной страницей; затем грузится следующая страница.
    /// Ожидание: элементы кэша не участвуют в пагинации — сдвиг считается только по полученным с сервера.
    func test_refresh_withCache_doesNotShiftNextPageContext() async {
        let recorder = ContextRecorder()
        await sut.refresh(cached: { [Item(id: 10), Item(id: 11), Item(id: 12)] }, load: page(ids: [1, 2], hasNext: true))

        await sut.loadNextPage(load: page(ids: [3], hasNext: false, recorder: recorder))

        XCTAssertEqual(recorder.contexts, [PaginationContext(loadedCount: 2, cursor: nil)])
        XCTAssertEqual(sut.items.map(\.id), [1, 2, 3])
    }

    /// Кейс: пока читался кэш, в пустой список локально вставлен элемент.
    /// Ожидание: кэш не затирает вставленный элемент — он актуальнее.
    func test_refresh_withCache_insertDuringCacheRead_keepsInsertedItem() async {
        let gate = Gate()
        var isCacheRead = false
        let cached: PaginatedList<Item>.Cached = { [unowned self] in
            sut.insertIfAbsent(Item(id: 99))
            isCacheRead = true
            return [Item(id: 10)]
        }
        let refresh = Task { await self.sut.refresh(cached: cached, load: self.page(ids: [1], hasNext: false, gate: gate)) }
        await yieldUntil { gate.isWaiting && isCacheRead }

        let itemsAfterCacheRead = sut.items.map(\.id)
        gate.open()
        await refresh.value

        XCTAssertEqual(itemsAfterCacheRead, [99])
    }

    // MARK: - Helpers

    private struct Item: Identifiable, Equatable {
        let id: Int
    }

    private enum TestError: Error, Equatable {
        case any
    }

    /// Копит контексты, с которыми вызывали загрузчик.
    private final class ContextRecorder {
        private(set) var contexts: [PaginationContext] = []

        func record(_ context: PaginationContext) {
            contexts.append(context)
        }
    }

    /// Загрузчик, отдающий страницу с указанными элементами и запоминающий переданный контекст.
    /// - Parameter gate: если задан, загрузчик ждёт его открытия перед ответом.
    private func page(
        ids: [Int],
        hasNext: Bool,
        cursor: Int? = nil,
        gate: Gate? = nil,
        recorder: ContextRecorder? = nil
    ) -> PaginatedList<Item>.Load {
        { context in
            recorder?.record(context)
            await gate?.wait()
            return PaginatedListPage(items: ids.map(Item.init), hasNext: hasNext, nextCursor: cursor)
        }
    }

    /// Загрузчик, всегда завершающийся ошибкой.
    private func failing() -> PaginatedList<Item>.Load {
        { _ in throw TestError.any }
    }

    /// Проверяет, что страница применена.
    private func assertApplied(_ outcome: PaginationOutcome, file: StaticString = #filePath, line: UInt = #line) {
        guard case .applied = outcome else {
            return XCTFail("Ожидался applied, получено \(outcome)", file: file, line: line)
        }
    }
}
