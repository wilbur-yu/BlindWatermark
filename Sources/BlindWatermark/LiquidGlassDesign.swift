import SwiftUI

// MARK: - Liquid Glass Design System (macOS 26)

private let buttonCornerRadius: CGFloat = 22
private let cardCornerRadius: CGFloat = 16
private let smallCornerRadius: CGFloat = 10

// ── 玻璃侧边栏 ──
struct GlassSidebar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: 220)
            .background(.ultraThinMaterial)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(.linearGradient(
                        colors: [.white.opacity(0.12), .clear],
                        startPoint: .trailing, endPoint: .leading
                    ))
                    .frame(width: 1)
            }
    }
}

// ── 玻璃导航项 ──
struct GlassNavItem: View {
    let icon: String
    let title: String
    let isActive: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? Color.accentColor : .clear)
                    .frame(width: 3, height: 20)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
            .background {
                if isActive || isHovered {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(isActive ? 0.12 : 0.06))
                }
            }
            .scaleEffect(isHovered && !isActive ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isHovered = h }
        }
    }
}

// ── 玻璃按钮 ──
struct GlassButton: View {
    let title: String
    let systemImage: String?
    let disabled: Bool
    let isLoading: Bool
    let action: () -> Void
    @State private var isHovered = false
    @State private var isPressed = false

    init(_ title: String, systemImage: String? = nil, disabled: Bool = false, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.disabled = disabled; self.isLoading = isLoading; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().scaleEffect(0.7).controlSize(.small)
                } else if let img = systemImage {
                    Image(systemName: img).font(.system(size: 14, weight: .semibold))
                }
                Text(isLoading ? "处理中..." : title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: buttonCornerRadius).fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: buttonCornerRadius)
                        .fill(disabled ? Color.accentColor.opacity(0.3) : Color.accentColor)
                    RoundedRectangle(cornerRadius: buttonCornerRadius)
                        .fill(.linearGradient(
                            colors: [.white.opacity(0.2), .clear, .white.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    if isHovered && !disabled {
                        RoundedRectangle(cornerRadius: buttonCornerRadius)
                            .fill(.linearGradient(
                                colors: [.clear, .white.opacity(0.15), .clear],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .offset(x: isHovered ? 60 : -60)
                            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: isHovered)
                    }
                }
            }
            .scaleEffect(isPressed ? 0.97 : (isHovered ? 1.02 : 1.0))
            .shadow(color: .black.opacity(isHovered && !disabled ? 0.12 : 0.04),
                    radius: isHovered ? 10 : 4, y: isHovered ? 4 : 1)
        }
        .buttonStyle(.plain).disabled(disabled)
        .onHover { h in withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { isHovered = h } }
        .onLongPressGesture(minimumDuration: .infinity, pressing: { p in
            withAnimation(.easeOut(duration: 0.08)) { isPressed = p }
        }, perform: {})
    }
}

// ── 玻璃输入框 ──
struct GlassTextField: View {
    let placeholder: String
    let isSecure: Bool
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder).foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
            }
            if isSecure {
                SecureField("", text: $text)
                    .focused($isFocused)
            } else {
                TextField("", text: $text)
                    .focused($isFocused)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .font(.system(size: 14))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: smallCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: smallCornerRadius)
            .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1))
        .overlay(alignment: .bottom) {
            if isFocused {
                RoundedRectangle(cornerRadius: smallCornerRadius)
                    .fill(.linearGradient(colors: [Color.accentColor.opacity(0.12), .clear], startPoint: .bottom, endPoint: .top))
                    .frame(height: 4).padding(.horizontal, 4)
            }
        }
        .textFieldStyle(.plain)
    }
}

// ── 拖放区 ──
struct GlassDropZone: View {
    @Binding var isTargeted: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
                    .scaleEffect(isTargeted ? 1.15 : 1.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.5), value: isTargeted)
                Text("拖放图片到此处").font(.system(size: 14)).foregroundStyle(.secondary)
                Text("选择图片")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                    .padding(.horizontal, 22).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity).frame(height: 180)
            .background(RoundedRectangle(cornerRadius: 16)
                .stroke(isTargeted ? Color.accentColor : isHovered ? Color.secondary.opacity(0.4) : Color.secondary.opacity(0.2),
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [8, 5])))
            .background(RoundedRectangle(cornerRadius: 16)
                .fill(isTargeted ? Color.accentColor.opacity(0.06) : isHovered ? Color.primary.opacity(0.03) : .clear))
            .scaleEffect(isHovered ? 1.008 : 1.0)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { isHovered = h } }
    }
}

// ── 分段选择器 ──
struct GlassSegmentedPicker<T: Hashable & RawRepresentable>: View where T.RawValue == String {
    @Binding var selection: T
    let options: [T]
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { opt in
                Button(opt.rawValue) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selection = opt }
                }
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background { if selection == opt { RoundedRectangle(cornerRadius: 8).fill(.regularMaterial).matchedGeometryEffect(id: "segment", in: indicator) } }
                .foregroundStyle(selection == opt ? Color.accentColor : .secondary)
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

// ── 内容卡片（无玻璃，保持清晰）──
struct ContentCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: cardCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cardCornerRadius).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
    }
}

// ── 区块标题 ──
struct GlassSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold)).kerning(1).textCase(.uppercase)
            .foregroundStyle(Color.accentColor)
    }
}
