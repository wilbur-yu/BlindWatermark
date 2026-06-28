import Foundation
import AppKit
import Accelerate

// MARK: - 盲水印核心算法（DWT-DCT-SVD）

/// 对应 Python WaterMarkCore 类
final class WatermarkCore {

    // 分块大小 4x4
    static let blockShape = (rows: 4, cols: 4)
    static let blockSize = 16

    // 嵌入强度参数
    let d1: Float = 36.0
    let d2: Float = 20.0

    // 密码种子
    let passwordSeed: Int

    // 图片状态
    private(set) var imgWidth: Int = 0
    private(set) var imgHeight: Int = 0
    private(set) var caShape: (rows: Int, cols: Int) = (0, 0)
    private(set) var caBlockShape: (rows: Int, cols: Int) = (0, 0)
    private(set) var partShape: (rows: Int, cols: Int) = (0, 0)

    // YUV 通道数据：CA（低频子带）、HVD（高频子带）、CA 分块
    private var caChannels: [[Float]] = []
    private var hvdChannels: [[[Float]]] = []
    private var caBlocks: [[[[[Float]]]]] = [] // [channel][blockRow][blockCol][4][4]

    // 块索引列表
    private var blockIndices: [(Int, Int)] = []
    private(set) var blockNum: Int = 0

    // 水印 bit 信息
    private var wmBits: [Bool] = []
    private var wmSize: Int = 0

    // 打乱索引
    private var shuffleIndices: [[Int]] = []

    // Alpha 通道
    private(set) var alpha: [Float]? = nil

    init(passwordImg: Int) {
        self.passwordSeed = passwordImg
    }

    // MARK: - 读取图片

    /// 读取图片并预处理：加白边 -> YUV -> DWT -> 4维分块
    func readImage(bgrPixels: [[[Float]]], alpha: [Float]?) {
        self.alpha = nil
        self.imgHeight = bgrPixels.count
        self.imgWidth = bgrPixels[0].count

        // 处理透明度
        if let a = alpha {
            let minAlpha = a.min() ?? 255
            if minAlpha < 255 {
                self.alpha = a
            }
        }

        // 加白边使尺寸为偶数
        let padBottom = imgHeight % 2
        let padRight = imgWidth % 2

        let paddedHeight = imgHeight + padBottom
        let paddedWidth = imgWidth + padRight

        // BGR -> YUV
        let yuvPadded = ImageProcessor.bgrToYUV(bgrPixels)

        // 加白边
        var yuvPadded2: [[[Float]]] = []
        for y in 0..<paddedHeight {
            var row: [[Float]] = []
            for x in 0..<paddedWidth {
                if y < imgHeight && x < imgWidth {
                    row.append(yuvPadded[y][x])
                } else {
                    row.append([0, 0, 0]) // Y=0, U=0, V=0
                }
            }
            yuvPadded2.append(row)
        }

        // CA 子带尺寸（DWT 后减半）
        let caRows = paddedHeight / 2
        let caCols = paddedWidth / 2
        self.caShape = (caRows, caCols)

        // 4x4 分块尺寸
        let blockRows = caRows / WatermarkCore.blockShape.rows
        let blockCols = caCols / WatermarkCore.blockShape.cols
        self.caBlockShape = (blockRows, blockCols)
        self.partShape = (blockRows * WatermarkCore.blockShape.rows, blockCols * WatermarkCore.blockShape.cols)

        // 对三个通道分别处理
        self.caChannels = []
        self.hvdChannels = []
        self.caBlocks = []

        for ch in 0..<3 {
            // 提取单通道
            var channelData = [[Float]](repeating: [Float](repeating: 0, count: paddedWidth), count: paddedHeight)
            for y in 0..<paddedHeight {
                for x in 0..<paddedWidth {
                    channelData[y][x] = yuvPadded2[y][x][ch]
                }
            }

            // DWT Haar 分解
            let dwtResult = haarDWT2(channelData)
            let ca = dwtResult.ca
            let hvd = dwtResult.details // (ch, cv, cd)

            self.caChannels.append(ca.flatMap { $0 })
            self.hvdChannels.append(hvd)

            // 转为 4 维分块：view as [blockRows][blockCols][4][4]
            var blocks: [[[[Float]]]] = []
            for br in 0..<blockRows {
                var blockRow: [[[Float]]] = []
                for bc in 0..<blockCols {
                    var block = [[Float]](repeating: [Float](repeating: 0, count: 4), count: 4)
                    for i in 0..<4 {
                        for j in 0..<4 {
                            block[i][j] = ca[br * 4 + i][bc * 4 + j]
                        }
                    }
                    blockRow.append(block)
                }
                blocks.append(blockRow)
            }
            self.caBlocks.append(blocks)
        }
    }

    // MARK: - 读取水印

    func readWatermark(bits: [Bool]) {
        self.wmBits = bits
        self.wmSize = bits.count
    }

    // MARK: - 初始化块索引

    private func initBlockIndex() {
        self.blockNum = caBlockShape.rows * caBlockShape.cols
        self.blockIndices = []
        for i in 0..<caBlockShape.rows {
            for j in 0..<caBlockShape.cols {
                blockIndices.append((i, j))
            }
        }
        // 生成打乱索引
        self.shuffleIndices = generateShuffleIndices(
            seed: passwordSeed,
            size: blockNum,
            blockShape: WatermarkCore.blockSize
        )
    }

    // MARK: - 4x4 DCT-II（手动实现，对应 OpenCV dct）

    /// 预计算 DCT-II 变换矩阵（4x4，正交归一化）
    private static let dctMatrix: [[Float]] = {
        var C = [[Float]](repeating: [Float](repeating: 0, count: 4), count: 4)
        for k in 0..<4 {
            let scale: Float = k == 0 ? sqrt(1.0 / 4.0) : sqrt(2.0 / 4.0)
            for n in 0..<4 {
                C[k][n] = scale * cos(Float.pi * Float(k) * Float(2 * n + 1) / Float(2 * 4))
            }
        }
        return C
    }()

    /// 4x4 2D DCT：DCT(block) = C * block * C^T
    private static func dct2D(_ block: [[Float]]) -> [Float] {
        let flatBlock = block.flatMap { $0 } // 行优先
        let c = dctMatrix.flatMap { $0 }
        let ct = transpose4x4(c)

        let temp = matMul4x4(c, flatBlock)     // C * block
        let result = matMul4x4(temp, ct)       // temp * C^T
        return result
    }

    /// 4x4 2D IDCT：IDCT(result) = C^T * result * C
    private static func idct2D(_ coeffs: [Float]) -> [[Float]] {
        let c = dctMatrix.flatMap { $0 }
        let ct = transpose4x4(c)

        let temp = matMul4x4(ct, coeffs)        // C^T * coeffs
        let result = matMul4x4(temp, c)          // temp * C
        // 转回 4x4 二维数组
        var block = [[Float]](repeating: [Float](repeating: 0, count: 4), count: 4)
        for i in 0..<4 {
            for j in 0..<4 {
                block[i][j] = result[i * 4 + j]
            }
        }
        return block
    }

    // MARK: - 嵌入水印到单个块（slow 模式）

    private func blockAddWM(block: [[Float]], shuffler: [Int], index: Int) -> [[Float]] {
        let wmBit = wmBits[index % wmSize]

        // DCT
        let blockDCT = WatermarkCore.dct2D(block)

        // 打乱
        var shuffled = [Float](repeating: 0, count: 16)
        for i in 0..<16 {
            shuffled[i] = blockDCT[shuffler[i]]
        }
        // reshape 4x4
        var shuffled4x4 = [[Float]](repeating: [Float](repeating: 0, count: 4), count: 4)
        for i in 0..<16 {
            shuffled4x4[i / 4][i % 4] = shuffled[i]
        }
        let flatShuffled = shuffled4x4.flatMap { $0 }

        // SVD
        let svdResult = svd4x4(a: flatShuffled)
        var s = svdResult.s
        let u = svdResult.u
        let vt = svdResult.vt

        // 嵌入水印
        let wmVal: Float = wmBit ? 1.0 : 0.0
        s[0] = (floor(s[0] / d1) + 0.25 + 0.5 * wmVal) * d1
        s[1] = (floor(s[1] / d2) + 0.25 + 0.5 * wmVal) * d2

        // 逆 SVD
        let reconstructed = reconstructFromSVD(u: u, s: s, vt: vt)

        // 逆打乱
        var deshuffled = [Float](repeating: 0, count: 16)
        for i in 0..<16 {
            deshuffled[shuffler[i]] = reconstructed[i]
        }

        // IDCT
        let blockOut = WatermarkCore.idct2D(deshuffled)
        return blockOut
    }

    // MARK: - 提取水印从单个块（slow 模式）

    private func blockGetWM(block: [[Float]], shuffler: [Int]) -> Float {
        // DCT
        let blockDCT = WatermarkCore.dct2D(block)

        // 打乱
        var shuffled = [Float](repeating: 0, count: 16)
        for i in 0..<16 {
            shuffled[i] = blockDCT[shuffler[i]]
        }
        var shuffled4x4 = [[Float]](repeating: [Float](repeating: 0, count: 4), count: 4)
        for i in 0..<16 {
            shuffled4x4[i / 4][i % 4] = shuffled[i]
        }
        let flatShuffled = shuffled4x4.flatMap { $0 }

        // SVD
        let svdResult = svd4x4(a: flatShuffled)
        let s = svdResult.s

        // 解水印
        let wm0: Float = (s[0].truncatingRemainder(dividingBy: d1) > d1 / 2) ? 1.0 : 0.0
        let wm1: Float = (s[1].truncatingRemainder(dividingBy: d2) > d2 / 2) ? 1.0 : 0.0

        // 加权：s[0] 权重 3/4, s[1] 权重 1/4
        return (wm0 * 3.0 + wm1 * 1.0) / 4.0
    }

    // MARK: - 嵌入

    func embed() -> (bgr: [[[Float]]], width: Int, height: Int) {
        initBlockIndex()

        // 深拷贝 ca
        var embedCA = caChannels.map { $0 } // 扁平存储

        // 对每个通道处理
        for ch in 0..<3 {
            let caCols = caShape.cols

            // 处理每个块
            for idx in 0..<blockNum {
                let (br, bc) = blockIndices[idx]
                let modified = blockAddWM(block: caBlocks[ch][br][bc], shuffler: shuffleIndices[idx], index: idx)
                caBlocks[ch][br][bc] = modified
            }

            // 4维分块 -> 2维
            var caPart = [[Float]](repeating: [Float](repeating: 0, count: partShape.cols), count: partShape.rows)
            for br in 0..<caBlockShape.rows {
                for bc in 0..<caBlockShape.cols {
                    for i in 0..<4 {
                        for j in 0..<4 {
                            caPart[br * 4 + i][bc * 4 + j] = caBlocks[ch][br][bc][i][j]
                        }
                    }
                }
            }

            // 将修改后的主体部分放回 embedCA
            for i in 0..<partShape.rows {
                for j in 0..<partShape.cols {
                    embedCA[ch][i * caCols + j] = caPart[i][j]
                }
            }
        }

        // 逆 DWT -> YUV
        let paddedHeight = caShape.rows * 2
        let paddedWidth = caShape.cols * 2

        var embedYUV: [[[Float]]] = []
        for _ in 0..<paddedHeight {
            var row: [[Float]] = []
            for _ in 0..<paddedWidth {
                row.append([0, 0, 0])
            }
            embedYUV.append(row)
        }

        for ch in 0..<3 {
            // 重建 CA 二维数组
            var ca2D = [[Float]](repeating: [Float](repeating: 0, count: caShape.cols), count: caShape.rows)
            for i in 0..<caShape.rows {
                for j in 0..<caShape.cols {
                    ca2D[i][j] = embedCA[ch][i * caShape.cols + j]
                }
            }

            // IDWT
            let reconstructed = haarIDWT2(ca: ca2D, details: hvdChannels[ch])

            for y in 0..<paddedHeight {
                for x in 0..<paddedWidth {
                    embedYUV[y][x][ch] = reconstructed[y][x]
                }
            }
        }

        // 裁剪掉白边
        var croppedYUV: [[[Float]]] = []
        for y in 0..<imgHeight {
            var row: [[Float]] = []
            for x in 0..<imgWidth {
                row.append(embedYUV[y][x])
            }
            croppedYUV.append(row)
        }

        // YUV -> BGR
        let bgrResult = ImageProcessor.yuvToBGR(croppedYUV)

        return (bgrResult, imgWidth, imgHeight)
    }

    // MARK: - 提取（原始 bit 数据）

    func extractRaw() -> [[Float]] {
        // 返回 [3][blockNum] 的浮点值
        var wmBlockBit: [[Float]] = []

        for ch in 0..<3 {
            var channelBits = [Float](repeating: 0, count: blockNum)
            for idx in 0..<blockNum {
                let (br, bc) = blockIndices[idx]
                channelBits[idx] = blockGetWM(block: caBlocks[ch][br][bc], shuffler: shuffleIndices[idx])
            }
            wmBlockBit.append(channelBits)
        }
        return wmBlockBit
    }

    // MARK: - 提取均值

    func extractAvg(wmBlockBit: [[Float]]) -> [Float] {
        var wmAvg = [Float](repeating: 0, count: wmSize)
        for i in 0..<wmSize {
            var sum: Float = 0
            var count: Int = 0
            for ch in 0..<3 {
                // stride = wmSize 循环嵌入
                var j = i
                while j < blockNum {
                    sum += wmBlockBit[ch][j]
                    count += 1
                    j += wmSize
                }
            }
            wmAvg[i] = count > 0 ? sum / Float(count) : 0
        }
        return wmAvg
    }

    // MARK: - 完整提取流程

    func extract(wmShape: (rows: Int, cols: Int)) -> [Float] {
        self.wmSize = wmShape.rows * wmShape.cols
        initBlockIndex()
        let raw = extractRaw()
        return extractAvg(wmBlockBit: raw)
    }

    func extractWithKMeans(wmShape: (rows: Int, cols: Int)) -> [Bool] {
        let avg = extract(wmShape: wmShape)
        return oneDimKMeans(avg)
    }
}

// MARK: - Haar DWT 2D 分解

/// 2D Haar 小波分解
/// 返回 (CA 低频, [(CH, CV, CD) 三个高频子带])
func haarDWT2(_ image: [[Float]]) -> (ca: [[Float]], details: [[Float]]) {
    let h = image.count
    let w = image[0].count
    let h2 = h / 2
    let w2 = w / 2

    var ca = [[Float]](repeating: [Float](repeating: 0, count: w2), count: h2)
    var ch = [[Float]](repeating: [Float](repeating: 0, count: w2), count: h2)
    var cv = [[Float]](repeating: [Float](repeating: 0, count: w2), count: h2)
    var cd = [[Float]](repeating: [Float](repeating: 0, count: w2), count: h2)

    for i in 0..<h2 {
        for j in 0..<w2 {
            let a = image[2 * i][2 * j]
            let b = image[2 * i][2 * j + 1]
            let c = image[2 * i + 1][2 * j]
            let d = image[2 * i + 1][2 * j + 1]

            ca[i][j] = (a + b + c + d) / 2.0
            ch[i][j] = (a - b + c - d) / 2.0
            cv[i][j] = (a + b - c - d) / 2.0
            cd[i][j] = (a - b - c + d) / 2.0
        }
    }

    // details 按行拼接 CH, CV, CD 为一个二维数组（三个子带堆叠）
    var details = [[Float]](repeating: [Float](repeating: 0, count: w2), count: h2 * 3)
    for i in 0..<h2 {
        for j in 0..<w2 {
            details[i][j] = ch[i][j]
            details[h2 + i][j] = cv[i][j]
            details[2 * h2 + i][j] = cd[i][j]
        }
    }

    return (ca, details)
}

/// 2D Haar 小波逆变换
func haarIDWT2(ca: [[Float]], details: [[Float]]) -> [[Float]] {
    let h2 = ca.count
    let w2 = ca[0].count
    let h = h2 * 2
    let w = w2 * 2

    var image = [[Float]](repeating: [Float](repeating: 0, count: w), count: h)

    for i in 0..<h2 {
        for j in 0..<w2 {
            let caVal = ca[i][j]
            let chVal = details[i][j]
            let cvVal = details[h2 + i][j]
            let cdVal = details[2 * h2 + i][j]

            image[2 * i][2 * j] = (caVal + chVal + cvVal + cdVal) / 2.0
            image[2 * i][2 * j + 1] = (caVal - chVal + cvVal - cdVal) / 2.0
            image[2 * i + 1][2 * j] = (caVal + chVal - cvVal - cdVal) / 2.0
            image[2 * i + 1][2 * j + 1] = (caVal - chVal - cvVal + cdVal) / 2.0
        }
    }

    return image
}

// MARK: - 高层便利接口

extension WatermarkCore {

    convenience init() {
        self.init(passwordImg: 123456)
    }

    // MARK: - 文字水印

    /// 嵌入文字水印
    func embed(image: NSImage, mark: String, password: String?) -> NSImage? {
        let seed = password.map { passwordToSeed($0) } ?? 123456
        let core = WatermarkCore(passwordImg: seed)

        guard let (pixels, _, _, alpha) = ImageProcessor.loadImage(from: image) else {
            return nil
        }
        core.readImage(bgrPixels: pixels, alpha: alpha)

        let bits = encodeTextToBits(mark)
        core.readWatermark(bits: bits)

        let (resultBGR, w, h) = core.embed()
        return ImageProcessor.bgrToNSImage(bgr: resultBGR, alpha: alpha, width: w, height: h)
    }

    /// 提取文字水印
    func extract(from image: NSImage, password: String?) -> String? {
        let seed = password.map { passwordToSeed($0) } ?? 123456
        let core = WatermarkCore(passwordImg: seed)

        guard let (pixels, _, _, alpha) = ImageProcessor.loadImage(from: image) else {
            return nil
        }
        core.readImage(bgrPixels: pixels, alpha: alpha)

        let maxBits = 512
        let bits = core.extractWithKMeans(wmShape: (rows: maxBits, cols: 1))
        return decodeBitsToText(bits)
    }

    // MARK: - 图片水印（对应 Python read_wm(mode='img') 和 extract(mode='img')）

    /// 嵌入图片水印：将一张灰度图作为水印嵌入载体图片
    func embed(image: NSImage, markImage: NSImage, password: String?) -> NSImage? {
        let seed = password.map { passwordToSeed($0) } ?? 123456
        let core = WatermarkCore(passwordImg: seed)

        guard let (pixels, _, _, alpha) = ImageProcessor.loadImage(from: image) else {
            return nil
        }
        core.readImage(bgrPixels: pixels, alpha: alpha)

        guard let bits = imageToBits(markImage) else {
            return nil
        }
        core.readWatermark(bits: bits)

        let (resultBGR, w, h) = core.embed()
        return ImageProcessor.bgrToNSImage(bgr: resultBGR, alpha: alpha, width: w, height: h)
    }

    /// 提取图片水印：返回灰度 NSImage
    func extractImage(from image: NSImage, password: String?, wmShape: (rows: Int, cols: Int)) -> NSImage? {
        let seed = password.map { passwordToSeed($0) } ?? 123456
        let core = WatermarkCore(passwordImg: seed)

        guard let (pixels, _, _, alpha) = ImageProcessor.loadImage(from: image) else {
            return nil
        }
        core.readImage(bgrPixels: pixels, alpha: alpha)

        let bits = core.extractWithKMeans(wmShape: wmShape)
        return bitsToGrayscaleImage(bits, shape: wmShape)
    }
}

// MARK: - 图片水印辅助：NSImage <-> [Bool] bits

/// 将 NSImage 转为灰度 bit 数组（对应 Python read_wm mode='img'：灰度→拉平→阈值128）
private func imageToBits(_ image: NSImage) -> [Bool]? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }
    let w = cgImage.width
    let h = cgImage.height
    guard w > 0, h > 0 else { return nil }

    // 创建灰度上下文提取像素
    guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.linearGray)!,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }

    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { return nil }
    let bytes = data.bindMemory(to: UInt8.self, capacity: w * h)

    // 拉平后与 128 比较（对应 Python wm.flatten() > 128）
    var bits = [Bool]()
    bits.reserveCapacity(w * h)
    for i in 0..<(w * h) {
        bits.append(bytes[i] > 128)
    }
    return bits
}

/// 将 bit 数组按 shape 重塑为灰度 NSImage（对应 Python wm.reshape * 255）
private func bitsToGrayscaleImage(_ bits: [Bool], shape: (rows: Int, cols: Int)) -> NSImage? {
    let rows = shape.rows
    let cols = shape.cols
    guard rows > 0, cols > 0, bits.count >= rows * cols else { return nil }

    var pixelData = [UInt8](repeating: 0, count: rows * cols)
    for i in 0..<(rows * cols) {
        pixelData[i] = bits[i] ? 255 : 0
    }

    guard let ctx = CGContext(
        data: &pixelData, width: cols, height: rows,
        bitsPerComponent: 8, bytesPerRow: cols,
        space: CGColorSpace(name: CGColorSpace.linearGray)!,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }

    guard let resultCG = ctx.makeImage() else { return nil }
    return NSImage(cgImage: resultCG, size: NSSize(width: cols, height: rows))
}

// MARK: - 文字<->Bits 编解码

private func encodeTextToBits(_ text: String) -> [Bool] {
    let data = [UInt8](text.data(using: .utf8) ?? Data())
    let len = UInt16(data.count)

    // 基础消息: [16bit 长度][数据][8bit CRC]
    var base: [Bool] = []
    for i in (0..<16).reversed() { base.append((len >> i) & 1 != 0) }
    for byte in data {
        for i in (0..<8).reversed() { base.append((byte >> i) & 1 != 0) }
    }
    let crc = crc8(data)
    for i in (0..<8).reversed() { base.append((crc >> i) & 1 != 0) }

    // 补齐到 2 的幂，再重复填满 512 bit
    let pad: Int = {
        let raw = base.count
        if raw <= 32 { return 32 }
        if raw <= 64 { return 64 }
        if raw <= 128 { return 128 }
        if raw <= 256 { return 256 }
        return 512
    }()
    while base.count < pad { base.append(false) }

    var result: [Bool] = []
    while result.count < 512 { result.append(contentsOf: base) }
    return Array(result.prefix(512))
}

// MARK: - CRC-8

private func crc8(_ data: [UInt8]) -> UInt8 {
    var crc: UInt8 = 0
    for byte in data {
        crc ^= byte
        for _ in 0..<8 {
            if crc & 0x80 != 0 { crc = (crc << 1) ^ 0x07 }
            else { crc <<= 1 }
        }
    }
    return crc
}

// MARK: - 解码 + 纠错

private func decodeBitsToText(_ bits: [Bool]) -> String? {
    // 候选份数长度（2 的幂，能被 512 整除）
    let candidates = [32, 64, 128, 256, 512].filter { bits.count % $0 == 0 }

    func tryVoteAndDecode(_ b: [Bool]) -> String? {
        for baseLen in candidates {
            let copies = b.count / baseLen
            var voted: [Bool] = []
            for i in 0..<baseLen {
                var ones = 0
                for c in 0..<copies { if b[c * baseLen + i] { ones += 1 } }
                voted.append(ones > copies / 2)
            }
            if let text = decodeOne(bits: voted) { return text }
        }
        return nil
    }

    if let text = tryVoteAndDecode(bits) { return text }

    // 单 bit 翻转自动修复
    for i in 0..<min(bits.count, 512) {
        var flipped = bits
        flipped[i].toggle()
        if let text = tryVoteAndDecode(flipped) { return text }
    }

    return nil
}

/// 解码单份 bit 数组（已做完多数投票）
private func decodeOne(bits: [Bool]) -> String? {
    guard bits.count >= 24 else { return nil }
    var len: UInt16 = 0
    for i in 0..<16 { if bits[i] { len |= 1 << (15 - i) } }
    let byteCount = Int(len)
    guard byteCount > 0, byteCount <= 100 else { return nil }

    let totalNeeded = 16 + byteCount * 8 + 8
    guard bits.count >= totalNeeded else { return nil }

    var bytes = [UInt8](repeating: 0, count: byteCount)
    for bi in 0..<byteCount {
        var byte: UInt8 = 0
        for i in 0..<8 {
            if bits[16 + bi * 8 + i] { byte |= 1 << (7 - i) }
        }
        bytes[bi] = byte
    }

    var expectedCRC: UInt8 = 0
    for i in 0..<8 {
        if bits[16 + byteCount * 8 + i] { expectedCRC |= 1 << (7 - i) }
    }
    guard crc8(bytes) == expectedCRC else { return nil }

    return String(data: Data(bytes), encoding: .utf8)
}
