# Dataset registry

任何数据下载前都要再次核对版本、许可和使用范围。完整数据集、个人 ECG 和受限数据均不
提交到 Git。本文件记录计划，不代表已经下载或使用。

| 数据集 | 计划用途 | 许可/限制 | 当前状态 |
|---|---|---|---|
| MIT-BIH Arrhythmia Database v1.0.0 | 第一层 R 峰与 beat 回归；切成 30 s 窗口 | ODC Attribution 1.0；需引用来源；48 个约 30 分钟、360 Hz、双通道记录 | 48 条记录已在本地逐文件校验；数据与生成 manifest 均被 Git 忽略 |
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

- `Tools/Validation/download_mitdb.py` 固定到 v1.0.0 与官方 48 条 `RECORDS`，并用官方
  `SHA256SUMS.txt` 逐文件验证。本轮已下载并复核 145 个必需文件，约 104.3 MB；这些文件
  只存在于本地忽略目录，不进入 Git。
- 下载位置固定为 `Tools/Validation/data/`，由 Git 忽略。
- 自动生成的报告放 `Tools/Validation/output/`，默认不提交大体积结果。
- `mitdb_split_v1.json` 与 `mitdb_manifest_v1.lock.json` 是可提交的小型控制文件；前者冻结
  subject-level split，后者固定生成 manifest 的 SHA-256、字节数、统计量与边界案例。
- 可提交的小型公开派生 fixture 必须记录原始 record、channel、sample range、变换、许可
  和归属，并确认许可允许分发。
- `PrivateValidationData/` 内除安全说明外全部被 Git 忽略。

## 当前评测契约

`Tools/Validation/evaluate_r_peaks.py` 已固定 30 秒窗口、development/validation/held-out-test
分组和 150 ms 一对一匹配容差，并会拒绝 subject/record 跨 split 泄漏。150 ms 来自
PhysioNet WFDB `bxb` 的官方默认匹配窗口。

冻结 manifest 含 48 records / 47 subjects / 2,880 个完整窗口 / 109,150 个参考 QRS。记录
201 与 202 按官方说明归为同一 subject；development / validation / held-out-test 分别为
30 / 9 / 9 records（29 / 9 / 9 subjects）。102、104 没有 MLII，固定使用 channel 0 的 V5；
207 有两个合法的零参考 QRS 窗口并被保留。manifest SHA-256 为
`55143a8301860ec3744fdf7e8d9cef31c0d6ed3ea82b8f73a42d2452b416f382`。

评测器仍必须与官方 `bxb` 交叉核对，然后才能用于 detector 选择；冻结公开数据也不能
替代 Apple Watch 域独立验证。

## 尚待确认

Icentia11k、WatchMyHeart 和 HOME 的精确版本 URL、许可文本和 checksum 必须由 Milestone 3
的独立 dataset ADR 冻结。本轮不根据二手摘要下载、调参或再分发任何数据。
