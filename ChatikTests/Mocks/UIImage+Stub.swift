//
//  UIImage+Stub.swift
//  ChatikTests
//

import UIKit

extension UIImage {
    /// Одноцветное изображение заданного размера в пикселях (scale 1).
    /// - Parameter size: размер в пикселях.
    static func stub(size: CGSize = CGSize(width: 10, height: 10)) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
