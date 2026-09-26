# ECG Research App

一个隐私优先、完全本地、可解释的开源研究项目，目标是在 iPhone 上读取
Apple Watch 官方 ECG App 已保存到 Apple Health 的单导联 ECG，并以保守、
可审计的方式标记疑似提前心搏。

> **当前状态：Milestone 0（架构基线）。** 仓库目前只有平台无关的
> `ECGCore` 契约、原始时间轴完整性检查和单元测试源码。没有可运行的 iOS App，
> 没有 PAC/PVC 分类器，也没有任何准确率声明。当前开发机是 Windows，未安装
> Swift 或 Xcode，因此源码尚未编译。详见
> [NEEDS_MACOS_VALIDATION.md](NEEDS_MACOS_VALIDATION.md)。

## 医疗安全声明

> This app is intended for informational and research purposes only. It does not
> provide a medical diagnosis. Possible PAC/PVC-like classifications may be
> incorrect. Do not use this app for emergency or treatment decisions.

本项目仅用于信息展示和研究，不提供医疗诊断。未来显示的“疑似房性早搏样心搏”
或“疑似室性早搏样心搏”可能不正确，不得用于急症判断、治疗或用药决策。出现胸痛、
晕厥、明显呼吸困难、持续严重心悸或其他严重症状时，应及时寻求专业医疗帮助。

## 目标结果词汇

产品只允许使用以下保守结果：

| Internal value | English UI | 中文 UI |
|---|---|---|
| `normal` | Normal Beat | 正常心搏 |
| `possiblePAC` | Possible PAC-like Beat | 疑似房性早搏样心搏 |
| `possiblePVC` | Possible PVC-like Beat | 疑似室性早搏样心搏 |
| `prematureUncertain` | Premature Beat — Uncertain | 疑似早搏—无法确定类型 |
| `noiseInvalid` | Noise / Invalid Beat | 噪声或无效心搏 |
| `notAnalyzed` | Not Analyzed | 未分析 |

禁止把这些研究性分类表述为确诊，也不得暗示 Apple Watch 漏诊疾病。

## 计划中的本地数据流

```text
Apple Watch 官方 ECG
  → Apple Health / HealthKit（只读）
  → 原始波形与真实时间戳
  → 完整性检查和信号质量门控
  → R 峰、RR、个人正常模板与形态特征
  → Possible PAC-like / Possible PVC-like / Uncertain / Not Analyzed
  → 本地解释、用户主动导出
```

算法核心不依赖 HealthKit 或 SwiftUI。缺测电压保留为 `nil`，不得通过删除样本改变
时间轴。Apple 的原始 ECG classification 未来只展示和导出，绝不作为 detector 选择、
PAC/PVC 分类或置信度的输入。

## 当前已实现

- 无第三方 runtime 依赖的 `ECGCore` Swift Package 基线。
- HealthKit 无关的 `ECGSignal` 数据边界。
- `RPeakDetecting` 与 `BeatClassifying` 协议。
- 稳定的六类结果、特征快照、reason code 和版本字段。
- 不删除样本的结构完整性检查：数组长度、缺测、非有限值、重复/倒退时间戳、
  稳健采样率推断和时间间隔相对 MAD。
- 确定性单元测试源码。
- 隐私、算法、验证、数据集、监管和依赖决策文档。

## 尚未实现

- SwiftUI App、HealthKit entitlement、授权流程和 ECG 历史列表。
- 波形读取、显示、导出和真机验证。
- 数字滤波、完整信号质量门控、R 峰 detector、RR、模板、QRS 和分类器。
- 离线公开数据评测结果或 Apple Watch 域验证。

因此目前没有应用截图。截图只能在 Milestone 1 的界面于 Xcode 编译并实际运行后加入，
不会用静态 mock 冒充已完成的产品。

## 构建 ECGCore

需要 Swift 5.9 或更高版本：

```bash
cd ECGCore
swift test
```

当前 Windows 环境没有 `swift`，上述命令**尚未执行**。首次在装有 Swift 的环境执行时，
任何编译错误都必须修复并记录，不能把静态检查写成测试通过。

## 未来构建 iPhone App

最低目标暂定 iOS 17.0。需要：

1. 一台受支持的 macOS 主机和兼容版本的 Xcode。
2. Apple Developer 签名配置及带 HealthKit capability 的 App ID。
3. 一台能访问真实 Apple Health ECG 数据的兼容 iPhone。
4. 只请求 ECG 读取权限；`toShare` 必须为空。
5. 在真机逐项完成 [NEEDS_MACOS_VALIDATION.md](NEEDS_MACOS_VALIDATION.md)。

模拟器、合成数据和静态 mock 不能替代 HealthKit 真实 ECG 的端到端验收。

## 隐私

All ECG processing is performed locally on the user's device.

本项目不需要账号、服务器、网络推理、广告、遥测、分析 SDK 或崩溃上传。默认不持久化
原始 ECG 副本，不把 ECG 数值、HealthKit identifier 或日期写入日志，不向 HealthKit
写入推断结果。只有用户主动操作时才通过系统 share sheet 导出敏感文件。完整政策见
[Docs/PRIVACY.md](Docs/PRIVACY.md)。

## 文档索引

- [架构](Docs/ARCHITECTURE.md)
- [算法边界与研究参数](Docs/ALGORITHM.md)
- [验证状态与指标](Docs/VALIDATION.md)
- [数据集登记](Docs/DATASETS.md)
- [隐私](Docs/PRIVACY.md)
- [监管与产品表述](Docs/REGULATORY.md)
- [依赖登记](Docs/DEPENDENCIES.md)
- [ADR-0001：R 峰依赖策略](Docs/ADR/0001-r-peak-dependency-strategy.md)
- [工作清单](TODO.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)

## 开源与贡献

项目主体采用 [MIT License](LICENSE)。候选第三方组件不会自动获得相同许可证；若未来
引入，必须固定版本、审查传递依赖，并保留其许可证、版权和 NOTICE。贡献前请阅读
[CONTRIBUTING.md](CONTRIBUTING.md)。
