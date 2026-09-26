# Dependency registry

## 当前依赖

Milestone 0 的 `ECGCore` 没有第三方 package dependency，只使用 Swift 标准库、Foundation
和 XCTest。没有第三方代码复制进仓库。

## 候选与决策

| 资源 | 固定版本/commit | 许可证 | Runtime | 用途 | 决策/可替换性 |
|---|---|---|---|---|---|
| [CardioKit/PeakSwift](https://github.com/CardioKit/PeakSwift) | 候选 tag `v1.0.0`；引入前记录完整 SHA | Apache-2.0；另有传递依赖待审 | 候选，尚未加入 | 两种以上单导联 R 峰 detector 与质量基线 | 先基准；通过 adapter 可替换 |
| [CardioKit/PeakWatch](https://github.com/CardioKit/PeakWatch) | 不适用，参考时记录 commit | Apache-2.0（需再次核对仓库） | 否 | 工程/交互参考 | 不整仓复制 |
| [StanfordSpezi/SpeziHealthKit](https://github.com/StanfordSpezi/SpeziHealthKit) | 不集成；参考时记录 commit | MIT | 否 | Swift concurrency/HealthKit API 参考 | 以最小自有 mapper 替代大型依赖 |
| [MIT-LCP/wfdb-python](https://github.com/MIT-LCP/wfdb-python) | Milestone 3 lockfile 冻结 | MIT | 否，tools only | WFDB 读取、XQRS 与评测 | Python validation 环境可替换 |
| [NeuroKit2](https://github.com/neuropsychology/NeuroKit) | Milestone 3 lockfile 冻结 | MIT | 否，tools only | 合成/交叉检查 | 可选验证依赖 |
| [BioSPPy](https://github.com/PIA-Group/BioSPPy) | Milestone 3 lockfile 冻结 | BSD-3-Clause | 否，tools only | 第二 detector reference | 可选验证依赖 |
| py-ecg-detectors / HeartPy | 不引入 | GPL-3.0 | 否 | 仅作为文献线索 | 不复制、不链接、不分发 |

PeakSwift 当前公开 release 页面显示 `v1.0.0`，其 `Package.swift` 还引用 Surge 并包含 C/C++
targets；因此引入前需在目标 Xcode/Swift 版本实际构建，核对 Surge、IIR/wavelib 等来源、
许可证和 NOTICE。仓库 README 的 branch-based 安装示例不是本项目允许的 pinning 策略。

## 引入门槛

每个依赖必须记录：URL、完整 tag/commit、校验来源、许可证、传递依赖、是否进入 App
runtime、必要性、替代方案、二进制/网络行为和移除成本。禁止跟随 `main`。新增 runtime
依赖需更新本文件、ADR、`THIRD_PARTY_NOTICES.md` 和可重现 lockfile。

更多理由见 [ADR-0001](ADR/0001-r-peak-dependency-strategy.md)。
