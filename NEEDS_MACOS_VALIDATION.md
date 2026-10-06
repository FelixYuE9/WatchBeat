# Mac 打包与测试清单 — v0.5.0 (6) MVP

本版在 Windows 上整理完成：Python 工具与工程配置测试 48/48 通过，App 算法的 NumPy 镜像已在
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
bash Tools/run-core-tests.sh --parallel   # ECGCore：应为 15 项全部通过
bash Tools/run-app-tests.sh --parallel    # iOS 包：WatchBeatAppTests 全部通过
```

预期 ECGCore 15 项 = ECGSignalInspectorTests 5 项 + PublicContractTests 10 项：结果词汇、默认配置/版本 `1.0.1-rr-research`、输入契约、早搏检出与节律摘要、规则心律
0 候选、缺测拒判、不规则采样拒判、直流偏移不改变检测结果、**描述性 R–R/QRS 峰谷值（新增）**、
**QRS 峰谷测量缺测与边界（新增）**。
iOS 包覆盖内置示例的 35 个 R 峰 / 2 个疑似早搏候选，并新增列表摘要缓存、列表/详情请求
互不干扰及滚动秒数刻度测试；本轮新增示例描述性数值、marker 候选标记、最近采样点/局部峰谷查找、
测量读数（B − A 与心动周期换算）和 mV 刻度测试。

**本轮未在 Mac 上编译过的新代码（请重点看编译报错）：** `ECGWaveformView.swift`（重写）、
新文件 `ECGCaliperView.swift` 与 `ECGCore/.../Signal/ECGQRSAmplitude.swift`（均已写入
`project.pbxproj`）、`SettingsView` 研究调试开关、`ECGAnalysisResultView` 可点击候选。

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
2. 主屏幕与 App 切换器显示新的 WatchBeat 图标，Xcode 不报告 AppIcon 尺寸或透明通道错误。
3. 申请权限时，健康权限页只出现心电**读取**，没有写入项。
4. 拒绝/不授权时，界面显示“没有可访问的心电”，不断言“已拒绝”。
5. 授权后列表加载正常；数据卡与背景有清晰对比，逐条显示筛查进度，并最终显示候选数、
   未标记候选或无法分析；有候选的行使用**黄色**旗标与描边（不再使用红色）。
6. 打开一条记录，核对开始时间、时长、采样率、测量数、平均心率、Apple 分类、症状与
   “健康”App 一致。
7. 详情页默认**不**显示模型 R 峰竖线和候选竖线；上方 R–R 间期正常显示，候选处有黄色底色、
   `#序号 精确秒数`，其前方偏短的 R–R 数字为黄色胶囊；或给出具体的拒判原因。横向滚动时下方秒数
   坐标轴同步移动，左侧 mV 刻度保持固定。设置 › 研究调试 打开两个开关后，橙色 R 峰线与黄色候选
   粗线出现，关闭后消失。
   - 候选导航条的 ‹ › 能逐个把候选滚动到屏幕中央并加深底色；在“本机研究分析”卡片里点某个候选
     的“定位”，页面回到波形并跳到该候选；定位后拖动时间缩放滑块，候选仍保持在中央。
   - 电压缩放 1×–4×：图表变高、R 峰之间的幅度差被放大，mV 刻度同步变密；“复位缩放”恢复 1×。
   - “峰谷电压差”开关：每个 R 峰旁出现青色竖括号和数值（mV），与分析 JSON 中
     `qrsPeakToTroughMillivolts` 一致；示例 ECG 正常搏约 1.27 mV，PVC 样搏约 1.72 mV。
   - “测量”开关：依次点击波形放置 A、B；拖动圆点时页面不滚动、其他位置仍可左右滑动；
     ‹ › 逐采样点移动、“吸附峰/谷”跳到 ±40 ms 内极值；读数为 B − A 的 Δt（ms）与 ΔV（mV），
     Δt 在 250–3000 ms 时显示换算次/分；关闭“贴合波形”后可把点放在任意高度。
   - 深色模式下黄色文字（候选秒数、旗标）清晰可读。
8. “心率与节律摘要”显示检测中位心率、中位 R–R、R–R 四分位距、可信间期数和候选占比；
   它与 Apple 元数据平均心率接近但不必完全相同，界面明确声明它不是临床 HRV。
   “更多节律与波形描述”显示最短/最长 R–R、逐搏心率范围、>2 秒间期数、相邻候选对数与
   QRS 峰谷电压差（中位、范围），并附非诊断说明。
9. 快速切换记录，旧记录结果不会覆盖当前页面；列表后台筛查也不会让已打开的详情失效。
10. 分享原始 CSV / metadata JSON / analysis JSON：CSV 行数、顺序、时间戳与 HealthKit 测量一致；
    JSON 的 `dataSource` 为 `healthKit`，analysis 含 `watchbeat.rr-summary.v1`；文件名和内容中没有
    HealthKit UUID。
11. 设置页“版本”显示 `0.5.0 (6)`。
12. 抽查签名产物包含 `com.apple.developer.healthkit`，且没有网络上传行为。

内置合成示例只用于教程和测速，不能替代任何真机 HealthKit 验收项。

## 6. 记录方式

记录设备型号/系统版本、Xcode/Swift 版本、提交号、测试通过数、分析耗时（中位数）和脱敏错误码。
不要把心电波形、HealthKit 标识、精确采集时间、Apple 账号或设备标识写进仓库。
