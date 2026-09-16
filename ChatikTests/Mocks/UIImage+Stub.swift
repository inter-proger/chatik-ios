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

    /// Шумное изображение из случайных байтов — плохо сжимается, поэтому заметно превышает лимит на больших размерах.
    /// - Parameter size: размер в пикселях.
    static func noise(size: CGSize) -> UIImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerRow = width * 4
        var bytes = Data(count: bytesPerRow * height)
        bytes.withUnsafeMutableBytes { arc4random_buf($0.baseAddress!, $0.count) }

        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        bytes.withUnsafeBytes { source in
            context.data?.copyMemory(from: source.baseAddress!, byteCount: source.count)
        }
        return UIImage(cgImage: context.makeImage()!)
    }
}
