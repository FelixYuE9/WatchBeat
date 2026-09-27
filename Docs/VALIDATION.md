# Validation

## 验证状态摘要

截至 2026-09-27，Milestone 0 已在真实 Swift/Xcode 环境编译并通过单元测试；Milestone 1 的
iOS 读取层源码已完成，并在 macOS 上编译与测试通过。用户截图确认修复后的 App 已在 iPhone 17 Pro /
iOS 26.5 模拟器安装和启动，且之后的截图确认上一版能显示 15,000 点的内置合成波形。
当前 v0.3.0 新增概览/底部导航/语言设置和合成 R–R 毫秒标注，但该 revision 尚未在 macOS 编译。
仍然没有 R 峰或 beat 分类性能报告，也没有
Apple Watch 域准确率。任何 sensitivity、specificity、precision、recall 或 accuracy
声明在当前阶段都是不真实的。

当前关键限制：模拟器已经可用，但**当前 v0.3.0 revision 尚未执行 Xcode build/test，也没有
完成签名真机运行**。HealthKit entitlement 的工程配置已修正，仍须在签名产物与真机上验证。

## 实际环境审计（2026-09-26 / 2026-09-27）

工作目录：当前 Git repository root。公开文档不固化本机用户名或绝对路径；原始 `pwd`
结果只用于本次开发会话审计。

### 2026-09-26：只有 Command Line Tools

| 检查 | 实际结果 |
|---|---|
| `sw_vers` | macOS 26.7，Build 25G229 |
| `uname -a` | `Darwin ... 25.6.0 ... RELEASE_X86_64 x86_64`（Intel Mac） |
| `xcode-select -p` | `/Library/Developer/CommandLineTools`（不是 Xcode） |
| `swift --version` | Apple Swift 6.2.4（swiftlang-6.2.4.1.4 clang-1700.6.4.2），swift-driver 1.127.15 |
| `xcodebuild -version` | **失败**：`tool 'xcodebuild' requires Xcode ...` |
| `xcrun --sdk iphoneos/iphonesimulator` | **失败**：`SDK "iphoneos" cannot be located` |
| `xcrun simctl list devices` | **失败**：`unable to find utility "simctl"` |
| 可用 SDK | 只有 `MacOSX*.sdk`；无任何 iPhoneOS/iPhoneSimulator SDK |

### 2026-09-27：Xcode 26.6 已安装（在 `~/Downloads/Xcode.app`）

| 检查 | 实际结果 |
|---|---|
| `xcodebuild -version`（`DEVELOPER_DIR` 指向 Xcode） | Xcode 26.6，Build version 17F113 |
| `xcrun swift --version` | Apple Swift 6.3.3（swiftlang-6.3.3.1.3 clang-2100.1.1.101），swift-driver 1.148.6 |
| `xcodebuild -showsdks` | iOS 26.5、iOS Simulator 26.5、macOS 26.5、tvOS 26.5、visionOS、watchOS、DriverKit |
| `xcrun --sdk iphoneos --show-sdk-path` | `.../Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk` |
| `xcrun --sdk iphonesimulator --show-sdk-path` | `.../Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk` |
| `xcode-select -p`（系统默认，未 sudo） | 仍是 `/Library/Developer/CommandLineTools`；切换需 `sudo xcode-select -s <Xcode.app>/Contents/Developer` |
| `xcrun simctl list runtimes` | **当时为空**：该次检查尚未安装 iOS 模拟器运行时 |
| `xcrun simctl list devices` | **当时为空**：该次检查尚无可用模拟器设备 |
| `iPhoneOS.platform/DeviceSupport` | 只有 15.0–16.4；缺 iOS 26.5 设备支持，故 "Any iOS Device" 报 `iOS 26.5 is not installed` |

历史记录（本仓库初始化时）：Windows 10.0.19045、PowerShell 7.6.5、`git --version`
`2.39.1.windows.1`、`python --version` `3.10.9`，Swift 与 Xcode 均不可用。

该表是首次安装 Xcode 时的历史快照。随后 simulator runtime 已安装；用户提供的截图显示
`iPhone 17 Pro / iOS 26.5` 上的 App 已启动并进入 “No accessible ECG records” 状态。没有保存
对应命令的完整输出，因此不能据此宣称 shared scheme 的 test action 已通过。真机 HealthKit
验收依旧未执行。

## 本轮实际执行结果

```text
python -m unittest discover -s Tools/Validation/tests -v
```

首次运行失败：测试通过 `importlib` 动态载入模块时未先登记 `sys.modules`，Python 3.10
的 `dataclass` 无法解析模块 namespace。修复测试 loader 后重新运行：3 tests，全部通过，
exit 0。保留此失败记录，避免把"最终通过"写成"一次即通过"。

2026-09-27 的 Windows follow-up 先增加 5 项 iOS 工程配置回归测试，覆盖正确的
`CODE_SIGN_ENTITLEMENTS`、iPhone-only、embedded framework bundle identifiers、只读 HealthKit
plist/entitlement 与共享 scheme；Milestone 2 又增加 1 项 Xcode source-membership 检查。
当前 Python suite 合计 9 tests，全部通过；该环境没有
Swift/Xcode，因此没有把静态检查写成
本次 Swift/Xcode 复验。

同日的 Milestone 2 follow-up 新增 9 项 Swift 测试，覆盖显示降采样不修改原始数据、extrema、
缺测 gap、真实 timestamp 映射、CSV 顺序/缺测、JSON 去除 HealthKit ID，以及内置合成示例的
确定性和来源标记，以及合成 R 峰间隔计算/异常 marker 过滤。当前 Windows 主机不能运行 Swift；这 9 项测试仅完成源码和 Xcode target
membership 静态检查，必须在 macOS 上运行后才可写成通过。

```text
python Tools/Validation/validate_raw_ecg_csv.py \
  Tools/Validation/tests/fixtures/raw_valid.csv
```

结果：exit 0；4 samples；missing index `[2]` 被保留；推断 500 Hz；relative MAD 0；
`structurally_valid: true`。fixture 是手工合成结构数据，不是人体 ECG，也不证明算法表现。

其他实际审计：

- `python -m compileall -q Tools/Validation`：通过。
- required-file existence check：15/15 存在。
- local Markdown link target check：通过，无缺失的本地目标。
- trailing-whitespace scan：通过。
- `ECGCore/Package.swift` external `.package(...)` scan：无第三方 Swift dependency。
- `git check-ignore`：私有 ECG、下载数据和用户导出示例均命中预期忽略规则。

## ECGCore 实际执行结果（2026-09-26）

```bash
Tools/run-core-tests.sh --parallel
```

结果：`Build complete!` → `Test run with 7 tests in 2 suites passed`，退出码 0。环境为
macOS 26.7 + Swift 6.2.4（仅 Command Line Tools）。链接期有两条无害告警：重复 `-rpath`
与 Swift Testing dylib 的 deployment target 差异。

Xcode 26.6 安装后同一脚本再次执行（`bash Tools/run-core-tests.sh --parallel`，Xcode 工具链
Swift 6.3.3）：同样是 `Test run with 7 tests in 2 suites passed`。

这证明 Milestone 0 的 `ECGCore` 契约与完整性检查**已真实编译并通过测试**，不再是"未验证的源码"。

## iOS App 实际执行结果（2026-09-26 / 2026-09-27）

| 命令（工作目录） | 结果 |
|---|---|
| `swift build`（`iOS`） | `Build complete!`：macOS 14 deployment target，含 SwiftUI 与 HealthKit 全部模块 |
| `swift build --triple x86_64-apple-ios17.0-macabi --target WatchBeatHealthKit`（`iOS`） | `Build of target: 'WatchBeatHealthKit' complete!`：以 **iOS 17 API** 编译 HealthKit 读取层 |
| `swift build --triple arm64-apple-ios17.0`（`iOS`） | **失败**：`unable to load standard library for target 'arm64-apple-ios17.0'`（无 iPhone SDK） |
| `swift build --triple arm64-apple-ios17.0`（`ECGCore`） | **失败**：同上 |
| `bash Tools/run-app-tests.sh --parallel` | `Test run with 16 tests in 2 suites passed` |
| `swift build --build-tests`（带 Swift Testing flags，`iOS`） | `Build complete!`，无告警 |
| `xcodebuild -scheme ...` | **未执行**：无 Xcode，无 scheme（2026-09-26） |

### Xcode 26.6 之后的真实构建（2026-09-27）

工程：`iOS/WatchBeat.xcodeproj`（手写 `project.pbxproj`，Xcode 26.6 可解析）。target：
`ECGCore`、`WatchBeatModels`、`WatchBeatHealthKit`（framework）与 `WatchBeatApp`（application）、
`WatchBeatAppTests`（unit-test bundle）。

`DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer`；因为系统
`xcode-select` 仍指向 Command Line Tools（切换需要 sudo），所有命令都显式带该变量。

| 命令（工作目录 `iOS`） | 结果 |
|---|---|
| `xcodebuild -project WatchBeat.xcodeproj -list` | 5 targets、Debug/Release、schemes `ECGCore` 与 `WatchBeatApp` |
| `xcodebuild -target WatchBeatApp -sdk iphonesimulator26.5 -arch x86_64 CODE_SIGNING_ALLOWED=NO build` | **BUILD SUCCEEDED** |
| `xcodebuild -target WatchBeatAppTests -sdk iphonesimulator26.5 -arch x86_64 CODE_SIGNING_ALLOWED=NO build` | **BUILD SUCCEEDED** |
| `xcodebuild -target WatchBeatApp -sdk iphoneos26.5 -arch arm64 CODE_SIGNING_ALLOWED=NO build` | **BUILD SUCCEEDED**（当时含一条 iPad 方向告警；后续已改为 iPhone-only，待 macOS 复验） |
| `swift build --triple arm64-apple-ios17.0 --sdk <iPhoneOS26.5.sdk>` | `Build complete!` |
| `swift build --triple x86_64-apple-ios17.0-simulator --sdk <iPhoneSimulator26.5.sdk>` | `Build complete!` |
| `bash Tools/run-app-tests.sh --parallel`（Xcode 工具链） | `Test run with 16 tests in 2 suites passed` |
| `xcodebuild -scheme WatchBeatApp -destination 'generic/platform=iOS Simulator' build` | **失败**：`Unable to find a destination matching the provided destination specifier` |
| `xcodebuild -scheme WatchBeatApp -destination 'generic/platform=iOS' build` | **失败**：`iOS 26.5 is not installed. Please download and install the platform from Xcode > Settings > Components.` |

为什么用 `-target` 而不是 `-scheme`：scheme 路径要求 destination 数据库里有可用设备/运行时，
本机两者都缺；`-target` + `-sdk` 直接构建，不查 destination。这能验证 App target 的编译、链接、
Info.plist 处理，但无签名构建不能验证最终签名中的 entitlement，且**不等于运行过 App**。

后续静态修复已提交共享 `WatchBeatApp` scheme，把 App 限定为 iPhone，并将误写的
`CODE_ENTITLEMENTS` 更正为 `CODE_SIGN_ENTITLEMENTS`，同时登记 HealthKit system capability。
第一次 macOS scheme build 随后真实失败：嵌入 App 的 `ECGCore`、`WatchBeatModels` 与
`WatchBeatHealthKit` framework 的生成 plist 都没有 `CFBundleIdentifier`。原因是三个 framework
target 的 Debug/Release 配置均缺 `PRODUCT_BUNDLE_IDENTIFIER`；现已分别补上唯一标识并加入回归测试。
这些配置当前通过 6 项 Python 回归测试。其后用户截图确认 framework 修复后的 App 能在模拟器安装并
启动；但由于没有保留命令输出，且又加入 Milestone 2 源码，仍须回到 macOS 执行当前 revision 的
scheme build/test 与签名产物检查。

编译可行性说明（本机实测）：

- macOS SDK 自带 `HealthKit.framework`，且 `HKElectrocardiogram`、`HKElectrocardiogramQuery`、
  `HKElectrocardiogramQueryDescriptor` 的可用性标注包含 `macos(13.0)`，所以读取层可在 macOS
  目标真实编译。
- `HealthKit.swiftmodule` 含 `x86_64-apple-ios-macabi` 切片，因此可用 iOS 17（Mac Catalyst）
  triple 编译；但 `SwiftUI.framework` **没有** macabi 切片，SwiftUI 模块只能用 macOS 目标编译。
  这也是把 `WatchBeatModels`/`WatchBeatHealthKit` 与 SwiftUI 拆成不同模块的原因。

失败与限制（保留，不改写为成功）：

1. App 已在 iPhone 17 Pro / iOS 26.5 模拟器运行，且上一版合成波形已有截图；但当前 v0.3.0 revision 尚未重新构建，
   shared scheme test action 也没有结果记录。截图不证明真机 HealthKit。
2. 真机 HealthKit 授权、measurement 完整性与真实 sampling metadata **未验证**。
3. 单元测试使用 `FakeECGReader` 替身：真实 `HKElectrocardiogram` 无法在测试中构造，所以
   mapper 测试只覆盖 `HKQuantity` 电压换算接缝，不覆盖 `HKElectrocardiogram` 元数据映射。
4. Xcode 工程中的 `PRODUCT_BUNDLE_IDENTIFIER` 是占位值 `com.watchbeat.WatchBeat`；真机运行前
   必须换成开发者自己的 team/bundle id。HealthKit entitlement 源码配置已修正，但此前构建全部
   使用 `CODE_SIGNING_ALLOWED=NO`，所以签名产物仍未验证。
5. 本机 Command Line Tools 的 `_Testing_Foundation` 交叉导入模块损坏
   （`_Testing_Foundation.framework/Modules` 指向不存在的目录），因此测试文件不能同时
   `import Testing` 与 `import Foundation`；测试代码已规避，未删除任何测试。

## Milestone 0 验收表

| 条件 | 状态 | 证据/限制 |
|---|---|---|
| 环境与 Git 审计 | 完成 | 上表记录实际输出 |
| 文档结构 | 完成 | `README.md`、`Docs/`、`TODO.md` 等 |
| 平台无关 ECGCore | 完成：已编译 | `swift build` / `swift test` 见上 |
| 最小 pure-function tests | 完成：7 tests 通过 | `Tools/run-core-tests.sh --parallel` |
| Python raw CSV checker | 完成并在 Python 3.10.9 通过 3 tests | 仅结构检查，不是 ECG 算法 |
| dependency ADR | 完成 | `Docs/ADR/0001-...md` |
| 私有 ECG Git 隔离 | 完成 | `.gitignore` 与目录安全说明 |
| Xcode 编译 | 完成：target 构建通过 | Xcode 26.6；scheme/destination 运行属于 Milestone 1 |
| 真实 iPhone ECG | 未验证 | 需要兼容 iPhone、权限和真实记录 |

## Milestone 1 验收表

| 条件 | 状态 | 证据/限制 |
|---|---|---|
| iOS 17 SwiftUI 工程与测试目标 | 完成：SwiftPM 包 + `iOS/WatchBeat.xcodeproj`（5 targets） | `xcodebuild -list` 输出 |
| HealthKit 只读授权（`toShare` 为空） | 源码完成 | `LiveHealthKitECGReader.requestReadOnlyAuthorization()` |
| 读取用途字符串与 entitlement | 源码配置完成；签名产物未验证 | `CODE_SIGN_ENTITLEMENTS` + HealthKit system capability；需真机签名检查 |
| metadata 列表查询（按开始时间排序） | 源码完成 | `HKSampleQueryDescriptor` + `SortDescriptor` |
| 惰性电压读取 + 取消/陈旧保护 | 源码完成 + 2 项测试通过 | `ECGRepository` generation 检查 |
| 顺序/时间/缺测/声明数量保持 | 源码完成 + 测试通过 | `ECGHealthKitMapper` 与 `ECGSignalInspector` |
| mV 换算（只做一次） | 源码完成 + 测试通过 | `ECGHealthKitMapper.millivolts(from:)` |
| 区分 unavailable/empty/failure/incomplete | 源码完成 + 4 项状态测试 | `ECGListState`、`ECGMeasurementIssue` |
| 首次启动与结果页免责声明 | 源码完成 | `Features/Disclaimer/` |
| 本机编译与单元测试 | 既有版本通过 SwiftPM 构建与 16 tests；修复后工程待 macOS 复验 | 16 tests 在 macOS 执行，Xcode iOS test bundle 仅构建 |
| Xcode 工程构建（App + 测试 bundle） | 通过：3 条 `xcodebuild -target` 命令 BUILD SUCCEEDED | Xcode 26.6，iOS 26.5 / iOS Simulator 26.5 SDK |
| iPhone-only、framework IDs 与共享 scheme | 源码完成 + 5 项配置测试通过 | 需在 macOS 重新执行共享 scheme |
| Xcode scheme + destination 构建 | 模拟器安装/启动已观察；命令待重跑 | 用户截图，缺完整 build/test 输出 |
| App 在模拟器/真机运行 | 模拟器已运行；真机未执行 | iPhone 17 Pro / iOS 26.5 截图；无真机证据 |
| 真机授权/列表/详情验证 | 未验证 | 见 `NEEDS_MACOS_VALIDATION.md` |

## Milestone 2 验收表

| 条件 | 状态 | 证据/限制 |
|---|---|---|
| 全分辨率与显示降采样分离 | 源码完成 | `ECGDisplayDownsampler`；新增 Swift tests 待 macOS 执行 |
| 滚动/缩放波形与 timestamp marker | 上一版模拟器已显示 | SwiftUI Canvas，1×–8×；当前 v0.3.0 待复验 |
| 内置合成教学 ECG | 上一版模拟器已显示 | UI/JSON/文件名显式 synthetic；不是人体或验证数据 |
| 概览/数据/设置导航与语言切换 | 源码完成 | 当前 v0.3.0 待 Xcode 编译与模拟器 UI 复验 |
| 合成 ECG 逐个 R–R 毫秒标注 | 源码完成 | 来自生成方程的已知 marker；不是 detector；真实 ECG 不显示 |
| raw CSV 与 metadata JSON | 源码完成 | 用户确认 + share sheet + 临时文件清理；待 iOS 构建 |
| 当前 Swift tests | 未执行 | 预期 25 tests；既有 16 曾通过，新增 9 待运行 |
| 真实 HealthKit 导出一致性 | 未验证 | 必须在真机逐样本核对 |

## 首次可用 Swift 环境的必跑命令

```bash
cd ECGCore
swift package describe
swift test --parallel
```

已执行（macOS 26.7 + Swift 6.2.4，仅 Command Line Tools）：`swift test --parallel` 通过
7 tests / 2 suites。

共享 `WatchBeatApp` scheme 和 simulator runtime 均已存在。现在必须对当前 revision 执行
`xcodebuild build` 和 `xcodebuild test`，并操作合成示例的 waveform/export。命令、Xcode/Swift
版本、destination、签名 entitlement 和完整结果摘要要回填本文件；真机读取仍受 device/signing
条件限制。

## 计划中的离线验证

### R 峰

以预先冻结的时间容差匹配 reference beat，至少报告：recall/sensitivity、precision/PPV、
F1、FP/30 s、FN/30 s、timing error median/p95，并按 record 和噪声分层。容差和一对一
匹配算法必须写入报告。

### Beat 分类

逐 beat 报告 PAC/PVC precision、recall、F1，premature detection 指标，完整 confusion
matrix、Uncertain rate/coverage、selective accuracy 和 false alerts/30 s。不得删除
Uncertain 后只展示覆盖子集的漂亮结果。

### 防泄漏

- 按 patient/record 切分 development 与 held-out test。
- 阈值只在 development set 调整；冻结决策后才运行 held-out test。
- 私有 Apple Watch 样本不能同时用于逐例调参与最终准确率。
- 公开动态 ECG 的结果必须标为 public-dataset validation，不能改称 Apple Watch accuracy。

## 真机验收边界

模拟器或 mock 可测试 UI 状态和 mapper，但不能证明：HealthKit 授权语义、measurement
完整性、真实 sampling metadata、Apple Watch 波形兼容性或端到端导出一致性。真机步骤见
[NEEDS_MACOS_VALIDATION.md](../NEEDS_MACOS_VALIDATION.md)。
