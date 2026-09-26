# Dataset registry

任何数据下载前都要再次核对版本、许可和使用范围。完整数据集、个人 ECG 和受限数据均不
提交到 Git。本文件记录计划，不代表已经下载或使用。

| 数据集 | 计划用途 | 许可/限制 | 当前状态 |
|---|---|---|---|
| MIT-BIH Arrhythmia Database v1.0.0 | 第一层 R 峰与 beat 回归；切成 30 s 窗口 | ODC Attribution 1.0；需引用来源；48 个约 30 分钟、360 Hz、双通道记录 | 未下载 |
| Icentia11k | 后续大规模单导联 N/S/V/Q 评测 | 体量大；使用前重新核对访问和再分发条款 | Deferred |
| WatchMyHeart | Apple Watch 波形兼容性、质量和假阳性观察 | 不作为充分的逐 beat PAC/PVC 真值；使用前复核条款 | Deferred |
| HOME | 仅按其 evaluation-only 条款考虑 | 不得训练、微调、域适配或阈值校准；不提交波形 | 不用于调参 |
| 用户自有专家标注 Apple Watch ECG | 最终 Apple Watch 域独立验证 | 必须有使用权、去标识化、版本化标注协议和独立测试划分 | 私有且未提供 |

## MIT-BIH 固定来源

- PhysioNet version 1.0.0：<https://physionet.org/content/mitdb/1.0.0/>
- DOI：<https://doi.org/10.13026/C2F305>
- 数据文件许可：Open Data Commons Attribution License v1.0。

数据包含 48 个双通道动态 ECG 片段，来源域、导联、采样率、设备与 Apple Watch
Lead-I-like ECG 明显不同。即使 detector 在该数据集表现良好，也不能直接推出 Apple
Watch 上的 PAC/PVC 准确率。

## 下载与派生物政策

- Milestone 3 才实现固定版本下载脚本、校验和与 fixture manifest。
- 下载位置固定为 `Tools/Validation/data/`，由 Git 忽略。
- 自动生成的报告放 `Tools/Validation/output/`，默认不提交大体积结果。
- 可提交的小型公开派生 fixture 必须记录原始 record、channel、sample range、变换、许可
  和归属，并确认许可允许分发。
- `PrivateValidationData/` 内除安全说明外全部被 Git 忽略。

## 尚待确认

Icentia11k、WatchMyHeart 和 HOME 的精确版本 URL、许可文本和 checksum 必须由 Milestone 3
的独立 dataset ADR 冻结。本轮不根据二手摘要下载、调参或再分发任何数据。
