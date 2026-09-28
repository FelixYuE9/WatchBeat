# Architecture

## 设计目标

系统优先保证可审计、可验证、隐私和拒判能力，而不是最大化标签数量。UI 不得重新实现
算法规则，算法不得依赖 HealthKit、SwiftUI、网络或 Apple 原始 ECG classification。

## 边界与数据流

```text
┌──────────────────────── iOS-only boundary ────────────────────────┐
│ HealthKit read-only repository                                    │
│   metadata list → selected ECG voltage measurements → mapper      │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ ECGSignal (time, mV?, nominal Hz?)
┌──────────────────────────────▼─────────────────────────────────────┐
│ ECGCore — platform-neutral, deterministic where practical         │
│ integrity → quality → detection path → refined R peaks → RR       │
│                    ↘ morphology path → template/QRS/features      │
│                               evidence classifier → reason codes  │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ versioned results and feature values
┌──────────────────────────────▼─────────────────────────────────────┐
│ SwiftUI presentation / local export                               │
│ waveform, timestamp markers, synthetic tutorial, CSV/JSON sharing │
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
8. 每个分析结果带 app、algorithm、config schema 和 config snapshot/hash。
9. 默认无 ECG 副本缓存、无健康数据日志、无网络数据流。

## 当前仓库布局

```text
ECGCore/                      # 已建立；平台无关 Swift Package
  Sources/ECGCore/
    Classification/          # 公共分类协议和可解释结果契约
    Config/                  # 版本与集中研究参数
    Models/                  # ECGSignal、质量模型
    Peaks/                   # RPeakDetecting 协议
    Signal/                  # 目前只有结构完整性检查
  Tests/ECGCoreTests/        # 确定性测试源码
Docs/                        # 设计、验证、数据、隐私与合规记录
Tools/Validation/            # 离线验证骨架；无运行时依赖
Tools/PeakSwiftBenchmark/    # 与 App 隔离的第三方 detector 候选预测工具
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

Xcode 工程已由 Xcode 26.6 解析，并曾用真实 iPhoneOS/iPhoneSimulator 26.5 SDK 完成无签名
target 构建。共享 `WatchBeatApp` scheme 已纳入版本控制；模拟器运行、签名 entitlement 与真机
HealthKit 行为仍须按 [VALIDATION.md](VALIDATION.md) 实测。

## iOS 组件（Milestone 1 已建立源码）

- `ECGHealthKitReading` / `LiveHealthKitECGReader`：可注入的最小授权/查询边界；`toShare` 为空。
- `ECGRepository`：列表只加载 metadata；详情按需读取 voltage；generation + 取消保护。
- `ECGHealthKitMapper`：单位换算和完整性信息，不静默清洗。
- feature modules：Disclaimer、ECG list、ECG detail、可滚动/缩放 Canvas 波形与内置合成教程
  （beat detail、settings、research mode 待后续里程碑）。
- `ECGDisplayDownsampler`：只生成绘图 envelope，不修改分析/导出的完整 `ECGSignal`；可选 marker
  从真实时间戳映射到横轴。
- `ECGExportEncoder` / `ECGTemporaryExportWriter`：原始 CSV、metadata JSON、敏感信息确认、系统
  share sheet 与分享结束后的临时目录清理。合成示例在 UI、JSON `dataSource` 和文件名中均有标记。

HealthKit 异步查询必须支持 cooperative cancellation 和请求 identity 检查，防止快速切换
记录时旧结果覆盖新页面。读取权限被拒绝和“数据库无可访问记录”在 HealthKit 中不可可靠
区分，因此 empty state 不能断言用户拒绝权限。

## 依赖倒置

`RPeakDetecting` 隔离 PeakSwift 或未来的独立 detector；`BeatClassifying` 隔离规则系统和
未来可选模型。shipping targets 尚未加入候选实现；PeakSwift 只存在于不会被 App 引用的离线
benchmark package。详见 [ADR-0001](ADR/0001-r-peak-dependency-strategy.md) 与
[ADR-0002](ADR/0002-peakswift-benchmark-boundary.md)。

## 状态

本文描述目标架构，不代表目标组件已经实现。以 README 的“当前已实现/尚未实现”和
[VALIDATION.md](VALIDATION.md) 的实际命令记录为准。
