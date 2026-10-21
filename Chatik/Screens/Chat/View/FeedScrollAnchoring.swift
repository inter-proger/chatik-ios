//
//  FeedScrollAnchoring.swift
//  Chatik
//

import SwiftUI
import UIKit

/// Положение ленты относительно её низа (самых новых сообщений). Меряется по якорю низа — строке нулевой высоты
/// у начала данных: она выкладывается всегда, даже когда сообщения у низа далеко не выложены.
///
/// Наблюдаемы только `isAtBottom` и `isBeyondThreshold`, и присваиваются они только при смене: прокрутка
/// не перерисовывает ленту.
@MainActor
@Observable
final class FeedBottomTracker {
    /// Самые новые сообщения видны: до низа ленты не больше `atBottomTolerance`.
    private(set) var isAtBottom = true
    /// Лента отлистана от низа дальше `thresholdScreens` высот видимой области — показывается кнопка «вниз».
    private(set) var isBeyondThreshold = false

    /// Расстояние от низа видимой области до низа ленты, в точках.
    @ObservationIgnored private(set) var distanceFromBottom: CGFloat = 0
    /// Высота видимой области ленты.
    @ObservationIgnored private(set) var viewportHeight: CGFloat = 0
    /// Последний визуальный `minY` якоря низа в координатах ленты.
    @ObservationIgnored private var anchorMinY: CGFloat?

    /// Допуск «лента внизу»: дробные координаты и короткая прокрутка не считаются уходом от низа.
    static let atBottomTolerance: CGFloat = 24
    /// Порог кнопки «вниз» в высотах видимой области.
    static let thresholdScreens: CGFloat = 1.5
    /// Дальше скольких высот видимой области кнопка «вниз» переходит к низу без анимации: анимированная прокрутка
    /// через сотни ленивых строк дёргается.
    static let jumpScreens: CGFloat = 2.5

    /// Переход к низу без анимации — лента отлистана далеко.
    var shouldJumpToBottom: Bool {
        distanceFromBottom > Self.jumpScreens * viewportHeight
    }

    /// Якорь низа сообщил кадр.
    /// - Parameter minY: визуальный `minY` якоря в координатах ленты.
    func anchorDidMove(minY: CGFloat) {
        anchorMinY = minY
        refresh()
    }

    /// Сменилась высота видимой области (клавиатура, поворот).
    /// - Parameter height: высота ленты.
    func viewportDidChange(height: CGFloat) {
        viewportHeight = height
        refresh()
    }

    /// Пересчитывает расстояние и флаги; флаги присваиваются только при смене. Пока высота ленты неизвестна, не
    /// пересчитывает: кадр якоря без неё выглядел бы как отлистанная лента, и мигнула бы кнопка «вниз».
    private func refresh() {
        guard let anchorMinY, viewportHeight > 0 else { return }
        distanceFromBottom = anchorMinY - viewportHeight
        let atBottom = distanceFromBottom <= Self.atBottomTolerance
        if atBottom != isAtBottom {
            isAtBottom = atBottom
        }
        let beyondThreshold = distanceFromBottom > Self.thresholdScreens * viewportHeight
        if beyondThreshold != isBeyondThreshold {
            isBeyondThreshold = beyondThreshold
        }
    }
}

/// Удержание ленты (решение 8 в `docs/unread-messages.md`): пока лента не внизу, держит видимую строку-якорь на месте
/// при любой смене раскладки — вставке нового сообщения в начало данных и уточнении оценочных высот `LazyVStack`
/// (раскладка после вставки идёт в несколько проходов). В перевёрнутом `ScrollView` на iOS 17 для этого нет API
/// SwiftUI: `scrollPosition(id:)` позицию не удерживает.
///
/// Сдвиг меряется по `minY` якоря в координатах содержимого прокрутки (`contentSpace`): прокрутка его не меняет,
/// а сдвиг содержимого раскладкой меняет ровно на величину сдвига. На неё же сдвигается `contentOffset` у
/// `UIScrollView` — прямо из `onGeometryChange` строки, до отрисовки кадра. Видимый `minY` для этого не годится:
/// в момент колбэка он бывает не согласован с `contentOffset`. Прирост `contentSize` — тоже: при смене данных
/// `LazyVStack` пересчитывает оценку всей высоты. Внизу ленты якоря нет: новое сообщение сдвигает ленту.
///
/// Доступ к `UIScrollView` — обход SwiftUI (поиск предка, `FeedScrollViewLocator`), поэтому изолирован в этом типе.
/// При крупном обновлении iOS сценарий удержания нужно проверить заново.
@MainActor
final class FeedOffsetKeeper {
    /// Координатное пространство содержимого прокрутки — внутри `ScrollView`, до отражения.
    nonisolated static let contentSpace = "feedContent"

    /// Вызывается после компенсации сдвига — лента сдвинулась без жеста.
    var onCompensation: () -> Void = {}
    /// Держать ли якорь: лента не внизу. Снятие забывает якорь и завершает возврат к низу.
    var isHolding = false {
        didSet {
            guard !isHolding else { return }
            anchor = nil
            returnDeadline = nil
        }
    }

    /// Сколько длится возврат к низу без компенсации, если лента так и не дошла до низа (прокрутку прервал жест).
    static let returnToBottomTimeout: Duration = .seconds(1)

    private weak var scrollView: UIScrollView?
    /// Строка-якорь и её `minY` в координатах содержимого.
    private var anchor: (id: MessageClientKey, contentMinY: CGFloat)?
    /// Высота видимой области — чтобы понять, видна ли строка.
    private var viewportHeight: CGFloat = 0
    /// До какого момента лента возвращается к низу и сдвиги не компенсируются; `nil` — возврата нет.
    private var returnDeadline: ContinuousClock.Instant?
    private let now: () -> ContinuousClock.Instant

    /// - Parameter now: текущий момент; подменяется в тестах.
    init(now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.now = now
    }

    /// Лента возвращается к низу (кнопка «вниз» или своё сообщение). Пока она не дошла до низа, сдвиги не
    /// компенсируются: вставка своего сообщения идёт одновременно с прокруткой, и компенсация сдвигала бы
    /// `contentOffset` навстречу ей, а при переходе без анимации — уводила бы ленту от низа уточнением оценочных
    /// высот. Если низа так и не достигнуто (прокрутку прервал жест), удержание возвращается через
    /// `returnToBottomTimeout`.
    func beginReturnToBottom() {
        anchor = nil
        returnDeadline = now() + Self.returnToBottomTimeout
    }

    /// Запоминает `UIScrollView` ленты.
    /// - Parameter scrollView: найденный предок ленты.
    func attach(_ scrollView: UIScrollView) {
        self.scrollView = scrollView
    }

    /// Сменилась высота видимой области.
    /// - Parameter height: высота ленты.
    func viewportDidChange(height: CGFloat) {
        viewportHeight = height
    }

    /// Строка сообщила кадр. Для якоря компенсирует сдвиг содержимого раскладкой. Без якоря или когда якорь ушёл
    /// с экрана якорем становится эта строка, если она видна.
    /// - Parameters:
    ///   - id: строка.
    ///   - contentMinY: `minY` в координатах содержимого прокрутки.
    ///   - visualMinY: визуальный `minY` в координатах ленты — только чтобы понять, видна ли строка.
    func rowDidMove(_ id: MessageClientKey, contentMinY: CGFloat, visualMinY: CGFloat) {
        guard isHolding, !isReturningToBottom, let scrollView else { return }
        let isVisible = visualMinY >= 0 && visualMinY <= viewportHeight
        guard let anchor else {
            if isVisible {
                self.anchor = (id, contentMinY)
            }
            return
        }
        guard anchor.id == id else { return }
        let shift = contentMinY - anchor.contentMinY
        self.anchor = isVisible ? (id, contentMinY) : nil
        guard abs(shift) > 0.5 else { return }
        scrollView.contentOffset.y += shift
        onCompensation()
    }

    /// Идёт возврат к низу: срок ещё не вышел. После срока лента снова удерживается.
    private var isReturningToBottom: Bool {
        returnDeadline.map { now() < $0 } ?? false
    }

    /// Строка ушла из раскладки; если это якорь, якорем станет следующая видимая строка.
    /// - Parameter id: строка.
    func rowDidDisappear(_ id: MessageClientKey) {
        guard anchor?.id == id else { return }
        anchor = nil
    }
}

/// Находит `UIScrollView` ленты среди предков и передаёт его `FeedOffsetKeeper`. Ставится в фон содержимого ленты.
struct FeedScrollViewLocator: UIViewRepresentable {
    let keeper: FeedOffsetKeeper

    func makeUIView(context: Context) -> LocatorView {
        let view = LocatorView()
        view.keeper = keeper
        return view
    }

    func updateUIView(_ view: LocatorView, context: Context) {}

    /// Пустая View, которая при появлении в окне ищет ближайший `UIScrollView` среди предков.
    final class LocatorView: UIView {
        weak var keeper: FeedOffsetKeeper?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var view = superview
            while let current = view {
                if let scrollView = current as? UIScrollView {
                    keeper?.attach(scrollView)
                    return
                }
                view = current.superview
            }
        }
    }
}
