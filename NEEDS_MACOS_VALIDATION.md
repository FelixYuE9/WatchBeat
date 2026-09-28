# Mac 打包与测试清单 — v0.5.0 (6) MVP

本版在 Windows 上整理完成：Python 工具与工程配置测试 46/46 通过，App 算法的 NumPy 镜像已在
MIT-BIH 上复测；**Swift 源码尚未在本版本编译**，请按下列顺序在 Mac 上跑一遍并记录结果。

历史记录（供对照）：macOS 26.7 / Xcode 26.6 (17F113，位于 `~/Downloads/Xcode.app`) 曾通过
ECGCore 7 项测试、App/测试 target 构建，并在 iPhone 17 Pro / iOS 26.5 模拟器上运行 v0.3.0。

如果 `xcode-select` 仍指向 Command Line Tools，先执行：

```bash
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
```

## 1. 单元测试（约 2 分钟）

在仓库根目录：

```bash
bash Tools/run-core-tests.sh --parallel   # ECGCore：应为 13 项全部通过
bash Tools/run-app-tests.sh --parallel    # iOS 包：WatchBeatAppTests 全部通过
```

预期 ECGCore 13 项 = ECGSignalInspectorTests 5 项 + PublicContractTests 8 项：结果词汇、默认配置/版本 `1.0.1-rr-research`、输入契约、早搏检出、规则心律
0 候选、缺测拒判、不规则采样拒判、**直流偏移不改变检测结果（新增）**。
iOS 包中新增 `builtInExampleShowsModelDetectedPrematureCandidates`：内置示例应检出 35 个 R 峰、
2 个疑似早搏候选。

## 2. Xcode 构建与模拟器测试

```bash
cd iOS
xcodebuild -project WatchBeat.xcodeproj -scheme WatchBeatApp -showdestinations
xcodebuild -project WatchBeat.xcodeproj -scheme WatchBeatApp \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

本版从 Xcode 工程中移除了 `BeatClassifying.swift`、`ECGQuality.swift`、`RPeakDetecting.swift`
三个文件（`project.pbxproj` 已同步修改）。如果 Xcode 提示找不到文件，说明工程引用没对齐，请告诉我。

## 3. 真机打包安装

1. 打开 `iOS/WatchBeat.xcodeproj` → target **WatchBeatApp** → **Signing & Capabilities**。
2. 选择你的 Team，把 Bundle ID `com.watchbeat.WatchBeat` 改成你自己的唯一 ID；确认 HealthKit 仍在。
3. 选择已连接并解锁的 iPhone（iOS 17+，必要时开启开发者模式）→ **Run**。
4. 打包 Release：**Product → Archive**，或参见 [Docs/IPHONE_INSTALL.md](Docs/IPHONE_INSTALL.md)。

签名证书、描述文件、Team ID 不要提交到 Git。

## 4. 测速

详情页的“本机研究分析”卡片新增 **分析耗时（Analysis time）**，是 `PrematureBeatAnalyzer.analyze`
单次执行的墙钟时间（不含 HealthKit 读取和绘图）。

1. **用 Release 构建测速**（Debug 未优化，Swift 数组代码会慢 5–20 倍）：Scheme → Edit Scheme →
   Run → Build Configuration 选 Release，或直接安装 Archive 出来的包。
2. 打开“数据 → 示例 ECG 数据”（30 秒、500 Hz、15,000 点），记录分析耗时。
   注意：示例在 App 启动时分析一次，这个数字包含冷启动开销，可重启 App 多看几次。
3. 打开 3–5 条真实 Apple Watch ECG（30 秒、约 512 Hz、约 15,360 点），逐条记录分析耗时。
   每次进入详情页都会重新读取并分析，可以反复进出取中位数。
4. 同时粗略感受“点进详情 → 波形出现”的总等待时间（主要是 HealthKit 读取）。

需要更细的剖析时，用 Instruments 的 Time Profiler 录一次“打开真实记录”的过程。

参考量级：算法主要是两次双向 biquad 滤波 + 每 30 秒块若干次排序，复杂度约 O(n log n)；
15k 点在现代 iPhone 的 Release 构建下预期为毫秒级。若超过 ~50 ms，请把数字发给我。

## 5. 真机功能验收

使用 Apple 健康中已有 Apple Watch 心电记录的 iPhone：

1. 首次安装先出现研究用途声明。
2. 申请权限时，健康权限页只出现心电**读取**，没有写入项。
3. 拒绝/不授权时，界面显示“没有可访问的心电”，不断言“已拒绝”。
4. 授权后列表加载正常；打开一条记录，核对开始时间、时长、采样率、测量数、平均心率、
   Apple 分类、症状与“健康”App 一致。
5. 详情页显示模型 R 峰（橙线）、R–R 间期与疑似早搏候选（红线），或给出具体的拒判原因。
6. 快速切换记录，旧记录结果不会覆盖当前页面。
7. 分享原始 CSV / metadata JSON / analysis JSON：CSV 行数、顺序、时间戳与 HealthKit 测量一致；
   JSON 的 `dataSource` 为 `healthKit`；文件名和内容中没有 HealthKit UUID。
8. 设置页“版本”显示 `0.5.0 (6)`。
9. 抽查签名产物包含 `com.apple.developer.healthkit`，且没有网络上传行为。

内置合成示例只用于教程和测速，不能替代任何真机 HealthKit 验收项。

## 6. 记录方式

记录设备型号/系统版本、Xcode/Swift 版本、提交号、测试通过数、分析耗时（中位数）和脱敏错误码。
不要把心电波形、HealthKit 标识、精确采集时间、Apple 账号或设备标识写进仓库。
