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

    /// Задерживает загрузчик, пока тест его не отпустит: так порядок ответов задаётся тестом, а не планировщиком.
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?

        /// `true`, пока загрузчик ждёт у шлагбаума.
        var isWaiting: Bool {
            continuation != nil
        }

        /// Приостанавливает вызывающего до `open()`.
        func wait() async {
            await withCheckedContinuation { continuation = $0 }
        }

        /// Отпускает ждущего загрузчика.
        func open() {
            continuation?.resume()
            continuation = nil
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
