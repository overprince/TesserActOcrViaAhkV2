# WinOCR — AHK v2 屏幕 OCR 库

基于 [Tesseract 5 LSTM](https://github.com/UB-Mannheim/tesseract) 的屏幕文字识别库，适用于 AutoHotkey v2。  
框选屏幕任意区域即可提取文字——支持 **Windows 10 LTSC**、Windows 10、Windows 11。

> **为什么不用 Windows 自带的 OCR？**  
> `Windows.Media.Ocr`（WinRT）对中文和小字识别效果差。  
> `Microsoft.Windows.AI.Imaging.TextRecognizer`（Windows App SDK）效果好得多，但**仅支持 Windows 11**，Win10 LTSC 无法使用。  
> 如果你确实在用 Win11，可以切换到 [Windows App SDK 版本](#windows-app-sdk-升级版仅-win11)。

---

## 特性

- **纯 AHK v2 库**——`#Include` 后直接调用 `WinOCR(x1, y1, w, h)`
- **零运行时依赖**——只需系统上装好 Tesseract 即可
- **自动查找 Tesseract**——按常用安装路径 + PATH 自动搜索
- **可调放大倍率**——小字放大后识别更准
- **多语言支持**——中文、英文、日文、韩文等
- **清晰的错误处理**——失败时返回空字符串 + `ErrorLevel` 置为非空

---

## 依赖

| 依赖项 | 是否必需 | 说明 |
|-------|---------|------|
| **AutoHotkey v2** | 必需 | v2.0 或以上 |
| **Tesseract OCR 5** | 必需 | 从 [UB-Mannheim/releases](https://github.com/UB-Mannheim/tesseract/releases/latest) 下载安装 |
| **中文语言包** | 可选 | 需要中文 OCR 时安装。安装过程中勾选 "Chinese Simplified"，或手动下载 `chi_sim.traineddata` |

---

## 快速开始

### 1. 安装 Tesseract（一次性）

从 [UB-Mannheim releases](https://github.com/UB-Mannheim/tesseract/releases/latest) 下载并运行安装程序：

```
tesseract-ocr-w64-setup-5.x.x.exe
```

如果需要中文 OCR，安装时在 "Additional language data" 中勾选 **Chinese Simplified**。

### 2. 配置路径（如果需要）

如果 Tesseract 安装在默认位置（`C:\Program Files\Tesseract-OCR\`），**无需任何配置**——库会自动找到。

否则，编辑 `WinOCR.ahk` 第 30 行：

```autohotkey
global g_OCR_Tesseract := "D:\你的路径\Tesseract-OCR\tesseract.exe"
```

### 3. 引入并使用

```autohotkey
#Requires AutoHotkey v2.0
#Include "WinOCR_Tesseract\WinOCR.ahk"
CoordMode "Pixel", "Screen"

result := WinOCR(100, 200, 300, 50)
if (ErrorLevel)
    MsgBox "识别失败: " ErrorLevel
else
    MsgBox result
```

---

## API 参考

### `WinOCR(x1, y1, width, height, scale?, language?)`

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `x1, y1` | 整数 | *(必填)* | 矩形左上角坐标（`CoordMode "Pixel", "Screen"` 坐标系） |
| `width` | 整数 | *(必填)* | 矩形宽度（像素） |
| `height` | 整数 | *(必填)* | 矩形高度（像素） |
| `scale` | 浮点数 | `1.0` | 放大倍率。设为 `2.0` 或 `3.0` 可提升小字精度 |
| `language` | 字符串 | `"chi_sim+eng"` | Tesseract 语言代码。多个语言用 `+` 连接 |

**返回值：** 成功时返回识别文本，失败时返回 `""`（空字符串）。

**错误处理：** 调用后检查 `ErrorLevel`，非空表示失败。

### `WinOCR_CheckSetup()`

返回 `""` 表示 Tesseract 已就绪，否则返回错误描述。

---

## 调参指南

所有参数在 `WinOCR.ahk` 顶部配置：

```autohotkey
global g_OCR_DefaultScale := 1.0   ; 默认放大倍率
global g_OCR_Language    := "chi_sim+eng"  ; 默认语言
global g_OCR_PSM         := 6      ; 页面分割模式
global g_OCR_Tesseract   := ""     ; Tesseract 路径（留空自动查找）
```

### 放大倍率（`g_OCR_DefaultScale`）

| 倍率 | 效果 |
|------|------|
| `1.0` | 不放大。速度最快，大字效果好。 |
| `2.0` | 2 倍放大。推荐值，适合常规屏幕文字（12-16px）。 |
| `3.0` | 3 倍放大。小字最佳，但速度明显变慢。 |

倍率越高，Tesseract 能分析的像素越多，精度越高，但耗时也越大（像素数平方增长）。

### PSM 模式（`g_OCR_PSM`）

PSM（Page Segmentation Mode）控制 Tesseract 如何理解图像中的文字布局：

| PSM | 模式 | 适用场景 |
|-----|------|---------|
| `3` | 全自动 | 通用场景 |
| `6` | 统一文本块 | 屏幕上的整段文字（推荐） |
| `7` | 单行文字 | 按钮、标签等单行文字 |
| `8` | 单个词 | 短词、图标标签 |
| `13` | 原始行 | 调试用 |

### 语言（`g_OCR_Language`）

| 代码 | 语言 |
|------|------|
| `eng` | 英文 |
| `chi_sim` | 简体中文 |
| `chi_tra` | 繁体中文 |
| `jpn` | 日文 |
| `kor` | 韩文 |
| `chi_sim+eng` | 中英混合 |
| `jpn+eng` | 日英混合 |

语言数据文件（`.traineddata`）必须存放在 `C:\Program Files\Tesseract-OCR\tessdata\`。  
如需其他语言，从 [tesseract-ocr/tessdata](https://github.com/tesseract-ocr/tessdata) 下载。

### 插值算法（放大时）

当 `scale > 1.0` 时，可在第 96 行附近修改插值模式：

```autohotkey
; 5 = 最近邻（锐利，保留边缘——OCR 推荐）
; 6 = 高质量双线性（较平滑）
; 7 = 高质量双三次（最平滑，可能模糊小字）
DllCall("gdiplus.dll\GdipSetInterpolationMode", "UPtr", g, "Int", 5)
```

---

## Windows App SDK 升级版（仅 Win11）

`WinOCR_Upgrade/` 目录包含了使用 `Microsoft.Windows.AI.Imaging.TextRecognizer` 的版本——这是 Windows 11 内置的 NPU 加速 OCR 引擎。

**要求：** Windows 11 + .NET 9 SDK + Windows App SDK 运行时

切换方法：编译 C# helper 后，在 `WinOCR.ahk` 中切换后端路径即可。

---

## 项目结构

```
WinOCR_Tesseract/
├── WinOCR.ahk          # 主库文件
├── WinOCR_Demo.ahk     # 交互式演示
├── setup.bat           # （可选）自动下载 Tesseract + 语言包
└── README.md

WinOCR_Upgrade/         # Windows 11 NPU 后端（可选）
├── Program.cs
├── WinOCR_Helper.csproj
├── build.bat
└── local-feed/
```

---

## 许可证

MIT
