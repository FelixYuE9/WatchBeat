# Algorithm specification

## 当前实现边界

算法版本为 `1.0.1-rr-research`，配置版本为 `1.0.0`。当前已经实现一个完整、无第三方
runtime 的最小垂直闭环：结构拒判 → 5–25 Hz 零相位二阶高通/低通 → 梯度平方与 120 ms
移动积分 → 分块自适应阈值 → 原波形局部 R 峰细化 → 最近 8 个 RR 的中位数基线 →
`prematureUncertain`。它不会使用 Apple classification，也不会凭 RR 猜 PAC/PVC。

在不改变上述分类逻辑的前提下，分析报告还会从 300–2,000 ms 的可信检测 R–R 间期生成
`watchbeat.rr-summary.v1` 描述性摘要：记录时长、可信间期数、中位 R–R、检测中位心率、
R–R 四分位距和候选占比。R–R 四分位距只描述这段短记录，不命名为 HRV，也不参与候选判定。

这是一条可运行的研究默认值，不是医学阈值或经过 Apple Watch 域验证的诊断模型。
`normal` 在当前 report 中仅表示“有足够 RR 上下文且未通过提前门槛”，不能解释为整段
心电正常。缺测、非有限值、时间轴不合法、采样不受支持或峰数不足会返回 `notAnalyzed`。

1.0.1 相对 1.0.0 的改动：零相位滤波两端各加 1 秒奇对称延拓（消除直流偏移/边缘阶跃造成的
首尾假峰）、积分窗改为居中（与 Python 原型一致，不再滞后半窗）、不足半块的尾部并入上一块、
峰位替换时保持相邻峰间距。App 算法的 NumPy 镜像在 MIT-BIH development 1,800 个独立 30 秒
窗口上：R 峰 Se 0.9836 / +P 0.9969；早搏候选 Se 0.449 / +P 0.667（见
`Tools/Validation/README.md`）。早搏规则是主要短板；公开数据指标不等于 Apple Watch 准确率。
未来替换 detector 时必须保持下述输入/输出契约并单独验证。

## 输入契约

```swift
public struct ECGSignal {
    public static let formatIdentifier = "watchbeat.ecg.signal.v1"
    public let timeSeconds: [Double]
    public let voltageMillivolts: [Double?]
    public let nominalSamplingRateHz: Double?
}
```

输入必须保留原始顺序和缺测位置。`ECGSignalInspector`：

- 数组长度不同则返回 typed error；
- 报告缺测、非有限电压、非有限/重复/倒退时间戳的原始 index；
- 仅用正且有限的相邻时间差中位数推断采样率；
- 用 `median(abs(dt - median(dt))) / median(dt)` 报告相对 MAD；
- 不排序、不删除、不插值、不改变电压或时间轴。

模型还要求：时长至少 8 秒；推算采样率 60–1,000 Hz；相邻采样严格递增；相对 MAD 不超过
0.05；最大间隔不超过中位间隔的 1.5 倍；所有电压存在且有限。完整的 flatline、clipping、
运动伪影质量报告尚未实现，因此结构检查通过不等于信号质量良好。

HealthKit 与内置示例都直接构造同一 `ECGSignal`；CSV 只是这个对象的无损导出/离线 adapter，
不是 App 内第二套模型输入。

## 输出契约

`ECGAnalysisReport` schema v1 固定包含：

- `algorithmVersion`、`configVersion`、`detectorIdentifier`、`researchOnly`；
- `inputFormat = watchbeat.ecg.signal.v1`；
- `status = analyzed | notAnalyzed` 及机器可读 `reason`；
- 推算采样率和 `rPeakCount/classifiedBeatCount/prematureCandidateCount`；
- 可选 `rhythmMetrics`：版本化的记录时长、可信 R–R 数、中位 R–R/心率、R–R 四分位距和
  候选占比；拒判报告为 `nil`；
- 每个峰在原始信号中的 `sampleIndex/timeSeconds`、RR、局部 RR、提前比值、保守标签与 reason code。

详情页 marker、摘要和用户主动分享的 analysis JSON 都来自同一个 report，不重复计算。

## 信号路径

1. **Raw path**：仅做单位归一与完整性记录；用于导出和 overlay。
2. **Detection path（已实现）**：5–25 Hz、导数、平方、120 ms 积分、30 秒分块阈值和
   250 ms refractory；在滤波信号 ±100 ms 内细化。不得用此路径测 QRS 宽度或形态。
3. **Morphology path（未实现）**：候选 0.5–40 Hz，轻度基线去除，保留 QRS 形态。30 秒离线分析
   优先零相位；若改为 causal filter，必须显式记录并补偿群延迟。

频带、阶数、相位方式和细化半径已进入 config/version。当前源码测试覆盖 250 Hz，内置
示例为 500 Hz，公开原型记录为 360 Hz；128/512 Hz 与 Apple Watch 真机仍需验证。

## 计划中的质量门控

在任何 PAC/PVC 规则之前评估时间戳、gap、缺测、flatline、clipping、瞬变、baseline
drift、高频/导数能量、连续可用时长、峰稳定性和 impossible RR。输出：

- `good`
- `usableWithCaution`
- `poor`

`poor` 必须停止细分类并返回 `notAnalyzed` 或 beat 级 `noiseInvalid`，绝不能变成 Normal。
`usableWithCaution` 必须降低 confidence 并保留原因。

## 当前与后续检测顺序

```text
structural gate（已实现）
  → R-peak candidates + refractory/T-wave protection
  → detection-path local refinement
  → RR_before + prior 4–8 valid RR median
  → premature candidate gate（RR < 0.80 × local RR，且 RR ≥ 300 ms）
  → prematureUncertain / normal-research-label / notAnalyzed
  ───── 以下未实现 ─────
  → objective quality gate + morphology-path local refinement
  → independent normal-template candidates
  → medoid/cluster screening + aligned median template
  → QRS width ratio + correlation + NRMSE + compensation ratio
  → PAC/PVC evidence scores or explicit refusal
```

当前 `localRR` 使用当前 beat 之前最近最多 8 个、位于 300–2,000 ms 的 RR；至少需要 4 个。
它与原 Python vertical slice 一致，尚未排除所有异常 RR 对 baseline 的污染，属于下一轮
质量/节律稳健性工作。

## 分类安全规则

- “明显提前”是进入 PAC/PVC 证据融合的必要门槛。
- 模板少于候选默认 5 个、模板不稳定或多 morphology cluster 势均力敌时不得细分类。
- QRS 宽度、形态和 pause 只能作为融合证据；任何单项都不能硬判 PVC/PAC。
- width 与 morphology 冲突、score 太低/太接近、节律不可靠、QRS 边界不可靠或连续
  异位上下文不足时输出 `prematureUncertain` 或 `notAnalyzed`。
- P 波是未来实验特征；“没有可靠检测到”不等于“没有 P 波”。

## 版本与配置

- Algorithm semantic version：`1.0.1-rr-research`
- Config schema：`1.0.0`
- Detector：`watchbeat-gradient-energy-rr-v1`

任何会改变结果的参数或逻辑都需要版本变更、可重现测试和验证记录。稳定 config hash 的
规范仍需在可配置算法替换前冻结；不得把对象默认编码的 hash 当作跨版本标识。
`ECGAlgorithmConfig` 只保留当前实际生效的参数；形态学/模板等后续分类参数在真正实现时
再随新版本加入。未来高级设置只能暴露真正接入、边界明确且验证过的参数，
并提供恢复基准配置和随结果记录配置版本的能力。
