//
//  MessageDraftServiceMock.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

/// Мок сервиса черновиков: черновики и правки задаёт тест (наблюдаются через Observation), вызовы запоминаются.
/// Включение, изменение и выключение правки меняют `edits`, как настоящий сервис.
@MainActor
@Observable
final class MessageDraftServiceMock: MessageDraftServiceProtocol {
    /// Вызов `update` или `save`.
    struct Call: Equatable {
        let text: String
        let conversationId: Int
        let userId: Int
    }

    /// Вызов `endEditing`.
    struct EndEditingCall: Equatable {
        let messageId: Int
        let conversationId: Int
        let userId: Int
    }

    /// Черновики по `conversationId`.
    var drafts: [Int: String] = [:]
    /// Незавершённые правки по `conversationId`.
    var edits: [Int: MessageEditDraft] = [:]
    private(set) var beginEditings: [(messageId: Int, originalText: String, conversationId: Int)] = []
    private(set) var editUpdates: [Call] = []
    private(set) var editSaves: [(edit: MessageEditDraft, conversationId: Int, userId: Int)] = []
    private(set) var endEditings: [EndEditingCall] = []
    /// Все вызовы по порядку — для проверки последовательности.
    private(set) var log: [String] = []
    private(set) var updates: [Call] = []
    private(set) var saves: [Call] = []
    private(set) var removals: [(conversationId: Int, userId: Int)] = []
    private(set) var loadedUserIds: [Int] = []
    /// Вызывается внутри `load` — пока идёт загрузка.
    @ObservationIgnored var onLoad: (@MainActor () async -> Void)?

    func draft(for conversationId: Int) -> String? {
        drafts[conversationId]
    }

    func hasDraft(for conversationId: Int) -> Bool {
        drafts[conversationId] != nil
    }

    func update(text: String, conversationId: Int, userId: Int) {
        updates.append(Call(text: text, conversationId: conversationId, userId: userId))
    }

    func save(text: String, conversationId: Int, userId: Int) {
        saves.append(Call(text: text, conversationId: conversationId, userId: userId))
        log.append("save")
    }

    func edit(for conversationId: Int) -> MessageEditDraft? {
        edits[conversationId]
    }

    func editingMessageId(for conversationId: Int) -> Int? {
        edits[conversationId]?.messageId
    }

    func beginEditing(messageId: Int, originalText: String, conversationId: Int, userId: Int) {
        beginEditings.append((messageId, originalText, conversationId))
        log.append("beginEditing")
        guard edits[conversationId] == nil else { return }
        edits[conversationId] = MessageEditDraft(messageId: messageId, originalText: originalText, text: originalText)
    }

    func updateEdit(text: String, conversationId: Int, userId: Int) {
        editUpdates.append(Call(text: text, conversationId: conversationId, userId: userId))
        edits[conversationId]?.text = text
    }

    func saveEdit(_ edit: MessageEditDraft, conversationId: Int, userId: Int) {
        editSaves.append((edit, conversationId, userId))
        log.append("saveEdit")
        guard edits[conversationId]?.messageId == edit.messageId else { return }
        edits[conversationId] = edit
    }

    func endEditing(messageId: Int, conversationId: Int, userId: Int) {
        endEditings.append(EndEditingCall(messageId: messageId, conversationId: conversationId, userId: userId))
        log.append("endEditing")
        guard edits[conversationId]?.messageId == messageId else { return }
        edits[conversationId] = nil
    }

    func remove(conversationId: Int, userId: Int) {
        removals.append((conversationId, userId))
    }

    func load(userId: Int) async {
        loadedUserIds.append(userId)
        await onLoad?()
    }
}
