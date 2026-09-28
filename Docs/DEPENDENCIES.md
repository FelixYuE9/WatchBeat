# Dependency registry

## 当前依赖

shipping `ECGCore` 与 iOS App 没有第三方 package dependency，只使用 Swift 标准库、
Foundation、SwiftUI、HealthKit 和测试框架。build 5 的 gradient-energy + RR analyzer 是本仓库
纯 Swift 实现；没有复制 PeakSwift/SciPy 代码，也不需要 Python、网络或服务器推理。

## 候选与决策

| 资源 | 固定版本/commit | 许可证 | Runtime | 用途 | 决策/可替换性 |
|---|---|---|---|---|---|
| [CardioKit/PeakSwift](https://github.com/CardioKit/PeakSwift) | `v1.0.0` / `18fe5e7c674f915c3666e0414c7f2ac39b241bb9` | Apache-2.0；无 NOTICE at pin | 否；离线 benchmark 已在 MVP 清理中移除 | 曾作九种 R 峰 detector 候选 | 未采用；见 Git 历史 `c3c3e0e` |
| [NumPy](https://numpy.org/) | `1.23.5`，`prototype-requirements.txt` | BSD-3-Clause | 仅离线 Python tools | 统一 CSV 原型的数值数组和 MIT-BIH adapter | 不进入 iOS App；App 已有纯 Swift 垂直闭环 |
| [SciPy](https://scipy.org/) | `1.10.0`，`prototype-requirements.txt` | BSD-3-Clause | 仅离线 Python tools | 最小 R 峰流程的离线滤波/交叉检查 | 不进入 iOS App；App 使用独立 Swift 实现 |
| [CardioKit/PeakWatch](https://github.com/CardioKit/PeakWatch) | 不适用，参考时记录 commit | Apache-2.0（需再次核对仓库） | 否 | 工程/交互参考 | 不整仓复制 |
| [StanfordSpezi/SpeziHealthKit](https://github.com/StanfordSpezi/SpeziHealthKit) | 不集成；参考时记录 commit | MIT | 否 | Swift concurrency/HealthKit API 参考 | 以最小自有 mapper 替代大型依赖 |
| [MIT-LCP/wfdb-python](https://github.com/MIT-LCP/wfdb-python) | Milestone 3 lockfile 冻结 | MIT | 否，tools only | WFDB 读取、XQRS 与评测 | Python validation 环境可替换 |
| [NeuroKit2](https://github.com/neuropsychology/NeuroKit) | Milestone 3 lockfile 冻结 | MIT | 否，tools only | 合成/交叉检查 | 可选验证依赖 |
| [BioSPPy](https://github.com/PIA-Group/BioSPPy) | Milestone 3 lockfile 冻结 | BSD-3-Clause | 否，tools only | 第二 detector reference | 可选验证依赖 |
| py-ecg-detectors / HeartPy | 不引入 | GPL-3.0 | 否 | 仅作为文献线索 | 不复制、不链接、不分发 |

PeakSwift 候选审计与 `Tools/PeakSwiftBenchmark` 已在 MVP 清理中删除，审计记录保留在 Git 历史
（commit `c3c3e0e` 的 `Tools/PeakSwiftBenchmark/dependency-lock.json`）。

## 引入门槛

每个依赖必须记录：URL、完整 tag/commit、校验来源、许可证、传递依赖、是否进入 App
runtime、必要性、替代方案、二进制/网络行为和移除成本。禁止跟随 `main`。新增 runtime
依赖需更新本文件、ADR、`THIRD_PARTY_NOTICES.md` 和可重现 lockfile。

更多理由见 [ADR-0001](ADR/0001-r-peak-dependency-strategy.md) 与
[ADR-0002](ADR/0002-peakswift-benchmark-boundary.md)。
