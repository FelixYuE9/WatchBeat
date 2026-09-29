# Validation

> **2026-09-28 MVP cleanup:** the PeakSwift benchmark, three-detector vote and WFDB `bxb`
> preparation tooling described in historical sections below were removed from the tree (see Git
> history `c3c3e0e`). Current App-algorithm numbers come from
> `Tools/Validation/evaluate_swift_analyzer_mirror.py`; the Mac checklist for this build is
> [NEEDS_MACOS_VALIDATION.md](../NEEDS_MACOS_VALIDATION.md).
>
> **2026-09-29 Data/waveform UI follow-up:** high-contrast list cards, deferred per-record local
> screening badges, a scrolling seconds axis and exact candidate-time labels are implemented in
> source. `python -m unittest discover -s Tools/Validation/tests -p 'test_*.py'` passed 47/47 and
> `git diff --check` passed on Windows. Swift/Xcode is unavailable on this host, so the added
> summary-cache, request-isolation and time-tick Swift tests still require the Mac checklist.

## 验证状态摘要

截至 2026-09-28，Milestone 0 已在真实 Swift/Xcode 环境编译并通过单元测试；Milestone 1 的
iOS 读取层源码已完成，并在 macOS 上编译与测试通过。用户截图确认修复后的 App 已在 iPhone 17 Pro /
iOS 26.5 模拟器安装和启动，且之后的截图确认能显示 15,000 点的内置合成波形。
用户随后确认 v0.3.0 (3) 整体在模拟器运行正常，并提供了中文数据页截图。v0.3.0 (4)
把合成示例改为固定数据记录后，用户又报告所要求的 Mac/Xcode 测试通过；但未提供带测试
数量的最终摘要，因此属于用户验收记录，不等于已归档的 shared-scheme 自动测试证据。
v0.4.0 (5) 已在源码中接通 HealthKit/合成 `ECGSignal` → 纯 Swift analyzer →
`ECGAnalysisReport` → 详情页/JSON；Xcode App target 同时具备自动签名与 Archive 配置，选择
Team/唯一 Bundle ID 后可以打包安装到实际 iPhone。本轮 Windows 无法运行 Swift/Xcode，
所以“可以打包安装”的工程能力与“当前 commit 已在真机实际运行”的验证证据必须区分。
现已有 MIT-BIH 公开数据的 development-only R 峰初筛结果；尚无独立 validation、官方 `bxb`
交叉核对、beat 分类性能报告或 Apple Watch 域准确率。不得把下文开发集的 sensitivity、
precision、recall 或 F1 改称为正式 App 或 Apple Watch 的性能。

当前关键限制：模拟器已经可用，且用户报告 **v0.3.0 (4) 测试通过，但 v0.4.0 (5) 的完整
Xcode build/test 日志未归档，也没有完成签名真机运行**。HealthKit entitlement、自动签名、
Archive 和完整数据流的工程配置已完成，仍须在签名产物与真机上验证。

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
后续 Milestone 3 把覆盖范围扩展到官方 checksum 中的安全嵌套路径、受限并发下载、WFDB header /
MIT annotation 解析、完整数据重哈希、冻结 split 推导、manifest lock、零参考 QRS 窗口，以及
30 秒窗口、split 防泄漏、150 ms 一对一匹配、配置哈希、空预测和指标汇总。PeakSwift
follow-up 又增加显式 split projection、held-out 防误用、精确 package/submodule revision、许可证、
无标签解码、版本元数据一致性与 process-local HTTPS rewrite 检查。Mac 首次构建通过后，又增加
development-only 九算法编排、release/debug 配置记录，以及报告的数据集/window/split/matching/count
一致性比较。比较器还核对包含参考峰位置的完整基准定义哈希和逐窗口计数。当前 Python suite
合计 70 tests，全部通过；本机重新生成 2,880 个窗口的 manifest 与锁文件一致。该环境没有
Swift/Xcode，因此没有把静态检查写成
本次 Swift/Xcode 复验。

### v0.4.0 (5) 统一 App 闭环的本机检查（2026-09-28）

- `python -m unittest discover -s Tools/Validation/tests -p "test_*.py"`：70/70 通过。
- `test_ios_project_configuration.py`：8/8 通过，包含新 Swift 源文件 target membership、
  HealthKit、iPhone-only、framework ID、只读用途字符串与 shared scheme 检查。
- `git diff --check`：通过。
- 以与 Swift 实现相同的 biquad、梯度能量、积分、阈值、细化和 RR 规则做数值等价检查：
  现有 30 秒/500 Hz 内置波形检测 35 个 R 峰、0 个提前候选；15 秒/250 Hz 提前样例检测
  14 个峰，并在 6.200 秒得到唯一候选（ratio 0.70）；规则样例为 14 峰/0 候选。
- 当前 Swift tests 源码数量：`ECGCore` 12 项、iOS 26 项；Windows 没有 Swift/Xcode，未执行，
  必须在 Mac 复跑后才可写成通过。

### PeakSwift macOS 构建证据（2026-09-28）

用户在仓库根目录实际执行：

```bash
bash Tools/run-peakswift-benchmark-tests.sh
```

结果：PeakSwift `1.0.0` 与 Surge `2.3.2` 成功解析；当时的 38 项 Python tests 全部通过；
SwiftPM 完成包含 C/C++/Objective-C++ 子模块的 debug 链接（`Build complete! (80.78s)`），并在
`x86_64-apple-macos14.0` 上打印 `[4/4]` 执行四项 `WFDB212ReaderTests`。末尾 Swift Testing
runner 的 `0 tests in 0 suites` 只表示该 package 没有使用 Swift Testing 风格用例；四项 XCTest
已由 SwiftPM 的 parallel XCTest runner 执行。该命令没有运行任何 detector 数据集，因此不能据此
产生准确率结论。

用户随后再次运行同一测试脚本并提供完整末尾输出：47 项 Python tests 通过，Swift debug
构建完成（`Build complete! (0.31s)`），适配器 XCTest 显示 `[4/4]`；末尾的 Swift Testing
`0 tests` 仍是另一运行器的结果。

该次构建报告 Surge 未被 root target 直接使用；这是为了收窄 PeakSwift 的传递依赖版本而添加的
exact root constraint。后续源码同时把 Surge product 声明为 benchmark-support target dependency，
保留精确约束并消除该非功能性警告；这项小改动仍会在下一次 benchmark 命令中重新编译验证。

### PeakSwift development-only 初筛（2026-09-28）

用户提供 Mac 端生成的九算法 `comparison.json`，以及 `neurokit` 和 `pan-tompkins` 的逐窗口
report JSON。九份汇总均为同一 `development` split：1,800 个 30 秒窗口、67,351 个参考 QRS。
比较文件的 `benchmarkDefinitionSHA256` 为
`8c99c5a9e92abb89c400918a5773ec97545c9dc19eb4f393dfd7e8e695ecf00d`，与本机从锁定
manifest 重算的值一致。两份逐窗口报告通过本仓库比较器检查，且各自的配置哈希、基准哈希、
TP/FP/FN 与九算法比较文件一致。原始 Mac 运行未在本机复现；这里记录的是用户提供的产物。

| PeakSwift 算法 | F1 | Recall | PPV | FP | FN | 时间误差 p95 (ms) |
|---|---:|---:|---:|---:|---:|---:|
| neurokit | 0.9826 | 0.9758 | 0.9895 | 697 | 1,632 | 11.1 |
| pan-tompkins | 0.9808 | 0.9850 | 0.9765 | 1,594 | 1,010 | 97.2 |
| kalidas | 0.9753 | 0.9697 | 0.9810 | 1,262 | 2,040 | 44.4 |
| two-average | 0.9644 | 0.9709 | 0.9580 | 2,866 | 1,961 | 80.6 |
| hamilton | 0.9586 | 0.9744 | 0.9433 | 3,944 | 1,722 | 111.1 |
| nabian2018 | 0.9284 | 0.9139 | 0.9433 | 3,701 | 5,800 | 8.3 |
| engzee | 0.9130 | 0.8453 | 0.9925 | 433 | 10,422 | 5.6 |
| christov | 0.8838 | 0.9843 | 0.8019 | 16,374 | 1,059 | 61.1 |
| unsw | 0.7432 | 0.9988 | 0.5918 | 46,401 | 81 | 16.7 |

表中的 `neurokit` 是 PeakSwift v1.0.0 的算法名，不表示已安装或评测 Python NeuroKit2。
按逐记录 F1，`neurokit` 在 30 条中的 26 条领先，但有两个明显失效点：记录 207 为
TP 1,321 / FP 57 / FN 529 / F1 0.8185（`pan-tompkins` 为 1,824 / 354 / 26 / 0.9057）；
记录 231 为 1,546 / 407 / 19 / 0.8789（`pan-tompkins` 为 1,539 / 67 / 26 / 0.9707）。
记录 203 的 `neurokit` 也有 270 次漏检，`pan-tompkins` 为 75 次。官方数据库说明记录 207
包含复杂的室扑和传导阻滞，记录 231 包含 2:1 房室传导阻滞与右束支传导阻滞；这些是需要逐段
排查的线索，不构成对具体误差机制的证明。

`neurokit`、`pan-tompkins` 与 `kalidas` 是下一轮优先核查的单算法候选，而非生产 detector
选择。先与官方 WFDB `bxb` 核对匹配器，再冻结候选配置并使用独立 validation；held-out-test
继续封存。`bxb` 默认
跳过每条记录前 5 分钟，而当前 30 秒窗口初筛包含这段数据，因此两套汇总数字不能直接等同。
MIT-BIH 的双导联动态 ECG 结果也不能说明 Apple Watch 单导联 ECG 的性能，更不能说明 PAC/PVC
分类效果。记录说明与 `bxb` 规则见：
<https://physionet.org/physiobank/database/html/mitdbdir/records.htm>、
<https://physionet.org/physiotools/wag/bxb-1.htm>。

### 三算法投票的 development-only 探索（2026-09-28）

用户随后提供上述三种算法的逐峰预测文件。本机用相同的 manifest 重新评测三份预测；其中
`neurokit` 和 `pan-tompkins` 的新报告与用户提供的 Mac 报告逐字段相同。新增离线工具只根据
窗口元数据和三个检测结果对齐峰位，同一算法对同一候选最多投一票，不查看参考标注；每组
参数再交给原评测器计分。投票先按票数多、组内跨度小的确定性贪心规则选择峰组；这只是待检验
的融合策略，不能被解释为已验证的最优匹配。

三份用户提供的原始预测文件 SHA-256 分别为：`neurokit`
`b1f75d3994dfab0bc7aed26e1e6c09896322719fbfc4ceb9a067877b785b795f`，
`pan-tompkins` `ce1bdfbf6e07e3455650c3849f774db8838ea0e46c3e5cc63735a939c482d067`，
`kalidas` `11fa25081830b69c3141477359c4b2e5087ce142b5c69e729c64131fd0dba015`。
本机 Windows Python 回归测试现为 59/59；没有再次声称 macOS Swift 构建已运行。

| 投票门槛 | 对齐容差 (ms) | F1 | Recall | PPV | FP | FN |
|---|---:|---:|---:|---:|---:|---:|
| 2/3 | 60 | 0.9744 | 0.9584 | 0.9910 | 588 | 2,799 |
| 2/3 | 80 | 0.9831 | 0.9765 | 0.9898 | 681 | 1,581 |
| 2/3 | 100 | 0.9855 | 0.9826 | 0.9884 | 779 | 1,173 |
| 2/3 | 120 | 0.9853 | 0.9832 | 0.9875 | 840 | 1,134 |
| 2/3 | 150 | 0.9857 | 0.9850 | 0.9865 | 908 | 1,012 |
| 3/3 | 80 | 0.7290 | 0.5738 | 0.9993 | 29 | 28,705 |
| 3/3 | 120 | 0.9583 | 0.9204 | 0.9994 | 40 | 5,358 |
| 3/3 | 150 | 0.9671 | 0.9371 | 0.9992 | 49 | 4,239 |

相对于三个单算法，2/3 投票在 100–150 ms 范围提高了该开发集的总体 F1，但改变了
误报/漏检平衡，不存在只凭一个总分就能定的参数。100 ms 版本在记录 207 的 F1 为
0.9394（单算法最高为 `kalidas` 0.9065），记录 231 为 0.9825（单算法最高为
`kalidas` 0.9767）；记录 203 则仍落后于 `pan-tompkins`（0.9761 对 0.9784）。
3/3 投票看似有极高 PPV，却漏掉大量真实峰，不适合仅按误报数选用。

逐峰复核显示：记录 203 有 44 个参考峰仅被 `pan-tompkins` 命中，2/3 投票会将其舍弃；
全开发集另有 194 个参考峰被至少两种单算法分别命中、却未被 100 ms 投票命中；
逐个检查后，这 194 个峰的命中位置在算法之间均相差超过 100 ms，没有发现容差内的
双算法峰被贪心分组抢走。记录 208 单独占其中 104 个：`neurokit` 为
TP 2,906 / FP 4 / FN 40 / F1 0.9925，而 100 ms 2/3 投票为
2,791 / 5 / 155 / 0.9721。150 ms 投票使记录 208 的 F1 回到 0.9904，
却将记录 207 的误报从 181 增到 212（F1 从 0.9394 降至 0.9349），
因此没有一个仅凭总体 F1 就可确定的通用容差。
记录 207 的两个零参考峰窗口中，100 ms 的 2/3 投票分别仍输出 33 和 23 个假峰，
说明多数投票不能替代信号质量门控。这些是开发集诊断，不应用记录特例去拟合生产规则。

已新增独立 WFDB 交叉核对准备工具；本机运行 100 ms、2/3 投票输入生成成功，覆盖
30 条 development 记录、1,800 个窗口、66,957 个预测峰，各记录都止于 30 分钟完整窗口。
Mac 脚本会先重新校验 manifest 锁，再用官方 `wrann` 写入、`rdann` 回读逐样本核验，最后以
`bxb -f 0` 比较。当前 Windows 环境没有 `wrann`、`rdann` 或 `bxb`，**尚未执行官方比较**；
`bxb` 使用连续记录和 AAMI 注释规则，数字不保证与逐窗口自定义评测器完全相同。

这些参数是研究工具的 `minVotes` 和对齐容差，不等同于 PeakSwift 内部检测阈值；后者
尚未审计可配置接口。投票提升仅限本次 MIT-BIH development，尚须复核峰组边界、官方
`bxb`、独立 validation 和 Apple Watch 单导联域。App 暂不加入投票或可改阈值的设置。

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
- `python Tools/Validation/build_mitdb_manifest.py`：从全部 48 records / 47 subjects 重生成
  2,880 个窗口和 109,150 个参考 QRS；与 committed lock 完全一致，输出 2,665,330 bytes，
  SHA-256 `55143a8301860ec3744fdf7e8d9cef31c0d6ed3ea82b8f73a42d2452b416f382`。
- 本地下载共 145 个必需文件、约 104.3 MB；所有文件在下载后按官方 checksum 验证，
  manifest 重生成前又按 receipt 全量重哈希。`data/` 与 `output/` 均由 Git 忽略。
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

这证明旧版 Milestone 0 的 `ECGCore` 契约与完整性检查**已真实编译并通过测试**。当前新增
analyzer 后共有 12 项测试，仍需重新编译，不能把旧 7 项结果冒充为 build 5 结果。

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

1. App 已在 iPhone 17 Pro / iOS 26.5 模拟器运行；v0.3.0 (3) 合成波形、概览、数据和设置页已有截图，
   v0.3.0 (4) 又由用户报告测试通过。但 shared scheme test action 的完整摘要/数量没有归档，
   截图和用户反馈也不证明真机 HealthKit。
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
| 最小 pure-function tests | 旧 7 tests 通过；当前 12 tests 待 Mac 复跑 | `Tools/run-core-tests.sh --parallel` |
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
| 本机编译与单元测试 | 既有版本通过 SwiftPM 构建与 16 tests；build 5 的 26 tests 待 macOS 复验 | 16 tests 在 macOS 执行，当前新增源码仅通过静态检查 |
| Xcode 工程构建（App + 测试 bundle） | 通过：3 条 `xcodebuild -target` 命令 BUILD SUCCEEDED | Xcode 26.6，iOS 26.5 / iOS Simulator 26.5 SDK |
| iPhone-only、framework IDs 与共享 scheme | 源码完成 + 5 项配置测试通过 | 需在 macOS 重新执行共享 scheme |
| Xcode scheme + destination 构建 | 模拟器安装/启动已观察；命令待重跑 | 用户截图，缺完整 build/test 输出 |
| App 在模拟器/真机运行 | 模拟器已运行；真机未执行 | iPhone 17 Pro / iOS 26.5 截图；无真机证据 |
| 真机授权/列表/详情验证 | 未验证 | 见 `NEEDS_MACOS_VALIDATION.md` |

## Milestone 2 验收表

| 条件 | 状态 | 证据/限制 |
|---|---|---|
| 全分辨率与显示降采样分离 | 源码完成 | `ECGDisplayDownsampler`；新增 Swift tests 待 macOS 执行 |
| 滚动/缩放波形与 timestamp marker | v0.3.0 (3) 模拟器已显示 | SwiftUI Canvas，1×–8×；缺自动测试输出 |
| 内置合成教学 ECG | v0.3.0 (3) 模拟器已显示 | UI/JSON/文件名显式 synthetic；不是人体或验证数据 |
| 概览/数据/设置导航与语言切换 | v0.3.0 (3) 用户手工运行正常 | 无 shared-scheme 自动测试输出 |
| 合成/HealthKit 共用模型 R–R marker | build 5 源码完成 | marker 均来自同一 `ECGAnalysisReport`；待 Xcode/真机运行 |
| “示例 ECG 数据”固定记录卡 | v0.3.0 (4) 用户确认通过 | 已删除数据空状态内的“查看内置示例”按钮；缺完整 Xcode 日志 |
| raw CSV、metadata JSON、analysis JSON | build 5 源码完成 | 统一 v1 输入/输出；share sheet + 临时文件清理；待 Xcode 构建 |
| 当前 Swift tests | 源码完成 | 预期 26 iOS tests；build 4 用户报告通过，build 5 未运行 |
| 可打包/安装工程配置 | 完成 | automatic signing、HealthKit、Archive；需本地 Team/Bundle ID |
| 真实 HealthKit 导出一致性 | 未验证 | 必须在真机逐样本核对 |

## Milestone 3 验收表（进行中）

在进一步比较/投票 R 峰算法之前，2026-09-28 已在 Windows 用同一个 WatchBeat CSV
输入契约跑通最小波形分析闭环：MIT-BIH 200 号 `.hea/.dat` 经独立 adapter 转为
650,000 行 `time_s,voltage_mV`，分析器只读此 CSV，输出 R 峰、RR 和
`prematureUncertain` 候选。`.atr` 标注仅在之后的独立 smoke-check 中读取。
命令为 `convert_mitdb_to_watchbeat_csv.py 200 --output ...`、
`prototype_premature_beats.py <converted.csv> --output ...` 和
`evaluate_prototype_premature_beats.py 200 <converted.csv>`；Windows Python 3.10.9、
NumPy 1.23.5、SciPy 1.10.0，未使用 Mac/WFDB CLI。结果为 2,593 个检测峰、
466 个提前候选；与 2,601 个参考 QRS 的简单 150 ms 顺序匹配为 TP 2,592、FP 1、
FN 9；856 个参考提前心搏中 458 个被标记，398 个漏标，另有 8 个候选落在其他
或未匹配位置。该顺序匹配不是官方 `bxb`，只有一个 development record，不能泛化为
公开数据总体、Apple Watch 或 PAC/PVC 准确率。build 5 已把等价最小流程用纯 Swift 接入
iOS；这不代表 Python/SciPy 进入 App，也不把该单记录数字转移成 App 性能声明。

| 条件 | 状态 | 证据/限制 |
|---|---|---|
| MIT-BIH v1.0.0 固定下载 | 完成（本地、Git 忽略） | 48 records / 145 files / 约 104.3 MB；官方 SHA-256 全部通过 |
| 30 s manifest 与 split 防泄漏 | 已冻结 | 47 subjects / 2,880 windows / 109,150 QRS；201/202 同 subject；有 lock 校验 |
| R 峰一对一匹配 | 源码 + 回归测试通过 | 150 ms；最大匹配数后最小总误差；尚须与 WFDB `bxb` 交叉核对 |
| PeakSwift 候选 adapter | macOS build + 4 adapter tests 通过 | v1.0.0/full SHA + Surge/IIR/wavelib pins；独立工具 |
| Split 使用顺序 | 工具强制 | CLI 必须显式指定；held-out-test 还需第二个 unlock flag |
| R 峰性能报告 | development 初筛完成 | 9 个 PeakSwift 算法的公开数据汇总；缺 `bxb`、独立 validation、Python reference 与 Apple Watch 域验证 |

## 首次可用 Swift 环境的必跑命令

```bash
cd ECGCore
swift package describe
swift test --parallel
```

已执行（macOS 26.7 + Swift 6.2.4，仅 Command Line Tools）：`swift test --parallel` 通过
7 tests / 2 suites（历史基线）。当前 build 5 应执行 12 tests；尚未在 Mac 复跑。

共享 `WatchBeatApp` scheme 和 simulator runtime 均已存在。现在必须对当前 revision 执行
`xcodebuild build` 和 `xcodebuild test`，并操作合成示例的 waveform/export。命令、Xcode/Swift
版本、destination、签名 entitlement 和完整结果摘要要回填本文件；工程可以打包安装，真机
实际运行仍需要本地 Team、唯一 Bundle ID、兼容设备和 HealthKit 数据。

## 计划中的离线验证

### R 峰

契约已冻结 150 ms 时间容差和一对一匹配，并输出 recall/sensitivity、precision/PPV、
F1、FP/30 s、FN/30 s、timing error median/p95，可按窗口、split 与全局汇总。真实
record/subject split 和生成 manifest 已由 committed lock 固定；下一步是与官方 WFDB `bxb`
交叉核对，并接入候选 detector 生成尚未查看 held-out-test 的预测。

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
