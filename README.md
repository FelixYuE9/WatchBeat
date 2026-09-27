# ECG Research App

一个隐私优先、完全本地、可解释的开源研究项目，目标是在 iPhone 上读取
Apple Watch 官方 ECG App 已保存到 Apple Health 的单导联 ECG，并以保守、
可审计的方式标记疑似提前心搏。

> **当前状态：Milestone 2（波形与导出，源码已实现，等待 macOS 复验）。** `ECGCore` 已编译并通过 7 项单元测试。
> iOS 17 读取层源码已完成（SwiftUI App、只读 HealthKit ECG 授权、metadata 列表、惰性电压读取、
> mV 映射、状态区分与免责声明），并在本机真实编译：
>
> - `swift build`：macOS 目标全量通过；以真实 iPhoneOS 26.5 / iPhoneSimulator 26.5 SDK 通过。
> - Xcode 26.6（build 17F113，位于 `~/Downloads/Xcode.app`）：`iOS/WatchBeat.xcodeproj` 的
>   App target 与单元测试 bundle 均 `BUILD SUCCEEDED`。
> - 既有 16 项读取层单元测试通过（SwiftPM/macOS）；本轮新增 7 项波形、合成示例和导出测试，
>   当前 Windows 环境无法执行 Swift，须在 macOS 上运行后再登记结果。
>
> **运行证据：** 2026-09-27 的用户截图确认 App 已在 iPhone 17 Pro / iOS 26.5 模拟器成功安装
> 和启动，并显示预期的无可访问 ECG 状态；这也确认 embedded framework plist 修复已越过安装检查。
> 尚未记录 shared scheme 自动测试，也没有真机 HealthKit 授权与波形验收。详见
> [NEEDS_MACOS_VALIDATION.md](NEEDS_MACOS_VALIDATION.md) 与
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
- 内置确定性合成 ECG 教程（非人体数据），在无授权、无记录或 HealthKit 不可用时也能学习界面。
- 全分辨率数据独立于显示降采样的可滚动/缩放波形，以及按真实时间戳定位的 marker 接口。
- 用户确认后通过系统 share sheet 导出原始 CSV 或 metadata JSON；临时文件分享后清理。
- 16 项读取层测试此前已通过；本轮新增 7 项波形/导出测试，等待 macOS 执行。
- 隐私、算法、验证、数据集、监管和依赖决策文档。

## 尚未实现

- shared scheme 的 simulator 自动测试、本轮 Milestone 2 源码的 Xcode 编译与 UI 操作复验。
- 真机 HealthKit 授权、真实波形显示和导出逐样本一致性校验。
- 数字滤波、完整信号质量门控、R 峰 detector、RR、模板、QRS 和分类器（Milestones 4–7）。
- 离线公开数据评测结果或 Apple Watch 域验证（Milestones 3、9）。
- 界面本地化：UI 文案目前为英文，免责声明为中英双语。

模拟器截图只证明安装、启动与 UI 状态，不会被当作真机 HealthKit 或医学准确率证据。内置示例
始终明确标为数学合成数据，不会用它冒充 Apple Watch ECG。

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
bash Tools/run-app-tests.sh --parallel                 # 当前应发现 23 项单元测试（仓库根目录执行）

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

Xcode App 构建与模拟器测试（Xcode 26.6；如果 `xcode-select` 仍指向 Command Line Tools，
需要显式指定 developer 目录）：

```bash
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
cd iOS
xcodebuild -project WatchBeat.xcodeproj -scheme WatchBeatApp \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
xcodebuild -project WatchBeat.xcodeproj -scheme WatchBeatApp \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

早期在没有 simulator runtime 时只能使用 `-target` + `CODE_SIGNING_ALLOWED=NO`；那段历史结果仍
保留在验证文档。现在 simulator 已可运行，应使用 shared scheme + 真实 destination。若设备名称
不同，先执行 `xcodebuild -project WatchBeat.xcodeproj -scheme WatchBeatApp -showdestinations`。

## 未来构建 iPhone App

最低目标 iOS 17.0。模拟器已经可以启动；要读取真人 ECG 还需要：

1. Apple Developer 签名配置及带 HealthKit capability 的 App ID；验证签名产物实际包含
   `com.apple.developer.healthkit`。
2. 一台能访问真实 Apple Health ECG 数据的兼容 iPhone。
3. 只请求 ECG 读取权限；`toShare` 必须为空。
4. 在真机逐项完成 [NEEDS_MACOS_VALIDATION.md](NEEDS_MACOS_VALIDATION.md)。

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
