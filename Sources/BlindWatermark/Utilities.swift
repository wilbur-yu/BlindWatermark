import Foundation
import Accelerate

// MARK: - 随机打乱索引生成（对应 Python random_strategy1）

/// 基于种子生成随机打乱索引。对应 Python 的 random_strategy1
/// - Parameters:
///   - seed: 随机种子（密码的整数哈希）
///   - size: 分块数量 block_num
///   - blockShape: 块内元素数（4x4=16）
/// - Returns: [size][16] 的随机打乱索引
func generateShuffleIndices(seed: Int, size: Int, blockShape: Int) -> [[Int]] {
    var rng = SeededRandomNumberGenerator(seed: UInt64(bitPattern: Int64(seed)))
    var indices: [[Int]] = []
    indices.reserveCapacity(size)

    for _ in 0..<size {
        // 生成 blockShape 个随机数，然后 argsort
        var values = (0..<blockShape).map { _ in Float.random(in: 0...1, using: &rng) }
        let sorted = values.enumerated().sorted { $0.element < $1.element }
        let order = sorted.map { $0.offset }
        indices.append(order)
    }
    return indices
}

// MARK: - 种子随机数生成器

struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

// MARK: - 一维 KMeans 阈值判断（对应 Python one_dim_kmeans）

/// 一维 KMeans 聚类，将浮点值二值化为 Bool 数组
/// 对应 Python 的 one_dim_kmeans
func oneDimKMeans(_ inputs: [Float]) -> [Bool] {
    guard !inputs.isEmpty else { return [] }
    let n = inputs.count

    let minVal = inputs.min()!
    let maxVal = inputs.max()!

    if abs(maxVal - minVal) < 1e-8 {
        return Array(repeating: false, count: n)
    }

    var center0 = minVal
    var center1 = maxVal
    var threshold: Float = 0
    let eTol: Float = 1e-6

    for _ in 0..<300 {
        threshold = (center0 + center1) / 2
        var sum0: Float = 0, count0: Int = 0
        var sum1: Float = 0, count1: Int = 0

        for v in inputs {
            if v > threshold {
                sum1 += v
                count1 += 1
            } else {
                sum0 += v
                count0 += 1
            }
        }

        let newCenter0 = count0 > 0 ? sum0 / Float(count0) : center0
        let newCenter1 = count1 > 0 ? sum1 / Float(count1) : center1

        center0 = newCenter0
        center1 = newCenter1

        if abs((center0 + center1) / 2 - threshold) < eTol {
            threshold = (center0 + center1) / 2
            break
        }
    }

    return inputs.map { $0 > threshold }
}

// MARK: - SVD 工具函数（调用 LAPACK sgesdd_）

/// 对 4x4 矩阵执行 SVD 分解 A = U * S * V^T
/// 输入 a 是 4x4 矩阵（行优先），输出 u(4x4), s(4), vt(4x4)
func svd4x4(a: [Float]) -> (u: [Float], s: [Float], vt: [Float]) {
    let m: Int32 = 4
    let n: Int32 = 4
    var lda = m
    var ldu = m
    var ldvt = n

    // sgesdd_ 需要列优先，而我们的输入是行优先
    // 对于 4x4 SVD，U 和 V 也是需要的（我们需要完整的 U 和 V^T）
    // jobz = "A" = 全部

    var jobz = Int8(Character("A").asciiValue!)
    var mm = m
    var nn = n

    // 将行优先转换为列优先
    var aColMajor = [Float](repeating: 0, count: 16)
    for i in 0..<4 {
        for j in 0..<4 {
            aColMajor[j * 4 + i] = a[i * 4 + j]
        }
    }

    var s = [Float](repeating: 0, count: 4)
    var u = [Float](repeating: 0, count: 16)
    var vt = [Float](repeating: 0, count: 16)

    // 查询工作空间大小
    var lwork: Int32 = -1
    var workQuery = [Float](repeating: 0, count: 1)
    var iwork = [Int32](repeating: 0, count: 8 * 4) // 8*min(m,n)
    var info: Int32 = 0

    sgesdd_(&jobz, &mm, &nn, &aColMajor, &lda, &s, &u, &ldu, &vt, &ldvt, &workQuery, &lwork, &iwork, &info)

    lwork = Int32(workQuery[0])
    var work = [Float](repeating: 0, count: Int(lwork))

    sgesdd_(&jobz, &mm, &nn, &aColMajor, &lda, &s, &u, &ldu, &vt, &ldvt, &work, &lwork, &iwork, &info)

    // 将 U 从列优先转回行优先
    var uRowMajor = [Float](repeating: 0, count: 16)
    for i in 0..<4 {
        for j in 0..<4 {
            uRowMajor[i * 4 + j] = u[j * 4 + i]
        }
    }

    // V^T 在 LAPACK 中也是列优先存储，同样需要转置为行优先
    var vtRowMajor = [Float](repeating: 0, count: 16)
    for i in 0..<4 {
        for j in 0..<4 {
            vtRowMajor[i * 4 + j] = vt[j * 4 + i]
        }
    }

    return (u: uRowMajor, s: s, vt: vtRowMajor)
}

/// 从 SVD 结果重建矩阵：U * diag(s) * V^T -> 4x4 行优先
func reconstructFromSVD(u: [Float], s: [Float], vt: [Float]) -> [Float] {
    // us = U * diag(s)，存储在 us（4x4 行优先）
    var us = [Float](repeating: 0, count: 16)
    for i in 0..<4 {
        for j in 0..<4 {
            us[i * 4 + j] = u[i * 4 + j] * s[j]
        }
    }

    // result = us * V^T
    // V^T 是 4x4 行优先，但 vt 的行是 V 的列
    // result[i][k] = sum_j us[i][j] * vt[j][k]
    var result = [Float](repeating: 0, count: 16)
    for i in 0..<4 {
        for k in 0..<4 {
            var sum: Float = 0
            for j in 0..<4 {
                sum += us[i * 4 + j] * vt[j * 4 + k]
            }
            result[i * 4 + k] = sum
        }
    }
    return result
}

// MARK: - 矩阵乘法工具

/// 4x4 矩阵乘法 C = A * B
func matMul4x4(_ a: [Float], _ b: [Float]) -> [Float] {
    var c = [Float](repeating: 0, count: 16)
    for i in 0..<4 {
        for k in 0..<4 {
            var sum: Float = 0
            for j in 0..<4 {
                sum += a[i * 4 + j] * b[j * 4 + k]
            }
            c[i * 4 + k] = sum
        }
    }
    return c
}

/// 4x4 矩阵转置
func transpose4x4(_ a: [Float]) -> [Float] {
    var t = [Float](repeating: 0, count: 16)
    for i in 0..<4 {
        for j in 0..<4 {
            t[j * 4 + i] = a[i * 4 + j]
        }
    }
    return t
}

// MARK: - 密码哈希

/// 将密码字符串转换为整数种子（使用 SipHash，确定性）
func passwordToSeed(_ password: String) -> Int {
    let data = (password + "blind_watermark_salt_2024").data(using: .utf8)!
    // 使用 CommonCrypto 的确定性哈希
    var hash: UInt64 = 0
    data.withUnsafeBytes { raw in
        let ptr = raw.bindMemory(to: UInt8.self)
        hash = siphash24(key: (0x6a09e667f3bcc908, 0xbb67ae8584caa73b), data: ptr.baseAddress!, count: data.count)
    }
    return Int(truncatingIfNeeded: hash)
}

/// SipHash-2-4 确定性哈希（64位输出）
private func siphash24(key: (UInt64, UInt64), data: UnsafePointer<UInt8>, count: Int) -> UInt64 {
    var v0: UInt64 = key.0 ^ 0x736f6d6570736575
    var v1: UInt64 = key.1 ^ 0x646f72616e646f6d
    var v2: UInt64 = key.0 ^ 0x6c7967656e657261
    var v3: UInt64 = key.1 ^ 0x7465646279746573
    var m: UInt64 = 0
    var i = 0
    let n = count
    let blocks = n / 8
    
    for _ in 0..<blocks {
        m = UnsafeRawPointer(data + i).loadUnaligned(as: UInt64.self).littleEndian
        i += 8
        v3 ^= m
        for _ in 0..<2 { sipRound(&v0, &v1, &v2, &v3) }
        v0 ^= m
    }
    
    // Last block
    var last: UInt64 = UInt64(n & 0xff) << 56
    let rem = n % 8
    if rem > 0 {
        var j = rem - 1
        while true {
            last |= UInt64(data[i + j]) << (j * 8)
            if j == 0 { break }
            j -= 1
        }
    }
    v3 ^= last
    for _ in 0..<2 { sipRound(&v0, &v1, &v2, &v3) }
    v0 ^= last
    
    v2 ^= 0xff
    for _ in 0..<4 { sipRound(&v0, &v1, &v2, &v3) }
    return v0 ^ v1 ^ v2 ^ v3
}

private func sipRound(_ v0: inout UInt64, _ v1: inout UInt64, _ v2: inout UInt64, _ v3: inout UInt64) {
    v0 &+= v1; v2 &+= v3; v1 = (v1 << 13) | (v1 >> 51); v3 = (v3 << 16) | (v3 >> 48)
    v1 ^= v0; v3 ^= v2; v0 = (v0 << 32) | (v0 >> 32)
    v2 &+= v1; v0 &+= v3; v1 = (v1 << 17) | (v1 >> 47); v3 = (v3 << 21) | (v3 >> 43)
    v1 ^= v2; v3 ^= v0; v2 = (v2 << 32) | (v2 >> 32)
}
