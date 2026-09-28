//
//  NetworkLogger.swift
//  Chatik
//

import Foundation

/// Логирует запросы и ответы сетевого слоя в консоль Xcode. Работает только в DEBUG-сборке:
/// в релизе методы пустые, и ни тела запросов, ни ответы сервера в лог не попадают.
///
/// Пишет через `print`, а не `os.Logger`: unified logging обрезает длинные сообщения, а тела ответов бывают большими.
/// Значения чувствительных полей формы (пароль) маскируются.
enum NetworkLogger {
    /// Логирует уходящий запрос: метод, URL, заголовки и тело.
    /// - Parameters:
    ///   - request: отправляемый запрос.
    ///   - bodyFileURL: файл, из которого отправляется тело upload-запроса; `nil` — тело в `request.httpBody`.
    static func logRequest(_ request: URLRequest, bodyFileURL: URL? = nil) {
        #if DEBUG
        print(requestDescription(request, bodyFileURL: bodyFileURL))
        #endif
    }

    /// Логирует полученный ответ: HTTP-статус, время выполнения и тело.
    /// - Parameters:
    ///   - response: ответ сервера.
    ///   - data: тело ответа.
    ///   - request: запрос, на который пришёл ответ.
    ///   - duration: время от отправки запроса до получения ответа.
    static func logResponse(_ response: URLResponse, data: Data, for request: URLRequest, duration: Duration) {
        #if DEBUG
        print(responseDescription(response, data: data, for: request, duration: duration))
        #endif
    }

    /// Логирует запрос, завершившийся ошибкой без ответа сервера (нет сети, таймаут, отмена).
    /// - Parameters:
    ///   - error: ошибка выполнения запроса.
    ///   - request: запрос, который не удалось выполнить.
    ///   - duration: время от отправки запроса до ошибки.
    static func logFailure(_ error: Error, for request: URLRequest, duration: Duration) {
        #if DEBUG
        print(failureDescription(error, for: request, duration: duration))
        #endif
    }
}

#if DEBUG
extension NetworkLogger {
    /// Поля формы, значения которых не выводятся в лог.
    static let maskedFields: Set<String> = ["password"]
    /// Заголовки, значения которых не выводятся в лог. Сейчас `URLSession` подставляет cookie сессии уже после
    /// `URLRequest`, и в лог она не попадает, но список задан заранее — на случай собственных заголовков с секретами.
    static let maskedHeaders: Set<String> = ["cookie", "authorization"]
    /// Максимальная длина тела в логе; длиннее — обрезается.
    static let maxBodyLength = 10_000

    /// Текст лога уходящего запроса.
    /// - Parameters:
    ///   - request: отправляемый запрос.
    ///   - bodyFileURL: файл с телом upload-запроса; `nil` — тело в `request.httpBody`.
    static func requestDescription(_ request: URLRequest, bodyFileURL: URL? = nil) -> String {
        var lines = ["➡️ \(title(of: request))"]
        lines += headerLines(request.allHTTPHeaderFields)
        if let body = requestBodyDescription(request, bodyFileURL: bodyFileURL) {
            lines.append(body)
        }
        return lines.joined(separator: "\n")
    }

    /// Текст лога полученного ответа.
    /// - Parameters:
    ///   - response: ответ сервера.
    ///   - data: тело ответа.
    ///   - request: запрос, на который пришёл ответ.
    ///   - duration: время выполнения запроса.
    static func responseDescription(_ response: URLResponse, data: Data, for request: URLRequest, duration: Duration) -> String {
        let statusCode = (response as? HTTPURLResponse).map { String($0.statusCode) } ?? "—"
        var lines = ["⬅️ \(statusCode) \(title(of: request)) (\(milliseconds(duration)) ms)"]
        if !data.isEmpty {
            lines.append(bodyDescription(data))
        }
        return lines.joined(separator: "\n")
    }

    /// Текст лога запроса, завершившегося ошибкой.
    /// - Parameters:
    ///   - error: ошибка выполнения запроса.
    ///   - request: запрос, который не удалось выполнить.
    ///   - duration: время до ошибки.
    static func failureDescription(_ error: Error, for request: URLRequest, duration: Duration) -> String {
        "❌ \(title(of: request)) (\(milliseconds(duration)) ms)\n\(error)"
    }

    /// Первая строка записи: метод и URL.
    private static func title(of request: URLRequest) -> String {
        "\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "—")"
    }

    /// Заголовки запроса строками `Name: value`, отсортированные по имени; значения секретных заголовков скрыты.
    static func headerLines(_ headers: [String: String]?) -> [String] {
        (headers ?? [:])
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \(maskedHeaders.contains($0.key.lowercased()) ? "***" : $0.value)" }
    }

    /// Тело запроса для лога: для upload — только размер файла (содержимое может быть большим и бинарным),
    /// для формы — строка с замаскированными чувствительными полями. `nil` — тела нет.
    private static func requestBodyDescription(_ request: URLRequest, bodyFileURL: URL?) -> String? {
        if let bodyFileURL {
            let size = (try? bodyFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return "<тело из файла, \(size) байт>"
        }
        guard let body = request.httpBody, !body.isEmpty else { return nil }
        guard let form = String(data: body, encoding: .utf8) else { return "<\(body.count) байт>" }
        return maskFormFields(form)
    }

    /// Заменяет значения чувствительных полей тела `x-www-form-urlencoded` на `***`.
    /// - Parameter form: тело формы вида `key1=value1&key2=value2`.
    static func maskFormFields(_ form: String) -> String {
        form
            .split(separator: "&", omittingEmptySubsequences: false)
            .map { pair in
                let key = pair.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
                guard maskedFields.contains(key) else { return String(pair) }
                return "\(key)=***"
            }
            .joined(separator: "&")
    }

    /// Тело ответа для лога: JSON — с отступами, прочий текст — как есть, бинарные данные — размером.
    /// Слишком длинное тело обрезается до `maxBodyLength` символов.
    /// - Parameter data: тело ответа.
    static func bodyDescription(_ data: Data) -> String {
        guard let text = prettyJSON(data) ?? String(data: data, encoding: .utf8) else {
            return "<\(data.count) байт>"
        }
        guard text.count > maxBodyLength else { return text }
        return "\(text.prefix(maxBodyLength))… <обрезано, всего \(data.count) байт>"
    }

    /// JSON с отступами и без экранирования `/` в URL; `nil`, если данные — не JSON.
    private static func prettyJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    /// Длительность в целых миллисекундах.
    private static func milliseconds(_ duration: Duration) -> Int {
        Int((duration / .milliseconds(1)).rounded())
    }
}
#endif
