import SwiftUI

// MARK: - 技术特性详情弹窗

struct FeatureDetailView: View {
    @Environment(\.dismiss) private var dismiss

    private let repoURL = "https://github.com/guofei9987/blind_watermark"

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("技术特性")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("盲水印核心技术详解 · v2026.6")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)

            Divider().padding(.horizontal, 16)

            ScrollView {
                VStack(spacing: 14) {
                    SectionCard(icon: "cpu", title: "核心架构") {
                        Text("盲水印基于 DWT (离散小波变换) 频域编码技术，将水印数据嵌入图像的 LL 低频子带，在高频信息区域不可见地承载秘密数据，同时具备极高的鲁棒性与安全性。")
                            .font(.system(size: 12.5)).foregroundStyle(.secondary).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionCard(icon: "shield.lefthalf.filled", title: "核心技术") {
                        FeatureGrid()
                    }

                    SectionCard(icon: "arrow.down.doc", title: "嵌入流程") {
                        FlowGrid(items: [
                            ("HMAC-SHA256 密钥派生，生成确定性种子", "key.fill"),
                            ("CRC-8 计算校验和，附加到消息尾部", "checkmark.shield"),
                            ("RGB → YCbCr 转换，提取 Y 通道", "paintpalette"),
                            ("Y 通道 DWT-1 变换，获取 LL 低频子带", "waveform.path.ecg"),
                            ("消息重复填充 512 bit，每 bit 映射到 LL 块", "repeat.circle"),
                            ("量化调制：bit=1 加 +Q，bit=0 加 −Q", "slider.horizontal.3"),
                            ("IDWT 逆变换 → YCbCr → RGB", "arrow.triangle.2.circlepath"),
                            ("输出含水印 PNG 图像", "photo.on.rectangle.angled"),
                        ])
                    }

                    SectionCard(icon: "arrow.up.doc", title: "提取流程") {
                        FlowGrid(items: [
                            ("RGB → YCbCr → DWT-1 获取 LL 子带", "waveform.path.ecg"),
                            ("按嵌入时相同块映射读取低频系数", "square.grid.3x3"),
                            ("多副本多数表决决定最终 bit 值", "chart.bar.fill"),
                            ("单 bit 错误：翻转尝试并重算 CRC-8", "arrow.triangle.2.circlepath"),
                            ("CRC-8 校验 → 提取原始消息", "checkmark.shield"),
                            ("HMAC-SHA256 验证完整性（可选）", "lock.shield"),
                            ("解码文本/图片数据并呈现", "text.viewfinder"),
                        ])
                    }

                    SectionCard(icon: "gauge.with.dots.needle.33percent", title: "鲁棒性指标") {
                        RobustnessGrid()
                    }

                    SectionCard(icon: "lock.shield.fill", title: "安全性设计") {
                        SecurityGrid()
                    }

                    SectionCard(icon: "link.circle.fill", title: "开源仓库") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "swift")
                                    .font(.system(size: 12)).foregroundStyle(.orange)
                                Text("Swift 重写版 · macOS 26 原生应用")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 10) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 12)).foregroundStyle(.green)
                                Text("基于 Python 原版")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Link(destination: URL(string: repoURL)!) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.system(size: 11))
                                        Text("wilbur-yu/BlindWatermark")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 底部版本信息
                    HStack {
                        Spacer()
                        Text("BlindWatermark v2026.6 · Built for macOS 26")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 680)
        .background(.ultraThinMaterial)
    }
}

// MARK: - 子组件

private struct SectionCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

// MARK: - 核心技术

private struct FeatureGrid: View {
    private let features: [(icon: String, title: String, desc: String)] = [
        ("checkmark.shield", "CRC-8 校验", "内嵌 8-bit 循环冗余校验码，自动检测数据完整性，任何篡改均能被识别"),
        ("repeat", "多份冗余嵌入", "消息重复填充至 512 bit 后嵌入，单 bit 对应多个低频块副本，提供轻度压缩容错"),
        ("chart.bar", "多数投票提取", "多个副本独立提取后经多数表决决定最终 bit 值，可容错 1~2 bit 的局部翻转"),
        ("arrow.triangle.2.circlepath", "单 bit 自动修复", "CRC 校验失败时遍历翻转可疑 bit 并重算，实现单 bit 级自动纠错恢复"),
        ("square.grid.3x3", "块级重复 ~600×", "每个 bit 被重复嵌入 DWT 低频子带的约 600 个独立块中，天然抗噪、抗裁剪"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(features, id: \.title) { f in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: f.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(f.desc)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                }
            }
        }
    }
}

// MARK: - 流程网格（2 列）

private struct FlowGrid: View {
    let items: [(text: String, icon: String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 22, height: 22)
                        Image(systemName: item.icon)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    Text(item.text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.trailing, idx % 2 == 0 ? 8 : 0)
                .padding(.leading, idx % 2 == 1 ? 8 : 0)
            }
        }
    }
}

// MARK: - 鲁棒性

private struct RobustnessGrid: View {
    private let items: [(label: String, value: String, icon: String)] = [
        ("抗 JPEG 压缩", "质量 30%", "photo.on.rectangle"),
        ("抗裁剪", "保留 25% 面积", "crop"),
        ("抗缩放", "0.5× ~ 2.0×", "arrow.up.left.and.arrow.down.right"),
        ("抗噪声", "σ ≤ 15", "circle.dotted"),
        ("抗滤波", "中值/均值", "camera.filters"),
        ("抗旋转", "±1°", "rotate.3d"),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(items, id: \.label) { item in
                VStack(spacing: 4) {
                    Image(systemName: item.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(8)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                    Text(item.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(item.value)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.regularMaterial.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - 安全性（2 列）

private struct SecurityGrid: View {
    private let items: [(title: String, desc: String, icon: String)] = [
        ("HMAC-SHA256 密钥派生", "密码派生 256-bit 密钥用于种子生成与签名验证", "key.fill"),
        ("确定性伪随机序列", "基于密钥种子的 CSPRNG 决定嵌入位置与调制方向", "shuffle"),
        ("统计不可区分性", "量化步长经精心设计，嵌入后图像在统计上不可区分", "chart.xyaxis.line"),
        ("防碰撞设计", "CRC-8 + HMAC 双重校验，伪造水印概率低于 2⁻⁶⁴", "shield.righthalf.filled"),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(items, id: \.title) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(item.desc)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

#Preview {
    FeatureDetailView()
}
