//
//  InAppNotificationsModifier.swift
//  Chatik
//

import SwiftUI
import UIKit

extension View {
    /// Показывает уведомления сервиса поверх приложения, в том числе поверх листов. Вешается один раз — на корень.
    /// - Parameter service: сервис уведомлений.
    func inAppNotifications(_ service: any InAppNotificationServiceProtocol) -> some View {
        modifier(InAppNotificationsModifier(service: service))
    }
}

/// Создаёт окно уведомлений в сцене корня и передаёт сервису активность этой сцены.
///
/// Модификатор живёт в корне каждой сцены (на iPad их может быть несколько), поэтому у него свой идентификатор
/// сцены. `.inactive` тоже выключает сцену (шторка, переключатель приложений); закрываемая сцена до этого уходит
/// в `.background`. Фаза передаётся и при появлении: `onChange` на начальное значение не срабатывает, а сервис
/// создаётся без активных сцен.
private struct InAppNotificationsModifier: ViewModifier {
    let service: any InAppNotificationServiceProtocol

    @Environment(\.scenePhase) private var scenePhase
    @State private var presenter = InAppNotificationWindowPresenter()
    @State private var sceneId = UUID()

    func body(content: Content) -> some View {
        content
            .background {
                WindowSceneReader { scene in
                    presenter.install(in: scene, sceneId: sceneId, service: service)
                }
            }
            .onAppear {
                service.setActive(scenePhase == .active, sceneId: sceneId)
            }
            .onChange(of: scenePhase) { _, phase in
                service.setActive(phase == .active, sceneId: sceneId)
            }
    }
}

/// Сообщает сцену, в которой показана View, как только View попала в окно.
private struct WindowSceneReader: UIViewRepresentable {
    let onScene: (UIWindowScene) -> Void

    func makeUIView(context: Context) -> SceneReportingView {
        let view = SceneReportingView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: SceneReportingView, context: Context) {
        view.onScene = onScene
        view.reportScene()
    }
}

/// UIKit-View, которая знает своё окно и через него — сцену.
private final class SceneReportingView: UIView {
    var onScene: (UIWindowScene) -> Void = { _ in }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportScene()
    }

    /// Сообщает сцену, если View уже в окне.
    func reportScene() {
        guard let scene = window?.windowScene else { return }
        onScene(scene)
    }
}
