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
9. 默认无 ECG 副本缓存、无健康数据日志、无网络数据流。

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
  进程内列表摘要，原始信号不进入列表缓存；详情仍按需重读完整 voltage。详情请求使用
  generation + 取消保护，列表筛查使用独立通道，二者不会互相判为过期。
- `ECGHealthKitMapper`：单位换算和完整性信息，不静默清洗。
- feature modules：Disclaimer、ECG list、ECG detail、可滚动/缩放 Canvas 波形、模型结果卡、
  内置合成教程与 settings（beat detail、research mode 待后续里程碑）。
- `ECGDisplayDownsampler`：只生成绘图 envelope，不修改分析/导出的完整 `ECGSignal`；可选 marker
  从真实时间戳映射到横轴；滚动时间轴使用有上限的 1/2/5 秒刻度，候选红线显示精确秒数。
- `ECGExportEncoder` / `ECGTemporaryExportWriter`：原始 CSV、metadata JSON、analysis JSON、敏感信息确认、系统
  share sheet 与分享结束后的临时目录清理。合成示例在 UI、JSON `dataSource` 和文件名中均有标记。

HealthKit 异步查询必须支持 cooperative cancellation 和请求 identity 检查，防止快速切换
记录时旧结果覆盖新页面。读取权限被拒绝和“数据库无可访问记录”在 HealthKit 中不可可靠
区分，因此 empty state 不能断言用户拒绝权限。

## 依赖倒置

App 只依赖 `ECGAnalyzing` 协议（`analyze(ECGSignal) -> ECGAnalysisReport`）；替换 detector 或
加入 PAC/PVC 分型时实现同一协议即可。MVP 清理删除了尚未使用的 `RPeakDetecting`、
`BeatClassifying` 与质量模型占位类型，以及离线 PeakSwift benchmark（见 Git 历史 `c3c3e0e`）。详见 [ADR-0001](ADR/0001-r-peak-dependency-strategy.md) 与
[ADR-0002](ADR/0002-peakswift-benchmark-boundary.md)。

## 状态

本文同时标出已实现垂直闭环和后续目标。以 README 的“当前已实现/仍需验证”和
[VALIDATION.md](VALIDATION.md) 的实际命令记录为准。
