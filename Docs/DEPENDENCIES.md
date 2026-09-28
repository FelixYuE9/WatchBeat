# Dependency registry

## 当前依赖

Milestone 0 的 `ECGCore` 没有第三方 package dependency，只使用 Swift 标准库、Foundation
和 XCTest。没有第三方代码复制进仓库。

## 候选与决策

| 资源 | 固定版本/commit | 许可证 | Runtime | 用途 | 决策/可替换性 |
|---|---|---|---|---|---|
| [CardioKit/PeakSwift](https://github.com/CardioKit/PeakSwift) | `v1.0.0` / `18fe5e7c674f915c3666e0414c7f2ac39b241bb9` | Apache-2.0；无 NOTICE at pin | 仅 `Tools/PeakSwiftBenchmark`，未进入 App | 九种单导联 R 峰 detector 候选 | 先基准；不代表生产选择 |
| [CardioKit/PeakWatch](https://github.com/CardioKit/PeakWatch) | 不适用，参考时记录 commit | Apache-2.0（需再次核对仓库） | 否 | 工程/交互参考 | 不整仓复制 |
| [StanfordSpezi/SpeziHealthKit](https://github.com/StanfordSpezi/SpeziHealthKit) | 不集成；参考时记录 commit | MIT | 否 | Swift concurrency/HealthKit API 参考 | 以最小自有 mapper 替代大型依赖 |
| [MIT-LCP/wfdb-python](https://github.com/MIT-LCP/wfdb-python) | Milestone 3 lockfile 冻结 | MIT | 否，tools only | WFDB 读取、XQRS 与评测 | Python validation 环境可替换 |
| [NeuroKit2](https://github.com/neuropsychology/NeuroKit) | Milestone 3 lockfile 冻结 | MIT | 否，tools only | 合成/交叉检查 | 可选验证依赖 |
| [BioSPPy](https://github.com/PIA-Group/BioSPPy) | Milestone 3 lockfile 冻结 | BSD-3-Clause | 否，tools only | 第二 detector reference | 可选验证依赖 |
| py-ecg-detectors / HeartPy | 不引入 | GPL-3.0 | 否 | 仅作为文献线索 | 不复制、不链接、不分发 |

PeakSwift 的候选审计已经冻结：Surge 2.3.2 / `6e4a47e63da8801afe6188cf039e9f04eb577721`
（MIT）、IIR / `9ef2a04ac3a44a8762b6a209c18e3bdb00394e5b`（MIT）、wavelib /
`a92456d2e20451772dd76c2a0a3368537ee94184`（BSD-3-Clause）。精确记录见
`Tools/PeakSwiftBenchmark/dependency-lock.json`。上游 wavelib submodule 使用 SSH URL，测试脚本
仅对子进程改写 HTTPS；主 target 还包含 C/C++/Objective-C++ 并直接 import HealthKit，因此必须
在目标 Xcode/Swift 环境实际编译。仓库 README 的 branch-based 安装示例不是本项目允许的
pinning 策略。

## 引入门槛

每个依赖必须记录：URL、完整 tag/commit、校验来源、许可证、传递依赖、是否进入 App
runtime、必要性、替代方案、二进制/网络行为和移除成本。禁止跟随 `main`。新增 runtime
依赖需更新本文件、ADR、`THIRD_PARTY_NOTICES.md` 和可重现 lockfile。

更多理由见 [ADR-0001](ADR/0001-r-peak-dependency-strategy.md) 与
[ADR-0002](ADR/0002-peakswift-benchmark-boundary.md)。
