//
//  AuthStringsTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

/// Проверки `Auth.strings` во всех языках: шаблоны со ссылками должны содержать ровно те позиционные
/// плейсхолдеры, которые подставляет `AuthViewModel` — иначе ссылка в UI пропадёт или останется сырой `%1$@`.
final class AuthStringsTests: XCTestCase {
    /// Кейс: шаблоны `auth.agreement`, `auth.switch.to_login`, `auth.switch.to_signup` в каждом `<lang>.lproj`.
    /// Ожидание: каждый плейсхолдер из ожидаемого набора встречается ровно один раз, лишних `%…@` нет.
    func test_linkTemplates_containExpectedPlaceholders_inAllLanguages() throws {
        let templates: [(key: String, placeholders: [String])] = [
            ("auth.agreement", ["%1$@", "%2$@"]),
            ("auth.switch.to_login", ["%1$@"]),
            ("auth.switch.to_signup", ["%1$@"]),
        ]

        for language in AppLanguage.allCases {
            let bundle = try localizedBundle(for: language)
            for template in templates {
                let format = bundle.localizedString(forKey: template.key, value: nil, table: "Auth")
                XCTAssertNotEqual(format, template.key, "\(language.rawValue): нет ключа \(template.key)")
                for placeholder in template.placeholders {
                    XCTAssertEqual(occurrences(of: placeholder, in: format), 1, "\(language.rawValue) \(template.key): \(placeholder)")
                }
                XCTAssertEqual(occurrences(of: "@", in: format), template.placeholders.count, "\(language.rawValue) \(template.key): лишние плейсхолдеры")
            }
        }
    }

    /// Bundle директории `<language>.lproj` основного приложения.
    private func localizedBundle(for language: AppLanguage) throws -> Bundle {
        let appBundle = Bundle(for: AuthViewModel.self)
        let path = try XCTUnwrap(appBundle.path(forResource: language.rawValue, ofType: "lproj"), "нет \(language.rawValue).lproj")
        return try XCTUnwrap(Bundle(path: path))
    }

    /// Число вхождений подстроки.
    private func occurrences(of substring: String, in string: String) -> Int {
        string.components(separatedBy: substring).count - 1
    }
}
