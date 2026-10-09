# Architecture

## 设计目标

系统优先保证可审计、可验证、隐私和拒判能力，而不是最大化标签数量。UI 不得重新实现
算法规则，算法不得依赖 HealthKit、SwiftUI、网络或 Apple 原始 ECG classification。

## 边界与数据流

```text
┌──────────────────────── iOS-only boundary ────────────────────────┐
│ HealthKit read-only repository                                    │
│   metadata list → list-screen/detail voltage reads → mapper       │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ ECGSignal / watchbeat.ecg.signal.v1
┌──────────────────────────────▼─────────────────────────────────────┐
│ ECGCore — platform-neutral, deterministic where practical         │
│ integrity → 5–25 Hz detection path → refined R peaks → local RR   │
│                    → conservative premature-candidate rule        │
│              (future: quality/morphology/PAC-PVC evidence paths)  │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ ECGAnalysisReport v1
┌──────────────────────────────▼─────────────────────────────────────┐
│ SwiftUI presentation / local export                               │
│ list badges, waveform/time axis, result card, CSV + analysis JSON  │
└────────────────────────────────────────────────────────────────────┘
```

## 强制不变量

1. HealthKit 只读。授权时 `toShare` 为空。
2. HealthKit measurement 顺序、时间戳和缺测位置在映射时保持不变。
3. 电压在边界统一为 mV；采样率优先使用记录值，推断值必须显式标记。
4. 完整性或质量门控失败时不进入 PAC/PVC 细分类，也不把失败计为 Normal。
5. detection signal 与 morphology signal 是不同派生数据；原始数据永远保留用于导出。
6. Apple classification 只进入展示/metadata，不进入任何研究算法输入。
7. UI explanation 仅由实际 feature 值和 `ReasonCode` 生成。
8. 每个分析结果带 schema、algorithm、config version、detector identifier 和拒判原因。
9. 不缓存 ECG 波形副本、分析报告或采集日期，无健康数据日志、无网络数据流。本机受保护文件只保存
   用户主动保存的批注，以及按记录 UUID 索引的紧凑筛查摘要（候选数／未标记候选／无法分析）。

## 当前最小闭环的数据契约

App 内唯一输入对象是 `ECGSignal`（format identifier `watchbeat.ecg.signal.v1`）：索引对齐的
`timeSeconds`、Lead-I-like `voltageMillivolts` 和可选 nominal Hz。HealthKit mapper 与内置
合成 factory 都只生成这个对象；`ECGMeasurement` 初始化时一律将它送入同一个
`PrematureBeatAnalyzer`。每个数组位置对应原始 CSV 的一个 `time_s,voltage_mV` 行；空电压
仍占位并触发明确拒判，绝不压缩时间轴。

模型唯一输出是 `ECGAnalysisReport` v1，包含 status/reason、算法与配置版本、采样率、R 峰
原始 sample index、RR 特征和保守分类。波形 marker、结果卡和 analysis JSON 都读取同一份
report，不各自重算算法。Apple classification 只展示，完全不进入 report。

离线 Python 原型仍以 iPhone 原始导出 CSV 为唯一波形输入。
公开 MIT-BIH `.hea/.dat` 只由 `convert_mitdb_to_watchbeat_csv.py` 转到这一契约，
之后与 iPhone 导出走同一个 `prototype_premature_beats.py`。`.atr` 参考标注只进入
`evaluate_prototype_premature_beats.py`，不参与转换、峰值检测或 RR 判定。Swift 实现已接入
iOS 详情页；NumPy/SciPy 仍仅用于离线交叉检查，不属于 App runtime。

## 当前仓库布局

```text
ECGCore/                      # 已建立；平台无关 Swift Package
  Sources/ECGCore/
    Classification/          # 版本化 report 契约 + PrematureBeatAnalyzer 编排
    Config/                  # 版本与集中研究参数
    Models/                  # ECGSignal
    Peaks/                   # dependency-free gradient-energy R 峰实现
    Signal/                  # 无损结构完整性检查
  Tests/ECGCoreTests/        # 确定性测试源码
Docs/                        # 设计、验证、数据、隐私与合规记录
Tools/Validation/            # 离线验证；可选 Python 原型依赖与 App runtime 隔离
PrivateValidationData/       # 内容被 Git 忽略
iOS/                         # Milestone 1 App：SwiftPM 包 + Xcode 工程
  App/                       # @main 入口、scene container、root 路由
  Models/                    # records、measurement、display/export 与合成教学数据
  HealthKit/                 # WatchBeatHealthKit：唯一接触 HealthKit 的模块
  Features/                  # Disclaimer、ECGList、ECGDetail
  Resources/                 # Xcode App target 使用的 Info.plist 与 entitlements
  Tests/                     # Swift Testing 用例与 fakes
  WatchBeat.xcodeproj/       # iPhone-only App、framework、测试 target 与共享 scheme
```

Xcode 工程已由 Xcode 26.6 解析，并曾用真实 iPhoneOS/iPhoneSimulator 26.5 SDK 完成构建。
共享 `WatchBeatApp` scheme 可 Run/Archive，App target 开启自动签名、HealthKit entitlement、
iPhone-only 和 framework embed/sign。选择开发 Team 与唯一 Bundle ID 后可打包并安装到实际
iPhone；当前 revision 的签名产物和真机 HealthKit 行为仍须按
[IPHONE_INSTALL.md](IPHONE_INSTALL.md) 与 [VALIDATION.md](VALIDATION.md) 留证。

## iOS 组件（Milestone 1 已建立源码）

- `ECGHealthKitReading` / `LiveHealthKitECGReader`：可注入的最小授权/查询边界；`toShare` 为空。
- `ECGRepository`：先加载 metadata；用户进入数据页后逐条读取 voltage 生成仅含候选数/拒判的
  列表摘要，原始信号不进入列表缓存；详情仍按需重读完整 voltage。详情请求使用
  generation + 取消保护，列表筛查使用独立通道，二者不会互相判为过期。
- `ECGScreeningCacheStorage`：摘要经 `ECGScreeningCacheFileStorage` 持久化，重新启动后列表一次性
  显示已知结果，只读取新增记录的 voltage。文件绑定算法版本与全部研究参数（任何变化即整体失效），
  每 20 条新结果及每轮筛查结束时写入；全量 metadata 查询后删除已不可访问记录的摘要；文件
  暂不可读时不覆盖。
- `ECGHealthKitMapper`：单位换算和完整性信息，不静默清洗。
- feature modules：Disclaimer、ECG list、ECG detail、可滚动/缩放 Canvas 波形、模型结果卡、
  内置合成教程与 settings（beat detail、research mode 待后续里程碑）。
- `ECGDisplayDownsampler`：只生成绘图 envelope，不修改分析/导出的完整 `ECGSignal`；可选 marker
  从真实时间戳映射到横轴；滚动时间轴使用有上限的 1/2/5 秒刻度，纵轴为固定的 mV 刻度并可独立
  缩放。细节波形下方的全段概览使用独立显示缓存与固定范围，`ECGWaveformViewport` 将真实滚动
  距离映射为可见时间窗口；概览点击/拖动与候选跳转共用任意时间定位锚点。
  疑似早搏候选用黄色底色、`#序号` 精确秒数和高亮的前一 R–R 标出，并可上一个/下一个跳转；
  模型 R 峰竖线与候选竖线属于研究调试标注，默认关闭（设置 › 研究调试）。
- `ECGCaliper`（波形测量工具）：两点 A/B 存于信号单位（秒、mV），点击放置、拖动或逐采样点微调，
  可吸附 ±40 ms 内的波峰/波谷；读数恒为 B − A。只有测量 overlay 观察它，拖动时不重绘主波形。
- `ECGExportEncoder` / `ECGTemporaryExportWriter`：原始 CSV、metadata JSON、analysis JSON、敏感信息确认、系统
  share sheet 与分享结束后的临时目录清理。合成示例在 UI、JSON `dataSource` 和文件名中均有标记。

HealthKit 异步查询必须支持 cooperative cancellation 和请求 identity 检查，防止快速切换
记录时旧结果覆盖新页面。读取权限被拒绝和“数据库无可访问记录”在 HealthKit 中不可可靠
区分，因此 empty state 不能断言用户拒绝权限。

## 跨记录概览、筛选与批注

`ECGRecordInsights` 是 SwiftUI/HealthKit 无关的描述性汇总：对可访问记录按日分组，跨度超过
90 天时概览按月分组。趋势图每页最多显示 14 天或 12 个月，超出时可左右滑动（Swift Charts
原生滚动，纵轴固定），默认停在最近一页，切换日期范围后回到最近一页。心率均值对有有效 Apple 平均心率的记录等权平均，不以时长加权。
候选总数只求和成功分析的记录；成功零候选、无法分析、待分析和读取失败分别统计。
示例不进入真实记录集合。筛查仍只缓存紧凑结果，详情成功读取后同步更新列表和概览。

`ECGRecordFilter` 将日期、研究分析结果、标签、批注搜索组合为 AND；标签内部为 OR。
自定义结束日期包含整天，使用当前 Calendar 的次日零点作为排他上界，覆盖夏令时间。
最近 7/30 天包含今天；预设症状的中英文名称都可搜索。HealthKit metadata 查询默认
`limit: nil`，返回全部可访问记录，不再隐含截断到 200 条，电压仍按需逐条读取。

`ECGAnnotation` 与算法和 Apple 症状状态独立：预设感受多选，“没有不适”与其他预设症状
互斥，自定义标签清理空白并忽略大小写／重音去重。`ECGAnnotationStore` 在保存成功后才
发布修改；读取失败时禁止覆盖原文件。文件包含 schema v1、关联 UUID 和用户批注，使用
iOS complete file protection，并在写入前排除目录备份。详情提供草稿编辑与保存／取消，
设置提供清除全部批注。隐私边界见 [PRIVACY.md](PRIVACY.md)。

功能参考（2026-10-07 查阅官方页面）：

- [Kardia Insights](https://kardia.com/insights)：按月、时段查看 ECG 趋势，并汇总记录标签；
  为本项目的跨记录概览和标签分布提供参考。
- [Apple ECG](https://support.apple.com/en-ie/120278)：保存波形、分类和用户记录的症状，并支持 PDF 分享；
  为本项目的“记录期间感觉如何”入口提供参考。
- [Wellue 报告说明](https://getwellue.com/blogs/select-product-category/what-does-ai-ecg-report-include)：
  展示报告概览、心率摘要、事件计数和按小时统计。其持续记录场景与本项目的短时 ECG 不同；
  本轮只借鉴汇总层级，没有新增 PAC/PVC 分型或全天负荷指标。

## 依赖倒置

App 只依赖 `ECGAnalyzing` 协议（`analyze(ECGSignal) -> ECGAnalysisReport`）；替换 detector 或
加入 PAC/PVC 分型时实现同一协议即可。MVP 清理删除了尚未使用的 `RPeakDetecting`、
`BeatClassifying` 与质量模型占位类型，以及离线 PeakSwift benchmark（见 Git 历史 `c3c3e0e`）。详见 [ADR-0001](ADR/0001-r-peak-dependency-strategy.md) 与
[ADR-0002](ADR/0002-peakswift-benchmark-boundary.md)。

## 状态

本文同时标出已实现垂直闭环和后续目标。以 README 的“当前已实现/仍需验证”和
[VALIDATION.md](VALIDATION.md) 的实际命令记录为准。
