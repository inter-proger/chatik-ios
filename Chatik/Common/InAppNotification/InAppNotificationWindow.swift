//
//  InAppNotificationWindow.swift
//  Chatik
//

import SwiftUI
import UIKit

/// Прозрачное окно уведомлений над окном приложения и окном меню сообщения.
///
/// Окно никогда не становится ключевым: иначе поле ввода потеряет фокус и клавиатура спрячется. Касания принимает
/// только кадр карточки: с iOS 18 `super.hitTest` для SwiftUI-содержимого возвращает хостинг-вью для любой точки,
/// и на карточке, и мимо неё, — по возвращённой View их не различить. Поэтому точка сверяется с кадром, который
/// сообщает `InAppNotificationHost`.
final class InAppNotificationWindow: UIWindow {
    /// Кадр карточки в координатах окна; `.zero` — касания проходят насквозь.
    var cardFrame: CGRect = .zero

    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard cardFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Создаёт окно уведомлений в сцене один раз и держит его, пока жив корень сцены.
///
/// Окно видно, только пока в этой сцене показано уведомление, и ещё `hideDelay` после — чтобы доиграла анимация
/// ухода карточки. Постоянно видимое окно во весь экран UIKit учитывает при выборе вида статус-бара и ориентации,
/// а пустому окну влиять на них незачем.
@MainActor
final class InAppNotificationWindowPresenter {
    private var window: InAppNotificationWindow?
    private var service: (any InAppNotificationServiceProtocol)?
    private var sceneId: UUID?
    /// Отложенное скрытие окна после ухода карточки.
    private var hideTask: Task<Void, Never>?

    /// Уровень окна: выше окна меню сообщения (`.normal + 1`) — ошибка не прячется под его затемнением.
    private static let windowLevel: UIWindow.Level = .normal + 2
    /// Сколько окно остаётся видимым после ухода карточки: анимация ухода с запасом на затухание пружины.
    private static let hideDelay: Duration = .seconds(InAppNotificationHost.animationDuration * 2)

    /// Создаёт окно уведомлений в сцене и начинает следить, когда его показывать; повторный вызов ничего не делает.
    /// - Parameters:
    ///   - scene: сцена корня.
    ///   - sceneId: идентификатор сцены в сервисе уведомлений.
    ///   - service: сервис уведомлений, за которым наблюдает окно.
    func install(in scene: UIWindowScene, sceneId: UUID, service: any InAppNotificationServiceProtocol) {
        guard window == nil else { return }
        let window = InAppNotificationWindow(windowScene: scene)
        let host = UIHostingController(rootView: InAppNotificationHost(
            service: service,
            sceneId: sceneId,
            onCardFrameChange: { [weak window] frame in window?.cardFrame = frame }
        ))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.backgroundColor = .clear
        window.windowLevel = Self.windowLevel
        window.isHidden = true
        self.window = window
        self.service = service
        self.sceneId = sceneId
        observeService()
    }

    /// Сверяет видимость окна с сервисом и подписывается на следующее изменение.
    ///
    /// Observation сообщает об изменении до записи нового значения, синхронно на main (сервис — `@MainActor`).
    /// Окно открывается сразу, ещё до изменения: тогда новая карточка появляется с анимацией уже в видимом окне.
    /// Нужно ли окно, решается после изменения: если уведомления в этой сцене нет, окно скрывается с задержкой.
    /// Поэтому изменение, которое этой сцены не касается (показ в другой сцене), открывает пустое окно на время
    /// `hideDelay` — касания через него проходят насквозь.
    private func observeService() {
        guard let service, let sceneId else { return }
        let isShownHere = withObservationTracking {
            service.current != nil && service.presentingSceneId == sceneId
        } onChange: { [weak self] in
            MainActor.assumeIsolated { self?.showWindow() }
            Task { @MainActor [weak self] in self?.observeService() }
        }
        guard !isShownHere else { return }
        scheduleHide()
    }

    /// Показывает окно и отменяет отложенное скрытие.
    private func showWindow() {
        hideTask?.cancel()
        hideTask = nil
        // `isHidden = false`, а не `makeKeyAndVisible()`: окно не забирает фокус у поля ввода.
        window?.isHidden = false
    }

    /// Скрывает окно через `hideDelay`, если до тех пор оно снова не понадобится.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hideDelay)
            guard let self, !Task.isCancelled else { return }
            window?.isHidden = true
        }
    }
}
