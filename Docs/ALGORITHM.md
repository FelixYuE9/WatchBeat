# Algorithm specification

## 当前实现边界

算法版本为 `0.0.1-m0`。当前仅实现无损结构检查和公共协议；没有滤波器、R 峰 detector、
模板、QRS 特征或 PAC/PVC 分类器。`ECGAlgorithmConfig.researchDefaults` 中的数值只是待
验证的研究假设，不能解释为医学阈值，也没有形成生产默认值。

离线 MIT-BIH development 初筛已覆盖九种 PeakSwift R 峰算法，并用三种算法试验 2/3、
3/3 峰位投票。这不改变上述 App 实现边界。融合候选不要求最终只能选一个算法；其票数与
对齐容差必须按配置版本记录，经过独立 validation 和 Apple Watch 域验证后才可能进入 App。

## 输入契约

```swift
public struct ECGSignal {
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

完整 `ECGQualityReport` 尚未实现。结构检查通过不等于信号质量良好。

## 计划中的三条信号路径

1. **Raw path**：仅做单位归一与完整性记录；用于导出和 overlay。
2. **Detection path**：供 detector 使用，候选带通约 5–20 Hz，可包含导数、平方、积分
   和自适应阈值。不得用此路径测 QRS 宽度或形态。
3. **Morphology path**：候选 0.5–40 Hz，轻度基线去除，保留 QRS 形态。30 秒离线分析
   优先零相位；若改为 causal filter，必须显式记录并补偿群延迟。

频带、阶数、相位方式和边缘策略在实现后都必须进入 config 和版本记录。当前频带/阶数
仍未通过 128/250/360/500/512 Hz 测试。

## 计划中的质量门控

在任何 PAC/PVC 规则之前评估时间戳、gap、缺测、flatline、clipping、瞬变、baseline
drift、高频/导数能量、连续可用时长、峰稳定性和 impossible RR。输出：

- `good`
- `usableWithCaution`
- `poor`

`poor` 必须停止细分类并返回 `notAnalyzed` 或 beat 级 `noiseInvalid`，绝不能变成 Normal。
`usableWithCaution` 必须降低 confidence 并保留原因。

## 计划中的检测与特征顺序

```text
quality gate
  → R-peak candidates + refractory/T-wave protection
  → morphology-path local refinement
  → RR_before / RR_after + robust local normal RR
  → premature candidate gate
  → independent normal-template candidates
  → medoid/cluster screening + aligned median template
  → QRS width ratio + correlation + NRMSE + compensation ratio
  → PAC/PVC evidence scores or explicit refusal
```

`localNormalRR` 使用最近 5–8 个高质量、非异常候选 NN interval 的稳健中位数；开头用
记录级 trimmed median 作为 seed。早搏、漏检、重复峰和二联律不得污染 baseline。

## 分类安全规则

- “明显提前”是进入 PAC/PVC 证据融合的必要门槛。
- 模板少于候选默认 5 个、模板不稳定或多 morphology cluster 势均力敌时不得细分类。
- QRS 宽度、形态和 pause 只能作为融合证据；任何单项都不能硬判 PVC/PAC。
- width 与 morphology 冲突、score 太低/太接近、节律不可靠、QRS 边界不可靠或连续
  异位上下文不足时输出 `prematureUncertain` 或 `notAnalyzed`。
- P 波是未来实验特征；“没有可靠检测到”不等于“没有 P 波”。

## 版本与配置

- Algorithm semantic version：`0.0.1-m0`
- Config schema：`0.1.0`
- Detector：`unselected-pending-benchmark`

任何会改变结果的参数或逻辑都需要版本变更、可重现测试和验证记录。稳定 config hash 的
规范将在实际分析管线出现前定义；在此之前不得把对象默认编码的 hash 当作跨版本标识。
投票门槛与峰位对齐容差是离线融合参数；`prematurityThreshold`、
`morphologyCorrelationThreshold` 等是尚未启用的后续分类研究参数；PeakSwift 算法内部
阈值是否可配置还须单独审计。未来高级设置只能暴露真正接入、边界明确且验证过的参数，
并提供恢复基准配置和随结果记录配置版本的能力。
