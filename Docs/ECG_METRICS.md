# 可从单导联 ECG 扩展的量化信息

更新日期：2026-09-29。本文只规划研究型、可审计的量化输出，不把单导联 Apple Watch ECG
扩张成十二导联诊断工具。

## 这次已经接入

`ECGAnalysisReport` schema v1 新增可选的 `rhythmMetrics`。它只复用模型已经检测出的 R 峰，
不会改变 R 峰位置、早搏门槛、候选标签或现有准确率：

- `recordingDurationSeconds`：实际输入时间轴的跨度；
- `plausibleRRIntervalCount`：落在 300–2,000 ms 研究范围内的 R–R 间期数；
- `medianRRMilliseconds`：上述间期的中位数；
- `medianDetectedHeartRateBPM`：`60,000 / median RR (ms)`；
- `rrInterquartileRangeMilliseconds`：R–R 的 25%–75% 四分位距，使用线性插值样本分位数；
- `prematureCandidateFraction`：疑似早搏候选数 / 已分类心搏数。

UI 会显示中位心率、中位 R–R、R–R 四分位距、可用间期数和候选占比。这里的 R–R
四分位距只是当前 30 秒记录的稳健离散程度，**不是 HRV、房颤诊断或风险评分**。所有字段带
`metricsVersion = watchbeat.rr-summary.v1`，便于后续审计。

## 常见信息与引入判断

| 信息 | 单导联 30 秒可行性 | 自动化价值 | 当前判断 |
|---|---|---|---|
| 心率、R–R 分布、候选占比 | 高；已有可靠 R 峰时可直接量化 | 人工逐搏计数和汇总费时 | **已接入描述性指标** |
| 信号质量：平线、削顶、基线漂移、高频噪声、可读时长 | 高，但阈值必须按设备验证 | 人工容易漏掉局部坏段；错误质量会污染全部下游结果 | **下一优先级，先于新诊断标签** |
| 早搏序列：二联律/三联律、成对候选、最长 R–R、代偿间歇证据 | 中高 | 逐搏查找与计数很费时 | 待质量门控和早搏召回率改善后加入 |
| QRS 宽度、模板相关性、形态聚类 | 中；单导联只能给该导联的局部测量 | 人工对齐和跨搏比较困难 | 用作 PAC/PVC 的融合证据，不能单项硬判 |
| 不规则节律/房颤候选 | 中；单导联可以筛查，但早搏与噪声都会制造不规则 | 长串 R–R 的统计判断适合机器 | 需独立标注集、质量门控和与早搏的鉴别；不复用 Apple 分类作模型输入 |
| P 波、PR 间期 | 低到中；腕表单导联常有低振幅 P 波 | 人工在噪声中定位困难 | 只做实验特征；“未可靠检测”不能解释成“没有 P 波” |
| QT/QTc、T 波终点 | 低到中；终点方法、心率校正、导联差异都会改变数值 | 自动逐搏测量方便但误差后果较大 | 暂不面向用户输出；需独立标注、人工复核和算法专属参考范围 |
| ST-T 改变、缺血/心梗 | 低；单导联不能替代十二导联 | 自动化看似方便但极易误导 | **不引入** |

## 建议实现顺序

1. **客观信号质量门控**：在不改变原始数据的前提下，输出 `good / usableWithCaution / poor`，
   `poor` 停止细分类。阈值先在带专家质量标签的单导联数据上冻结，再做 Apple Watch 真机域验证。
2. **节律序列摘要**：候选占比之后增加二联律、三联律、成对候选、最长可信 R–R 和短-长序列；
   只描述本次记录，不推断长期负荷。
3. **独立 morphology path**：0.5–40 Hz 形态通路、正常搏模板、QRS 边界置信度、宽度比、相关系数、
   NRMSE 与代偿间歇证据，冲突时保持 `prematureUncertain`。
4. **不规则节律研究**：在噪声/早搏排除后研究 R–R 不规则性与可检测 P 波证据；达到独立验证门槛前
   不输出“房颤”。

## 为什么没有把更多项目一起打开

- Apple 明确说明 Apple Watch 生成的是类似 I 导联的单导联 ECG，主要提供心率与心律信息，不能用来
  识别心脏病发作等部分疾病；一次记录为 30 秒。
- AHA/ACCF/HRS 的标准化声明把 P 波时限、PR、QRS、QT 列为常规 ECG 间期，但推荐从时间对齐的
  多导联取得全局起止点；QT 的算法差异和 T 波终点尤其需要考虑，自动 QT 延长结果应人工复核。
- ESC/NASPE 的经典 HRV 标准建议短时 HRV 使用 5 分钟稳态记录。30 秒 R–R 四分位距可以描述
  当前片段，却不应换名成 SDNN/RMSSD 或临床 HRV。
- 单导联远程 ECG 的 QRS 检测在高质量数据上可以很好，但低质量数据性能明显下降，因此质量门控
  应当早于更积极的心律分类。

## 资料来源

- Apple Support, [Take an ECG with the ECG app on Apple Watch](https://support.apple.com/en-nz/120278)
  （页面更新于 2025-09-23；本项目查阅于 2026-09-29）。
- Apple, [ECG app Instructions for Use, version 2](https://www.apple.com/legal/ifu/ecg/2-0/ecg-ifu-2-0-en_GB.pdf).
- Kligfield et al., AHA/ACCF/HRS,
  [Recommendations for the Standardization and Interpretation of the Electrocardiogram, Part I](https://www.ahajournals.org/doi/10.1161/CIRCULATIONAHA.106.180200),
  *Circulation* 2007.
- Rautaharju et al., AHA/ACCF/HRS,
  [Recommendations for the Standardization and Interpretation of the Electrocardiogram, Part IV](https://www.ahajournals.org/doi/10.1161/CIRCULATIONAHA.108.191096),
  *Circulation* 2009.
- ESC/NASPE Task Force,
  [Heart rate variability: standards of measurement, physiological interpretation and clinical use](https://pubmed.ncbi.nlm.nih.gov/8598068/),
  *Circulation* 1996.
- Charlton et al.,
  [QRS detection in single-lead, telehealth electrocardiogram signals: benchmarking open-source algorithms](https://pmc.ncbi.nlm.nih.gov/articles/PMC7617317/),
  *Physiological Measurement* 2023.

