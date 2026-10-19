//
//  ChatViewModel+Editing.swift
//  Chatik
//

import Foundation
import os

/// Редактирование своих сообщений: меню по долгому нажатию, режим редактирования и подтверждение правки.
///
/// Правку хранит сервис черновиков рядом с черновиком, а запрос выполняет `MessageEditService` — он переживает уход
/// с экрана. Исход запроса — своего или начатого на прошлом открытии экрана — ждёт только `observeEditSubmission`,
/// задача которого живёт, пока экран показан. Ошибка, которую экран не успел показать, остаётся в сервисе до
/// следующего открытия.
extension ChatViewModel {
    /// Обработчик пункта меню по долгому нажатию на сообщение.
    /// - Parameters:
    ///   - action: выбранное действие.
    ///   - message: сообщение, у которого открыто меню.
    func didSelectAction(_ action: MessageAction, for message: MessageDisplayModel) {
        switch action {
        case .edit:
            beginEditing(message)
        }
    }

    /// Включает режим редактирования: черновик уходит в БД (точка сохранения) и остаётся нетронутым, в поле
    /// подставляется текст сообщения. При уже включённом режиме ничего не делает — действие в это время скрыто.
    /// - Parameter displayModel: редактируемое сообщение ленты.
    private func beginEditing(_ displayModel: MessageDisplayModel) {
        guard inputMode == .compose, let draftUserId,
              let message = serverMessages.first(where: { $0.clientKey == displayModel.id }) else { return }
        let conversationId = conversation.conversationId
        draftService.save(text: messageText, conversationId: conversationId, userId: draftUserId)
        draftService.beginEditing(messageId: message.messageId, originalText: message.text, conversationId: conversationId, userId: draftUserId)
        guard let edit = draftService.edit(for: conversationId), edit.messageId == message.messageId else { return }
        setInputMode(.editing(messageId: edit.messageId, originalText: edit.originalText))
        replaceInput(with: edit.text)
    }

    /// Крестик на плашке: выключает режим редактирования и возвращает в поле черновик. Во время запроса крестик
    /// скрыт, и вызов ничего не делает.
    func cancelEditing() {
        guard case let .editing(messageId, _) = inputMode, !isEditSubmitting, let draftUserId else { return }
        draftService.endEditing(messageId: messageId, conversationId: conversation.conversationId, userId: draftUserId)
        switchToCompose()
    }

    /// Подтверждение правки. Текст, совпадающий с текущим текстом сообщения после обрезки, закрывает режим без
    /// запроса. Иначе текст правки уходит в БД и запускается запрос; кнопка и поле блокируются сразу, а результат
    /// приходит через `waitForSubmission`.
    func submitEdit() {
        guard case let .editing(messageId, originalText) = inputMode, let draftUserId else { return }
        let conversationId = conversation.conversationId
        guard Self.trimmed(messageText) != Self.trimmed(editedMessageText ?? originalText) else {
            draftService.endEditing(messageId: messageId, conversationId: conversationId, userId: draftUserId)
            switchToCompose()
            return
        }
        let edit = MessageEditDraft(messageId: messageId, originalText: originalText, text: messageText)
        draftService.saveEdit(edit, conversationId: conversationId, userId: draftUserId)
        guard editService.submit(conversationId: conversationId, userId: draftUserId) != nil else {
            Logger.chat.error("Запрос правки не начат: сервис правок отказал")
            return
        }
        editSubmissionRequests?.yield()
    }

    /// Ждёт исходов запросов правки, пока экран показан, — для `.task` экрана. Сначала — запроса, начатого
    /// на прошлом открытии (или его непоказанной ошибки), затем — каждого запроса, начатого `submitEdit`.
    /// Отмена задачи (уход с экрана) прекращает ожидание, и ошибка остаётся в сервисе до следующего открытия.
    func observeEditSubmission() async {
        let (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        editSubmissionRequests = continuation
        continuation.yield()
        for await _ in requests {
            await awaitEditSubmission()
        }
    }

    /// Дожидается запроса правки и применяет исход, если экран ещё показан. Успех (или отсутствие запроса) сверяет
    /// режим с сервисом: успешный запрос выключил режим, и в поле возвращается черновик. Ошибка забирается
    /// из сервиса и показывается, режим остаётся. Отмена выходом из аккаунта не показывается и режим не трогает:
    /// сервис черновиков к этому моменту уже очистил память.
    private func awaitEditSubmission() async {
        let conversationId = conversation.conversationId
        do {
            try await editService.waitForSubmission(conversationId: conversationId)
        } catch is CancellationError {
            return
        } catch {
            // Ошибка ждёт в сервисе и забирается ниже — только если экран ещё показан.
        }
        guard !Task.isCancelled else { return }
        if let failure = editService.takeFailure(conversationId: conversationId) {
            errorMessage = ErrorMessages.message(for: failure)
            return
        }
        syncInputModeWithService()
    }

    /// Выключает режим, если сервис черновиков уже выключил его, — после успешного запроса.
    private func syncInputModeWithService() {
        guard inputMode != .compose, draftService.editingMessageId(for: conversation.conversationId) == nil else { return }
        switchToCompose()
    }

    /// Переключает поле в режим нового сообщения и возвращает в него черновик.
    private func switchToCompose() {
        setInputMode(.compose)
        replaceInput(with: draftService.draft(for: conversation.conversationId) ?? "")
    }

    /// Текст без краевых пробелов и невидимых символов — так же сервер сравнивает правку с текущим текстом.
    /// - Parameter text: текст.
    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: MessageTextValidator.trimmedCharacters)
    }
}

extension Logger {
    /// Лог экрана переписки: сбои, которые не показываются пользователю, но не должны теряться молча.
    static let chat = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Chatik", category: "Chat")
}
