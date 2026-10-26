//
//  AvatarSource.swift
//  Chatik
//

import Foundation

/// Откуда взять изображение для аватара.
enum AvatarSource: Hashable, CaseIterable {
    case gallery
    case camera
}
