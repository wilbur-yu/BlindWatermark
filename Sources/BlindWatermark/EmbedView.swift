import SwiftUI
import UniformTypeIdentifiers

// MARK: - 嵌入盲水印

struct EmbedView: View {
    @State private var selectedImage: NSImage?
    @State private var watermarkText = ""
    @State private var watermarkImage: NSImage?
    @State private var watermarkDropTargeted = false
    @State private var password = ""
    @State private var watermarkMode: WatermarkMode = .text
    @State private var isDragTargeted = false
    @State private var outputImage: NSImage?
    @State private var isProcessing = false
    @State private var scrollTarget: String?

    enum WatermarkMode: String, Hashable, RawRepresentable {
        case text = "文字", image = "图片"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("嵌入盲水印").font(.system(size: 32, weight: .bold)).foregroundStyle(.primary)
                        Text("将不可见水印嵌入图片，保护您的版权").font(.system(size: 14)).foregroundStyle(.secondary)
                    }.padding(.bottom, 4)

                ContentCard {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassSectionHeader(title: "原图")
                        if let img = selectedImage {
                            preview(img)
                            Button(action: selectImage) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("重新选择").font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16).padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                        } else {
                            GlassDropZone(isTargeted: $isDragTargeted) { selectImage() }
                                .onDrop(of: [.fileURL, .image], isTargeted: $isDragTargeted) { p in loadImage(p); return true }
                        }
                    }
                }
                ContentCard {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassSectionHeader(title: "水印内容")
                        GlassSegmentedPicker(selection: $watermarkMode, options: [WatermarkMode.text, .image])
                        if watermarkMode == .text {
                            VStack(alignment: .leading, spacing: 6) { subLabel("水印文字"); GlassTextField(placeholder: "输入水印文字...", isSecure: false, text: $watermarkText) }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                subLabel("水印图片")
                                VStack(spacing: 8) {
                                    GlassDropZone(isTargeted: $watermarkDropTargeted) { selectWatermarkImage() }
                                        .onDrop(of: [.fileURL, .image], isTargeted: $watermarkDropTargeted) { p in
                                            _ = loadWatermarkImage(p); return true
                                        }
                                    if let wmImg = watermarkImage {
                                        VStack(spacing: 6) {
                                            Image(nsImage: wmImg).resizable().scaledToFit().frame(maxHeight: 120).clipShape(RoundedRectangle(cornerRadius: 6))
                                            Text("水印图片 (\(Int(wmImg.size.width))×\(Int(wmImg.size.height)))")
                                                .font(.system(size: 10, weight: .semibold)).kerning(1).textCase(.uppercase).foregroundStyle(.secondary.opacity(0.6))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                ContentCard {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassSectionHeader(title: "密码")
                        VStack(alignment: .leading, spacing: 6) { subLabel("解嵌密码（可选）"); GlassTextField(placeholder: "设置解嵌密码以增强安全性...", isSecure: true, text: $password) }
                    }
                }

                GlassButton("嵌入水印", systemImage: "lock.rectangle",
                    disabled: selectedImage == nil
                        || (watermarkMode == .text && watermarkText.isEmpty)
                        || (watermarkMode == .image && watermarkImage == nil)
                        || isProcessing, isLoading: isProcessing) { embed() }

                if let out = outputImage {
                    ContentCard {
                        VStack(alignment: .leading, spacing: 12) {
                            GlassSectionHeader(title: "处理结果")
                            Image(nsImage: out).resizable().scaledToFit().frame(maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 12))
                            HStack(spacing: 12) {
                                Button(action: saveOutputImage) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "square.and.arrow.down")
                                        Text("保存图片").font(.system(size: 13, weight: .semibold))
                                    }
                                    .foregroundStyle(.white).frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .focusEffectDisabled()
                                Button(action: { outputImage = nil }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark")
                                        Text("清除").font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .focusEffectDisabled()
                            }
                        }
                    }
                    .id("result_embed")
                }
            }.padding(24)
            }
            .onChange(of: scrollTarget) { _, target in
                if let target { withAnimation { proxy.scrollTo(target, anchor: .top) } }
            }
        }
    }

    private func subLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).kerning(1.5).textCase(.uppercase).foregroundStyle(.secondary)
    }

    

    @ViewBuilder func preview(_ img: NSImage) -> some View {
        VStack(spacing: 8) {
            Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 8))
            Text("已选择 (\(Int(img.size.width))×\(Int(img.size.height)))")
                .font(.system(size: 11, weight: .semibold)).kerning(1).textCase(.uppercase).foregroundStyle(.secondary.opacity(0.6))
        }
    }

    func selectImage() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg, .bmp, .tiff]; p.allowsMultipleSelection = false; p.canChooseDirectories = false
        if p.runModal() == .OK, let u = p.url, let i = NSImage(contentsOf: u) { selectedImage = i }
    }

    func loadImage(_ providers: [NSItemProvider]) {
        guard let p = providers.first else { return }
        if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            p.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                if let d = item as? Data, let i = NSImage(data: d) { DispatchQueue.main.async { selectedImage = i } }
                else if let u = item as? URL, let i = NSImage(contentsOf: u) { DispatchQueue.main.async { selectedImage = i } }
            }
        }
    }

    func embed() {
        guard let img = selectedImage else { return }
        if watermarkMode == .text { guard !watermarkText.isEmpty else { return } }
        else { guard watermarkImage != nil else { return } }

        isProcessing = true
        let mode = watermarkMode
        let text = watermarkText
        let wmImg = watermarkImage
        let pwd = password.isEmpty ? nil : password
        DispatchQueue.global(qos: .userInitiated).async {
            let r: NSImage? = {
                if mode == .text {
                    return WatermarkCore().embed(image: img, mark: text, password: pwd)
                } else {
                    return WatermarkCore().embed(image: img, markImage: wmImg!, password: pwd)
                }
            }()
            DispatchQueue.main.async { outputImage = r; isProcessing = false; scrollTarget = "result_embed" }
        }
    }

    func selectWatermarkImage() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg, .bmp, .tiff]; p.allowsMultipleSelection = false; p.canChooseDirectories = false
        if p.runModal() == .OK, let u = p.url, let i = NSImage(contentsOf: u) { watermarkImage = i }
    }

    func loadWatermarkImage(_ providers: [NSItemProvider]) {
        guard let p = providers.first else { return }
        if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            p.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                if let d = item as? Data, let i = NSImage(data: d) { DispatchQueue.main.async { watermarkImage = i } }
                else if let u = item as? URL, let i = NSImage(contentsOf: u) { DispatchQueue.main.async { watermarkImage = i } }
            }
        }
    }

    func saveOutputImage() {
        guard let out = outputImage, let tiff = out.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "watermarked.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? pngData.write(to: url)
    }
}

// MARK: - 提取盲水印

struct ExtractView: View {
    @State private var selectedImage: NSImage?
    @State private var password = ""
    @State private var isDragTargeted = false
    @State private var extractedText: String?
    @State private var extractedImage: NSImage?
    @State private var isProcessing = false
    @State private var extractMode: ExtractMode = .text
    @State private var wmRowsText = "64"
    @State private var wmColsText = "64"
    @State private var scrollTarget: String?

    enum ExtractMode: String, Hashable, RawRepresentable {
        case text = "文字", image = "图片"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("提取盲水印").font(.system(size: 32, weight: .bold)).foregroundStyle(.primary)
                        Text("从图片中提取隐藏的盲水印信息").font(.system(size: 14)).foregroundStyle(.secondary)
                    }.padding(.bottom, 4)

                ContentCard {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassSectionHeader(title: "原图")
                        if let img = selectedImage {
                            preview(img)
                            Button(action: selectImage) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("重新选择").font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16).padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                        } else {
                            GlassDropZone(isTargeted: $isDragTargeted) { selectImage() }
                                .onDrop(of: [.fileURL, .image], isTargeted: $isDragTargeted) { p in loadImage(p); return true }
                        }
                    }
                }
                ContentCard {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassSectionHeader(title: "提取模式")
                        GlassSegmentedPicker(selection: $extractMode, options: [ExtractMode.text, .image])
                    }
                }
                if extractMode == .image {
                    ContentCard {
                        VStack(alignment: .leading, spacing: 16) {
                            GlassSectionHeader(title: "水印尺寸")
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    subLabel("宽 (px)")
                                    GlassTextField(placeholder: "64", isSecure: false, text: $wmColsText)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    subLabel("高 (px)")
                                    GlassTextField(placeholder: "64", isSecure: false, text: $wmRowsText)
                                }
                            }
                        }
                    }
                }
                ContentCard {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassSectionHeader(title: "密码")
                        VStack(alignment: .leading, spacing: 6) { subLabel("解嵌密码（如有）"); GlassTextField(placeholder: "输入解嵌密码...", isSecure: true, text: $password) }
                    }
                }

                GlassButton("提取水印", systemImage: "magnifyingglass", disabled: selectedImage == nil || isProcessing, isLoading: isProcessing) { extract() }

                if let text = extractedText {
                    ContentCard {
                        VStack(alignment: .leading, spacing: 12) {
                            GlassSectionHeader(title: "提取结果")
                            Text(text).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
                                .textSelection(.enabled)
                        }
                    }
                    .id("result_extract")
                }

                if let outImg = extractedImage {
                    ContentCard {
                        VStack(alignment: .leading, spacing: 12) {
                            GlassSectionHeader(title: "提取结果")
                            Image(nsImage: outImg).resizable().scaledToFit().frame(maxHeight: 200).clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
                        }
                    }
                    .id("result_extract_img")
                }
            }.padding(24)
            }
            .onChange(of: scrollTarget) { _, target in
                if let target { withAnimation { proxy.scrollTo(target, anchor: .top) } }
            }
        }
    }

    private func subLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).kerning(1.5).textCase(.uppercase).foregroundStyle(.secondary)
    }

    

    @ViewBuilder func preview(_ img: NSImage) -> some View {
        VStack(spacing: 8) {
            Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 8))
            Text("已选择 (\(Int(img.size.width))×\(Int(img.size.height)))")
                .font(.system(size: 11, weight: .semibold)).kerning(1).textCase(.uppercase).foregroundStyle(.secondary.opacity(0.6))
        }
    }

    func selectImage() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg, .bmp, .tiff]; p.allowsMultipleSelection = false; p.canChooseDirectories = false
        if p.runModal() == .OK, let u = p.url, let i = NSImage(contentsOf: u) { selectedImage = i }
    }

    func loadImage(_ providers: [NSItemProvider]) {
        guard let p = providers.first else { return }
        if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            p.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
                if let d = item as? Data, let i = NSImage(data: d) { DispatchQueue.main.async { selectedImage = i } }
                else if let u = item as? URL, let i = NSImage(contentsOf: u) { DispatchQueue.main.async { selectedImage = i } }
            }
        }
    }

    func extract() {
        guard let img = selectedImage else { return }
        isProcessing = true
        let isTextMode = extractMode == .text
        let pwd = password.isEmpty ? nil : password
        let rows = Int(wmRowsText) ?? 64
        let cols = Int(wmColsText) ?? 64
        DispatchQueue.global(qos: .userInitiated).async {
            if isTextMode {
                let t = WatermarkCore().extract(from: img, password: pwd)
                DispatchQueue.main.async { extractedText = t; extractedImage = nil; isProcessing = false; scrollTarget = "result_extract" }
            } else {
                let outImg = WatermarkCore().extractImage(from: img, password: pwd, wmShape: (rows: rows, cols: cols))
                DispatchQueue.main.async { extractedImage = outImg; extractedText = nil; isProcessing = false; scrollTarget = "result_extract_img" }
            }
        }
    }
}
