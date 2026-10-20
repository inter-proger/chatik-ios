//
//  CommonStrings.swift
//  Chatik
//

import Foundation

/// Локализованные общие строки (таблица `Common.strings`).
@MainActor
enum CommonStrings {
    private static let table = "Common"

    static var errorUnknown: String { localized("common.error.unknown") }
    static var errorNoConnection: String { localized("common.error.no_connection") }

    static var errorInvalidLogin: String { localized("common.error.api.invalid_login") }
    static var errorInvalidPassword: String { localized("common.error.api.invalid_password") }
    static var errorInvalidName: String { localized("common.error.api.invalid_name") }
    static var errorInvalidParameters: String { localized("common.error.api.invalid_parameters") }
    static var errorInvalidText: String { localized("common.error.api.invalid_text") }
    static var errorLoginAlreadyTaken: String { localized("common.error.api.login_already_taken") }
    static var errorWrongCredentials: String { localized("common.error.api.wrong_credentials") }
    static var errorUnauthorized: String { localized("common.error.api.unauthorized") }
    static var errorFileMissing: String { localized("common.error.api.file_missing") }
    static var errorFileTooLarge: String { localized("common.error.api.file_too_large") }
    static var errorFileNotImage: String { localized("common.error.api.file_not_image") }
    static var errorFileNotFound: String { localized("common.error.api.file_not_found") }
    static var errorFileSaveFailed: String { localized("common.error.api.file_save_failed") }
    static var errorUserNotFound: String { localized("common.error.api.user_not_found") }
    static var errorConversationWithSelf: String { localized("common.error.api.conversation_with_self") }
    static var errorConversationNotFound: String { localized("common.error.api.conversation_not_found") }
    static var errorMessageNotFound: String { localized("common.error.api.message_not_found") }
    static var errorMessageBlockNotFound: String { localized("common.error.api.message_block_not_found") }
    static var errorMessageEditForbidden: String { localized("common.error.api.message_edit_forbidden") }
    static var errorInternalServer: String { localized("common.error.api.internal_server") }

    /// Возвращает локализованную строку по ключу из таблицы `Common`.
    /// - Parameter key: ключ в `Common.strings`.
    private static func localized(_ key: String) -> String {
        Localized.string(key, table: table)
    }
}
