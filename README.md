# ECG Research App

一个隐私优先、完全本地、可解释的开源研究项目，目标是在 iPhone 上读取
Apple Watch 官方 ECG App 已保存到 Apple Health 的单导联 ECG，并以保守、
可审计的方式标记疑似提前心搏。

> **当前状态：Milestone 1（HealthKit 读取层，进行中）。** `ECGCore` 已编译并通过 7 项单元测试。
> iOS 17 读取层源码已完成（SwiftUI App、只读 HealthKit ECG 授权、metadata 列表、惰性电压读取、
> mV 映射、状态区分与免责声明），并在本机真实编译：
>
> - `swift build`：macOS 目标全量通过；以真实 iPhoneOS 26.5 / iPhoneSimulator 26.5 SDK 通过。
> - Xcode 26.6（build 17F113，位于 `~/Downloads/Xcode.app`）：`iOS/WatchBeat.xcodeproj` 的
>   App target 与单元测试 bundle 均 `BUILD SUCCEEDED`。
> - 16 项读取层单元测试通过（SwiftPM/macOS）；Xcode iOS test bundle 已构建、尚未在 destination 执行。
>
> **未完成的真实验收：** App **从未运行过**。本机未安装 iOS 模拟器运行时与 iOS 26.5 设备支持，
> 因此 scheme + destination 构建失败，也没有模拟器/真机运行、没有截图、没有真机 HealthKit
> 授权与波形验收。详见 [NEEDS_MACOS_VALIDATION.md](NEEDS_MACOS_VALIDATION.md) 与
> [Docs/VALIDATION.md](Docs/VALIDATION.md)。
> 后续审查已修正 entitlement、iPhone-only、共享 scheme 与 SwiftUI 状态生命周期；该修复提交
> 已通过跨平台配置测试，但仍须回到 macOS 重新编译并运行。

## 医疗安全声明

> This app is intended for informational and research purposes only. It does not
> provide a medical diagnosis. Possible PAC/PVC-like classifications may be
> incorrect. Do not use this app for emergency or treatment decisions.

本项目仅用于信息展示和研究，不提供医疗诊断。未来显示的“疑似房性早搏样心搏”
或“疑似室性早搏样心搏”可能不正确，不得用于急症判断、治疗或用药决策。出现胸痛、
晕厥、明显呼吸困难、持续严重心悸或其他严重症状时，应及时寻求专业医疗帮助。

## 目标结果词汇

产品只允许使用以下保守结果：

| Internal value | English UI | 中文 UI |
|---|---|---|
| `normal` | Normal Beat | 正常心搏 |
| `possiblePAC` | Possible PAC-like Beat | 疑似房性早搏样心搏 |
| `possiblePVC` | Possible PVC-like Beat | 疑似室性早搏样心搏 |
| `prematureUncertain` | Premature Beat — Uncertain | 疑似早搏—无法确定类型 |
| `noiseInvalid` | Noise / Invalid Beat | 噪声或无效心搏 |
| `notAnalyzed` | Not Analyzed | 未分析 |

禁止把这些研究性分类表述为确诊，也不得暗示 Apple Watch 漏诊疾病。

## 计划中的本地数据流

```text
Apple Watch 官方 ECG
  → Apple Health / HealthKit（只读）
  → 原始波形与真实时间戳
  → 完整性检查和信号质量门控
  → R 峰、RR、个人正常模板与形态特征
  → Possible PAC-like / Possible PVC-like / Uncertain / Not Analyzed
  → 本地解释、用户主动导出
```

算法核心不依赖 HealthKit 或 SwiftUI。缺测电压保留为 `nil`，不得通过删除样本改变
时间轴。Apple 的原始 ECG classification 未来只展示和导出，绝不作为 detector 选择、
PAC/PVC 分类或置信度的输入。

## 当前已实现

- 无第三方 runtime 依赖的 `ECGCore` Swift Package 基线（已编译、7 项测试通过）。
- HealthKit 无关的 `ECGSignal` 数据边界。
- `RPeakDetecting` 与 `BeatClassifying` 协议。
- 稳定的六类结果、特征快照、reason code 和版本字段。
- 不删除样本的结构完整性检查：数组长度、缺测、非有限值、重复/倒退时间戳、
  稳健采样率推断和时间间隔相对 MAD。
- iOS 17 SwiftUI App 源码（`iOS/`）：只读 HealthKit ECG 授权（`toShare` 为空）、metadata
  列表、惰性电压读取（含取消与陈旧请求保护）、mV 映射、四类状态区分、免责声明。
- 16 项读取层单元测试源码（已通过 SwiftPM/macOS 测试；尚未在 iOS destination 执行）。
- 隐私、算法、验证、数据集、监管和依赖决策文档。

## 尚未实现

- App 运行：Xcode 工程与 App target 已能构建，但本机缺 iOS 模拟器运行时与 iOS 26.5 设备支持，
  所以没有 scheme + destination 构建、没有模拟器或真机运行、没有真机 HealthKit 授权验收。
- 波形显示、滚动缩放、导出和真机一致性校验（Milestone 2）。
- 数字滤波、完整信号质量门控、R 峰 detector、RR、模板、QRS 和分类器（Milestones 4–7）。
- 离线公开数据评测结果或 Apple Watch 域验证（Milestones 3、9）。
- 界面本地化：UI 文案目前为英文，免责声明为中英双语。

因此仍然没有应用截图。截图只能在界面于 Xcode 编译并在真机实际运行后加入，
不会用静态 mock 冒充已完成的产品。

## 构建 ECGCore

需要 Swift 5.9 或更高版本：

```bash
Tools/run-core-tests.sh --parallel
```

脚本内部执行 `swift test --parallel`。ECGCore 的单元测试使用 Swift Testing（`import Testing`），
不依赖 XCTest。XCTest 只随 Xcode 提供；在**未安装 Xcode、只有 Command Line Tools 的 macOS** 上，
SwiftPM 不会自动加入 Swift Testing 的 framework、宏插件和 rpath 搜索路径，`swift test` 会因找不到
XCTest 而失败（`Package.swift` 里的 target 级 flags 也无效：SwiftPM 自动生成的 test runner 拿不到
这些 flag，`canImport(Testing)` 为 false，会"构建成功但一个测试都不跑"，必须避免）。

两种无需 Xcode 的跑法：

```bash
# 1. 仓库脚本，任何环境都能用（推荐，CI 也适用）
Tools/run-core-tests.sh --parallel

# 2. 安装用户级 swift 包装器，之后裸命令即可
Tools/install-swift-test-shim.sh        # 只写 ~/.local/bin/swift，不需要 sudo
export PATH="$HOME/.local/bin:$PATH"    # 手动执行；需要持久化时自行加入 ~/.zshrc
cd ECGCore && swift test --parallel
Tools/uninstall-swift-test-shim.sh      # 需要时移除
```

装有 Xcode 的机器无需上述任何包装，可直接 `cd ECGCore && swift test --parallel`。

已验证：macOS 26.7 + Swift 6.2.4（Command Line Tools，未安装 Xcode），7 项测试全部通过。

## 构建与测试 iOS App（本机可执行的编译）

```bash
bash Tools/run-app-tests.sh --parallel                 # 16 项单元测试（仓库根目录执行）

cd iOS
swift build                                            # macOS 目标：SwiftUI + HealthKit 全量编译
swift build --triple arm64-apple-ios17.0 \
            --sdk "$(xcrun --sdk iphoneos --show-sdk-path)"        # 真实 iOS SDK（真机）
swift build --triple x86_64-apple-ios17.0-simulator \
            --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" # 真实 iOS SDK（模拟器）
```

`Tools/run-core-tests.sh`、`Tools/run-app-tests.sh` 会自动识别当前工具链（Xcode 或只有
Command Line Tools），为 `swift test` 补上 Swift Testing 的 framework、宏插件与 rpath
搜索路径——这些无法写进 `Package.swift`，必须放在命令行。

Xcode App 构建（Xcode 26.6，需要显式指定 developer 目录，因为 `xcode-select` 仍指向
Command Line Tools）：

```bash
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
cd iOS
xcodebuild -project WatchBeat.xcodeproj -target WatchBeatApp \
           -sdk iphonesimulator26.5 -arch x86_64 CODE_SIGNING_ALLOWED=NO build
xcodebuild -project WatchBeat.xcodeproj -target WatchBeatApp \
           -sdk iphoneos26.5 -arch arm64 CODE_SIGNING_ALLOWED=NO build
```

用 `-target` 而非 `-scheme`：scheme 构建需要 destination，而本机没有模拟器运行时与 iOS 26.5
设备支持，`-scheme` 会报 `Unable to find a destination ...` / `iOS 26.5 is not installed`。
`-target` + `CODE_SIGNING_ALLOWED=NO` 构建只证明 App 能编译、链接并处理 Info.plist；它不会生成
可用于验证的签名，也不能证明 HealthKit entitlement 已进入最终 App 签名，更不代表运行过。

## 未来构建 iPhone App

最低目标 iOS 17.0。Xcode 工程已经能用 `-target` + `-sdk` 构建；要真正跑起来还需要：

1. iOS 26.5 平台支持与模拟器运行时（Xcode > Settings > Components），或一台真机。
2. Apple Developer 签名配置及带 HealthKit capability 的 App ID；验证签名产物实际包含
   `com.apple.developer.healthkit`。
3. 一台能访问真实 Apple Health ECG 数据的兼容 iPhone。
4. 只请求 ECG 读取权限；`toShare` 必须为空。
5. 在真机逐项完成 [NEEDS_MACOS_VALIDATION.md](NEEDS_MACOS_VALIDATION.md)。

模拟器、合成数据和静态 mock 不能替代 HealthKit 真实 ECG 的端到端验收。

## 隐私

All ECG processing is performed locally on the user's device.

本项目不需要账号、服务器、网络推理、广告、遥测、分析 SDK 或崩溃上传。默认不持久化
原始 ECG 副本，不把 ECG 数值、HealthKit identifier 或日期写入日志，不向 HealthKit
写入推断结果。只有用户主动操作时才通过系统 share sheet 导出敏感文件。完整政策见
[Docs/PRIVACY.md](Docs/PRIVACY.md)。

## 文档索引

- [架构](Docs/ARCHITECTURE.md)
- [算法边界与研究参数](Docs/ALGORITHM.md)
- [验证状态与指标](Docs/VALIDATION.md)
- [数据集登记](Docs/DATASETS.md)
- [隐私](Docs/PRIVACY.md)
- [监管与产品表述](Docs/REGULATORY.md)
- [依赖登记](Docs/DEPENDENCIES.md)
- [ADR-0001：R 峰依赖策略](Docs/ADR/0001-r-peak-dependency-strategy.md)
- [工作清单](TODO.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)

## 开源与贡献

项目主体采用 [MIT License](LICENSE)。候选第三方组件不会自动获得相同许可证；若未来
引入，必须固定版本、审查传递依赖，并保留其许可证、版权和 NOTICE。贡献前请阅读
[CONTRIBUTING.md](CONTRIBUTING.md)。
