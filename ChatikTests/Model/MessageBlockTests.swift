//
//  MessageBlockTests.swift
//  ChatikTests
//

import XCTest
@testable import Chatik

final class MessageBlockTests: XCTestCase {
    private let decoder = JSONDecoder()

    /// Кейс: пример ответа `/messages/getBlockBatch` из документации — изменённый блок, очищенный блок
    /// и ненайденный id.
    /// Ожидание: блоки разобраны с сообщениями и `updatedAt`, пустой блок — с пустым `messages`, `notFoundIds` прочитан.
    func test_decode_batchWithEmptyBlockAndNotFound() throws {
        let json = """
        {
          "blocks": [
            {
              "blockId": 2, "conversationId": 1,
              "messages": [
                {
                  "messageId": 15, "clientId": "6f1c2a9e-4b7d-4e3a-9c51-0d2f8b6a7e14", "conversationId": 1, "blockId": 2, "senderId": 1, "type": "text", "text": "Привет!",
                  "isEdited": false, "createdAt": 1790846400000, "updatedAt": 1790846400000
                }
              ],
              "updatedAt": 1790849000789
            },
            { "blockId": 1, "conversationId": 1, "messages": [], "updatedAt": null }
          ],
          "notFoundIds": [999]
        }
        """

        let batch = try decoder.decode(MessageBlocksBatch.self, from: Data(json.utf8))

        XCTAssertEqual(batch.blocks.map(\.blockId), [2, 1])
        XCTAssertEqual(batch.blocks[0].messages, [.stub])
        XCTAssertEqual(batch.blocks[0].updatedAt, ServerTime(milliseconds: 1_790_849_000_789))
        XCTAssertTrue(batch.blocks[1].messages.isEmpty)
        XCTAssertNil(batch.blocks[1].updatedAt)
        XCTAssertEqual(batch.notFoundIds, [999])
    }
}
