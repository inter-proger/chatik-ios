//
//  FloatingDateTracker.swift
//  Chatik
//

import SwiftUI

/// Состояние плавающей даты над лентой: следит за кадрами строк и прокруткой и решает, видна ли плашка, какую
/// дату она показывает и какой заголовок в ленте она закрывает.
///
/// Кадры строк не наблюдаются и не перерисовывают View; наблюдаемы только `title`, `isVisible` и `coveredHeader`,
/// и присваиваются они только при изменении. Поэтому прокрутка перерисовывает плашку и заголовки лишь при смене
/// даты, появлении и скрытии плашки.
///
/// Прокрутка на iOS 18+ определяется по фазе (`scrollPhaseDidChange`), на iOS 17 — по изменению кадров строк.
/// На iOS 17 кадры сдвигаются и без жеста (новое сообщение, клавиатура, поворот), поэтому после смены данных
/// и высоты ленты изменения кадров `layoutChangeSuppression` не считаются прокруткой, а кадры начальной раскладки,
/// пришедшие раньше секций, не считаются прокруткой вовсе.
@MainActor
@Observable
final class FloatingDateTracker {
    /// Дата на плашке. Сохраняется и после скрытия — для анимации исчезновения.
    private(set) var title: String?
    /// Плашка видна.
    private(set) var isVisible = false
    /// Секция, заголовок которой закрыт видимой плашкой и рисуется прозрачным; `nil` — плашка ничего не закрывает.
    private(set) var coveredHeader: MessageDaySectionID?

    /// Координатное пространство ленты, в котором строки сообщают кадры. `nonisolated`: читается в `Sendable`-замыкании
    /// `onGeometryChange`, которое выполняется вне main actor.
    nonisolated static let coordinateSpace = "messagesFeed"
    /// Отступ плашки от верха ленты; верх плашки — линия, по которой выбирается дата.
    static let topInset: CGFloat = 8
    /// Сколько плашка видна после остановки прокрутки.
    static let hideDelay: Duration = .milliseconds(500)
    /// Сколько после смены данных или высоты ленты изменения кадров не считаются прокруткой (только iOS 17).
    static let layoutChangeSuppression: Duration = .milliseconds(300)
    /// Анимация появления, скрытия и смены даты.
    static let animation: Animation = .easeInOut(duration: 0.25)

    /// Кадры выложенных строк.
    @ObservationIgnored private var rows: [FloatingDateRow: CGRect] = [:]
    /// Заголовки секций ленты.
    @ObservationIgnored private var titles: [MessageDaySectionID: String] = [:]
    /// Идёт прокрутка или с её остановки прошло меньше `hideDelay`.
    @ObservationIgnored private var isScrolling = false
    /// Таймер скрытия после остановки прокрутки (iOS 18+).
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    /// Последнее изменение кадров, считанное прокруткой (iOS 17).
    @ObservationIgnored private var lastMovedAt: ContinuousClock.Instant?
    /// Ожидание остановки кадров перед скрытием (iOS 17); одно на всю прокрутку.
    @ObservationIgnored private var movementTask: Task<Void, Never>?
    /// До какого момента изменения кадров не считаются прокруткой.
    @ObservationIgnored private var suppressedUntil: ContinuousClock.Instant?
    /// Прокрутка определяется по фазе (iOS 18+), а не по кадрам.
    @ObservationIgnored private let usesScrollPhase: Bool
    /// Текущий момент; подменяется в тестах.
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    /// Длительность анимированной смены раскладки (вставки нового сообщения).
    @ObservationIgnored private let layoutAnimationDuration: Duration
    /// Номер последней анимированной смены раскладки, пришедший с кадром.
    @ObservationIgnored private var lastLayoutAnimation = 0

    /// - Parameters:
    ///   - layoutAnimationDuration: длительность анимированной смены раскладки ленты.
    ///   - usesScrollPhase: определять прокрутку по фазе; по умолчанию — на iOS 18+. Подменяется в тестах.
    ///   - now: текущий момент; подменяется в тестах.
    init(
        layoutAnimationDuration: Duration = .zero,
        usesScrollPhase: Bool? = nil,
        now: @escaping () -> ContinuousClock.Instant = { .now }
    ) {
        self.layoutAnimationDuration = layoutAnimationDuration
        if let usesScrollPhase {
            self.usesScrollPhase = usesScrollPhase
        } else if #available(iOS 18, *) {
            self.usesScrollPhase = true
        } else {
            self.usesScrollPhase = false
        }
        self.now = now
    }

    // MARK: - События ленты

    /// Строка сообщила новый кадр. На iOS 17 это признак прокрутки, если секции уже известны и не идёт окно
    /// подавления.
    /// - Parameters:
    ///   - row: строка.
    ///   - frame: визуальный кадр в координатах ленты.
    ///   - layoutAnimation: номер анимированной смены раскладки, в которой снят кадр.
    func update(_ row: FloatingDateRow, frame: CGRect, layoutAnimation: Int = 0) {
        rows[row] = frame
        noteLayoutAnimation(layoutAnimation)
        // Кадры до первых секций — начальная раскладка экрана, а не жест: иначе плашка мигнула бы при открытии,
        // а окно подавления из `setTitles` не началось бы из-за уже идущей «прокрутки».
        guard !usesScrollPhase, !titles.isEmpty, !isSuppressed else {
            refresh(scrollStateChanged: false)
            return
        }
        scrollDidMove()
    }

    /// Строка ушла с экрана.
    /// - Parameter row: строка.
    func remove(_ row: FloatingDateRow) {
        rows[row] = nil
        refresh(scrollStateChanged: false)
    }

    /// Секции ленты изменились: новые заголовки, строки исчезнувших секций забываются.
    /// - Parameter titles: заголовки секций ленты.
    func setTitles(_ titles: [MessageDaySectionID: String]) {
        self.titles = titles
        rows = rows.filter { titles[$0.key.section] != nil }
        layoutDidChange()
        refresh(scrollStateChanged: false)
    }

    /// Раскладка ленты меняется без жеста пользователя (данные, высота ленты, индикатор подгрузки, анимация вставки):
    /// на iOS 17 изменения кадров на время `layoutChangeSuppression` — а при анимации ещё и на её длительность —
    /// не считаются прокруткой. Уже идущее окно не укорачивается. Во время прокрутки окно не начинается — плашка
    /// уже видна.
    /// - Parameter animationDuration: длительность анимации, в которой строки сдвигаются; `.zero` — без анимации.
    func layoutDidChange(animationDuration: Duration = .zero) {
        guard !usesScrollPhase, !isScrolling else { return }
        let until = now() + animationDuration + Self.layoutChangeSuppression
        suppressedUntil = max(suppressedUntil ?? until, until)
    }

    /// Номер анимированной смены раскладки сменился — с первого кадра новой раскладки на время анимации и
    /// `layoutChangeSuppression` изменения кадров не считаются прокруткой. Номер приходит вместе с кадром, а не
    /// отдельным `onChange`: тот выполняется уже после первых кадров новой раскладки, и они успевали бы начать
    /// «прокрутку».
    /// - Parameter layoutAnimation: номер, с которым строка сообщила кадр.
    private func noteLayoutAnimation(_ layoutAnimation: Int) {
        guard layoutAnimation != lastLayoutAnimation else { return }
        lastLayoutAnimation = layoutAnimation
        layoutDidChange(animationDuration: layoutAnimationDuration)
    }

    /// Фаза прокрутки изменилась (iOS 18+).
    /// - Parameter isActive: пользователь тянет ленту или она прокручивается по инерции.
    func scrollPhaseDidChange(isActive: Bool) {
        guard isActive else {
            scheduleHide()
            return
        }
        hideTask?.cancel()
        setScrolling(true)
    }

    // MARK: - Состояние

    /// Идёт окно подавления после изменения раскладки.
    private var isSuppressed: Bool {
        guard let suppressedUntil else { return false }
        return now() < suppressedUntil
    }

    /// Лента сдвинулась (iOS 17): прокрутка идёт, скрытие откладывается до остановки кадров на `hideDelay`.
    /// Кадры приходят от каждой строки на каждом кадре анимации, поэтому здесь только отметка времени, а таймер
    /// скрытия один на всю прокрутку.
    private func scrollDidMove() {
        lastMovedAt = .now
        setScrolling(true)
        guard movementTask == nil else { return }
        movementTask = Task { [weak self] in await self?.hideWhenMovementStops() }
    }

    /// Ждёт, пока кадры не перестанут меняться на `hideDelay`, и скрывает плашку (iOS 17).
    private func hideWhenMovementStops() async {
        while let lastMovedAt, ContinuousClock.now < lastMovedAt + Self.hideDelay {
            guard (try? await Task.sleep(until: lastMovedAt + Self.hideDelay, clock: .continuous)) != nil else { return }
        }
        movementTask = nil
        setScrolling(false)
    }

    /// Запускает таймер скрытия после остановки прокрутки (iOS 18+); повторный вызов перезапускает его.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            guard (try? await Task.sleep(for: Self.hideDelay)) != nil else { return }
            self?.setScrolling(false)
        }
    }

    /// Меняет признак прокрутки и пересчитывает плашку с анимацией появления или скрытия.
    /// - Parameter scrolling: идёт ли прокрутка.
    private func setScrolling(_ scrolling: Bool) {
        let changed = isScrolling != scrolling
        isScrolling = scrolling
        refresh(scrollStateChanged: changed)
    }

    /// Пересчитывает дату и видимость плашки. Плашка появляется и скрывается с анимацией, только когда
    /// начинается или заканчивается прокрутка. Когда заголовок пересекает линию плашки, они меняются местами
    /// в одном кадре без анимации — плашка стоит ровно на месте заголовка.
    /// - Parameter scrollStateChanged: пересчёт вызван началом или концом прокрутки.
    private func refresh(scrollStateChanged: Bool) {
        let date = FloatingDateResolver.resolve(
            rows: rows,
            titles: titles,
            line: Self.topInset
        )
        let visible = isScrolling && date != nil
        let newTitle = visible ? date?.title : title
        let covered = visible ? date?.section : nil
        guard visible != isVisible || newTitle != title || covered != coveredHeader else { return }
        let animates = visible != isVisible ? scrollStateChanged : newTitle != title
        var transaction = Transaction(animation: animates ? Self.animation : nil)
        transaction.disablesAnimations = !animates
        withTransaction(transaction) {
            apply(visible: visible, title: newTitle, covered: covered)
        }
    }

    /// Присваивает наблюдаемое состояние, только если оно изменилось.
    /// - Parameters:
    ///   - visible: видна ли плашка.
    ///   - title: дата на плашке.
    ///   - covered: закрытый плашкой заголовок.
    private func apply(visible: Bool, title: String?, covered: MessageDaySectionID?) {
        if isVisible != visible {
            isVisible = visible
        }
        if self.title != title {
            self.title = title
        }
        if coveredHeader != covered {
            coveredHeader = covered
        }
    }
}

extension View {
    /// Сообщает трекеру плавающей даты визуальный кадр строки, пока она выложена.
    /// - Parameters:
    ///   - row: строка ленты.
    ///   - tracker: трекер.
    ///   - layoutAnimation: номер анимированной смены раскладки ленты, к которой относится строка.
    func trackFrame(_ row: FloatingDateRow, in tracker: FloatingDateTracker, layoutAnimation: Int = 0) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(FloatingDateTracker.coordinateSpace))
        } action: { frame in
            tracker.update(row, frame: frame, layoutAnimation: layoutAnimation)
        }
        .onDisappear { tracker.remove(row) }
    }
}
