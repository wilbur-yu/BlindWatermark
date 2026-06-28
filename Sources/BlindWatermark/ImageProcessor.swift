import Foundation
import AppKit
import CoreImage
import Accelerate

// MARK: - 图片处理器：负责图片读写、YUV 色彩空间转换

struct ImageProcessor {

    // MARK: - 从文件加载图片像素数据

    /// 加载图片文件，返回 BGR 顺序的浮点像素数组 [height][width][3] 以及 alpha 通道
    static func loadImage(from path: String) -> (pixels: [[[Float]]], width: Int, height: Int, alpha: [Float]?)? {
        guard let nsImage = NSImage(contentsOfFile: path) else {
            return nil
        }
        return loadImage(from: nsImage)
    }

    /// 从 NSImage 加载像素数据
    static func loadImage(from nsImage: NSImage) -> (pixels: [[[Float]]], width: Int, height: Int, alpha: [Float]?)? {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return loadImage(from: cgImage)
    }

    /// 从 CGImage 加载像素数据，返回 BGR 顺序
    static func loadImage(from cgImage: CGImage) -> (pixels: [[[Float]]], width: Int, height: Int, alpha: [Float]?)? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bitsPerComponent = cgImage.bitsPerComponent
        let bitmapInfo = cgImage.bitmapInfo
        let colorSpace = cgImage.colorSpace

        // 创建上下文读取像素
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        guard let ctx = context else { return nil }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.draw(cgImage, in: rect)

        guard let data = ctx.data else { return nil }
        let ctxBytesPerRow = ctx.bytesPerRow
        let byteData = data.bindMemory(to: UInt8.self, capacity: ctxBytesPerRow * height)

        var pixels: [[[Float]]] = []
        var alpha: [Float]? = nil
        var hasAlpha = false

        pixels.reserveCapacity(height)

        for y in 0..<height {
            var row: [[Float]] = []
            row.reserveCapacity(width)
            let rowBase = y * ctxBytesPerRow
            for x in 0..<width {
                let offset = rowBase + x * 4
                let r = Float(byteData[offset])
                let g = Float(byteData[offset + 1])
                let b = Float(byteData[offset + 2])
                let a = Float(byteData[offset + 3])

                // 去除预乘 alpha
                if a > 0 && a < 255 {
                    let invAlpha = 255.0 / a
                    row.append([b * invAlpha, g * invAlpha, r * invAlpha])
                    hasAlpha = true
                } else {
                    row.append([b, g, r])
                }
            }
            pixels.append(row)
        }

        // 提取 alpha 通道
        if hasAlpha {
            var alphaArr = [Float](repeating: 0, count: width * height)
            for y in 0..<height {
                let rowBase = y * ctxBytesPerRow
                for x in 0..<width {
                    alphaArr[y * width + x] = Float(byteData[rowBase + x * 4 + 3])
                }
            }
            alpha = alphaArr
        }

        return (pixels, width, height, alpha)
    }

    // MARK: - BGR 转 YUV

    /// BGR -> YUV 色彩空间转换（OpenCV 风格，BT.601）
    /// 输入：BGR 像素 [height][width][3]
    /// 输出：YUV 像素 [height][width][3]
    static func bgrToYUV(_ bgr: [[[Float]]]) -> [[[Float]]] {
        let height = bgr.count
        guard height > 0 else { return [] }
        let width = bgr[0].count

        var yuv: [[[Float]]] = []
        yuv.reserveCapacity(height)

        for y in 0..<height {
            var row: [[Float]] = []
            row.reserveCapacity(width)
            for x in 0..<width {
                let b = bgr[y][x][0]
                let g = bgr[y][x][1]
                let r = bgr[y][x][2]

                // OpenCV BGR2YUV 转换（YCrCb, BT.601）
                let Y = 0.299 * r + 0.587 * g + 0.114 * b
                let U = -0.14713 * r - 0.28886 * g + 0.436 * b + 128.0
                let V = 0.615 * r - 0.51499 * g - 0.10001 * b + 128.0

                row.append([Y, U, V])
            }
            yuv.append(row)
        }
        return yuv
    }

    /// YUV -> BGR 色彩空间转换
    static func yuvToBGR(_ yuv: [[[Float]]]) -> [[[Float]]] {
        let height = yuv.count
        guard height > 0 else { return [] }
        let width = yuv[0].count

        var bgr: [[[Float]]] = []
        bgr.reserveCapacity(height)

        for y in 0..<height {
            var row: [[Float]] = []
            row.reserveCapacity(width)
            for x in 0..<width {
                let Y = yuv[y][x][0]
                let U = yuv[y][x][1]
                let V = yuv[y][x][2]

                let Uoff = U - 128.0
                let Voff = V - 128.0

                var r = Y + 1.13983 * Voff
                var g = Y - 0.39465 * Uoff - 0.58060 * Voff
                var b = Y + 2.03211 * Uoff

                r = max(0, min(255, r))
                g = max(0, min(255, g))
                b = max(0, min(255, b))

                row.append([b, g, r]) // BGR 顺序
            }
            bgr.append(row)
        }
        return bgr
    }

    // MARK: - 保存图片

    /// 将 BGR 像素数组保存为 PNG/JPG 文件
    static func saveImage(bgr: [[[Float]]], alpha: [Float]?, width: Int, height: Int, to path: String) -> Bool {
        let hasAlpha = alpha != nil

        var rgbaData = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let b = UInt8(max(0, min(255, bgr[y][x][0])))
                let g = UInt8(max(0, min(255, bgr[y][x][1])))
                let r = UInt8(max(0, min(255, bgr[y][x][2])))
                let a = hasAlpha ? UInt8(max(0, min(255, alpha![y * width + x]))) : 255

                rgbaData[offset] = r
                rgbaData[offset + 1] = g
                rgbaData[offset + 2] = b
                rgbaData[offset + 3] = a
            }
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: &rgbaData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        guard let cgImage = context.makeImage() else { return false }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))

        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return false
        }

        let fileType: NSBitmapImageRep.FileType = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png
        let properties: [NSBitmapImageRep.PropertyKey: Any] = (fileType == .jpeg)
            ? [.compressionFactor: 0.95]
            : [:]

        guard let imageData = bitmapRep.representation(using: fileType, properties: properties) else {
            return false
        }

        do {
            try imageData.write(to: url)
            return true
        } catch {
            return false
        }
    }

    /// 将 BGR 像素转换为 NSImage 用于预览
    static func bgrToNSImage(bgr: [[[Float]]], alpha: [Float]?, width: Int, height: Int) -> NSImage? {
        let hasAlpha = alpha != nil

        var rgbaData = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let b = UInt8(max(0, min(255, bgr[y][x][0])))
                let g = UInt8(max(0, min(255, bgr[y][x][1])))
                let r = UInt8(max(0, min(255, bgr[y][x][2])))
                let a = hasAlpha ? UInt8(max(0, min(255, alpha![y * width + x]))) : 255

                rgbaData[offset] = r
                rgbaData[offset + 1] = g
                rgbaData[offset + 2] = b
                rgbaData[offset + 3] = a
            }
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: &rgbaData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        guard let cgImage = context.makeImage() else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
