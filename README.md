# BlindWatermark

基于 DWT（离散小波变换）频域编码的盲水印工具，macOS 原生应用。

> 本项目由 AI Vibe Coding 方式编写完成。

## 核心技术

- **DWT 频域编码**：将水印信息嵌入图像频域，肉眼不可见
- **CRC-8 校验**：确保水印数据完整性
- **冗余嵌入**：多次重复嵌入提升容错率
- **多数投票机制**：提取时通过投票还原原始信息
- **单 bit 修复**：对损坏的单个 bit 进行修复
- **块级重复**：将水印分块重复嵌入，增强抗裁剪能力

## 安装

### 直接下载

从 [Releases](https://github.com/wilbur-yu/BlindWatermark/releases) 页面下载最新版本的 `盲水印.app`。

### 手动编译

```bash
swift build -c release
```

编译产物位于 `.build/release/BlindWatermark`。

## 使用

1. 打开「盲水印」应用
2. **嵌入水印**：选择图片，输入水印文字，点击嵌入
3. **提取水印**：选择带水印的图片，点击提取
4. 支持拖放操作，将图片文件拖入窗口即可

## 安全性

- 嵌入的水印不可见，不影响图片观感
- 对 JPEG 压缩、缩放、裁剪等常见操作具有鲁棒性
- 水印信息通过编码后嵌入，无法直接读取

## 致谢

本项目灵感来源于 [guofei9987/blind_watermark](https://github.com/guofei9987/blind_watermark)（Python 实现）。

## 许可证

MIT License
