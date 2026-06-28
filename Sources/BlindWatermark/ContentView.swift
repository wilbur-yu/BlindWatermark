import SwiftUI

struct ContentView: View {
    @State private var selection: Tab = .embed
    @State private var showFeatures = false

    enum Tab: String, CaseIterable {
        case embed = "嵌入水印", extract = "提取水印"
        var icon: String {
            switch self { case .embed: return "photo.on.rectangle.angled"; case .extract: return "magnifyingglass" }
        }
    }

    var body: some View {
        NavigationSplitView {
            GlassSidebar {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Image(systemName: "drop.triangle")
                            .font(.system(size: 30, weight: .light)).foregroundStyle(Color.accentColor)
                        Text("盲水印")
                            .font(.system(size: 22, weight: .bold)).foregroundStyle(.primary)
                        Text("BLIND WATERMARK")
                            .font(.system(size: 10, weight: .medium)).kerning(2).foregroundStyle(.tertiary)
                    }
                    .padding(.top, 24).padding(.bottom, 20)
                    Divider().padding(.horizontal, 16)
                    List {
                        GlassNavItem(icon: Tab.embed.icon, title: "嵌入水印", isActive: selection == .embed) { selection = .embed }
                        GlassNavItem(icon: Tab.extract.icon, title: "提取水印", isActive: selection == .extract) { selection = .extract }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                    Spacer()
                    Divider().padding(.horizontal, 16)
                    HStack {
                        Spacer()
                        Button(action: { showFeatures = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 10))
                                Text("技术特性")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    HStack {
                        Spacer()
                        Text("v2026.6")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.bottom, 8)
                }
            }
            .navigationSplitViewColumnWidth(220)
        } detail: {
            ZStack {
                Color(NSColor.controlBackgroundColor).ignoresSafeArea()
                switch selection {
                case .embed: EmbedView()
                case .extract: ExtractView()
                }
            }
        }
        .sheet(isPresented: $showFeatures) {
            FeatureDetailView()
        }
        .frame(minWidth: 800, minHeight: 560)
    }
}
