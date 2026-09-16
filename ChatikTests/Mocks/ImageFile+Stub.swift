//
//  ImageFile+Stub.swift
//  ChatikTests
//

import Foundation
@testable import Chatik

extension ImageFile {
    /// JPEG во временной директории; сам файл на диске не создаётся.
    static let stub = ImageFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("stub.jpg"), type: .jpeg)
}
