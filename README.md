# WatchBeat — 开源早搏候选识别（研究用途）

一个隐私优先、完全本地运行的开源 iPhone App：读取 Apple Watch 官方 ECG App 已保存到
Apple 健康的单导联心电，在手机上检测 R 峰与 RR 间期，并保守地标记**疑似早搏候选**。

> **当前版本：v0.5.0 (6) MVP。** 读取 → 统一波形 → 本机分析 → 结果/导出 全流程已接通；
> 无第三方 runtime 依赖、无服务器、无网络推理。本版 Swift 源码在 Windows 上整理，需在 Mac 上
> 编译测试，步骤见 [NEEDS_MACOS_VALIDATION.md](NEEDS_MACOS_VALIDATION.md)。

## 医疗安全声明

> This app is intended for informational and research purposes only. It does not
> provide a medical diagnosis. Possible PAC/PVC-like classifications may be
> incorrect. Do not use this app for emergency or treatment decisions.

本项目仅用于信息展示和研究，不提供医疗诊断。结果可能不正确，不得用于急症判断、治疗或
用药决策。出现胸痛、晕厥、明显呼吸困难、持续严重心悸或其他严重症状时，应及时就医。

## 功能

- 只读 HealthKit 心电授权（`toShare` 为空），列表只读元数据，打开详情时才读取电压。
- 可缩放、横向滚动的全分辨率波形，标出模型 R 峰（橙）、R–R 间期（ms）与疑似早搏（红）。
- 本机研究分析卡片：R 峰数、疑似早搏候选及其时间/RR 比值、拒判原因、**分析耗时**。
- 内置确定性合成示例（含 1 个房早样、1 个室早样心搏），无授权/无数据时也可体验与测速；
  它与真实数据走完全相同的分析入口，不注入答案。
- 用户确认后通过系统分享导出原始 CSV、元数据 JSON、分析结果 JSON。
- 简体中文 / English 即时切换。

## 结果词汇

| Internal value | English UI | 中文 UI | v1 是否输出 |
|---|---|---|---|
| `normal` | Normal Beat | 正常心搏 | 是 |
| `prematureUncertain` | Premature Beat — Uncertain | 疑似早搏—无法确定类型 | 是 |
| `notAnalyzed` | Not Analyzed | 未分析 | 是 |
| `possiblePAC` | Possible PAC-like Beat | 疑似房性早搏样心搏 | 预留 |
| `possiblePVC` | Possible PVC-like Beat | 疑似室性早搏样心搏 | 预留 |
| `noiseInvalid` | Noise / Invalid Beat | 噪声或无效心搏 | 预留 |

当前模型只看 RR 时序，因此只给出“疑似早搏、类型未定”，不凭 RR 猜 PAC/PVC。

## 数据流

```text
Apple Watch ECG → Apple 健康（只读）
  → ECGSignal  watchbeat.ecg.signal.v1（时间 s + I 导联样 mV，缺测保留为 nil）
  → 结构拒判（缺测、非有限值、时间戳、采样率 60–1000 Hz、时长 ≥ 8 s）
  → 5–25 Hz 零相位带通 → 斜率能量 → 120 ms 居中积分 → 自适应阈值 → R 峰细化
  → 最近 8 个 RR 的中位数基线；RR < 0.8 × 基线 → prematureUncertain
  → ECGAnalysisReport v1（JSON 可导出）
```

算法核心 `ECGCore` 不依赖 HealthKit / SwiftUI。Apple 自带的 ECG 分类只展示，不作为模型输入。
详见 [算法说明](Docs/ALGORITHM.md) 与 [输入/输出契约](Docs/CONTRACTS.md)。

## 当前准确率（公开数据，开发集）

App 算法的 NumPy 镜像（`Tools/Validation/evaluate_swift_analyzer_mirror.py`）在 MIT-BIH
development 划分的 1,800 个独立 30 秒窗口上：

| 指标 | 数值 |
|---|---|
| R 峰灵敏度 / 阳性预测值 | 0.9836 / 0.9969 |
| 早搏候选灵敏度 / 阳性预测值 | 0.449 / 0.667 |

R 峰检测可靠；RR-only 早搏规则约漏掉一半标注早搏，是下一步重点。公开数据指标**不等于**
Apple Watch 准确率，尚无真机域验证。

## 在 Mac 上构建与测试

需要 Xcode（iOS 17+ SDK）。在仓库根目录：

```bash
bash Tools/run-core-tests.sh --parallel   # ECGCore 单元测试
bash Tools/run-app-tests.sh --parallel    # iOS 包单元测试
```

打开 `iOS/WatchBeat.xcodeproj`，在 **WatchBeatApp → Signing & Capabilities** 选择自己的 Team 和
唯一 Bundle ID，连接 iPhone 后 **Run**；打包用 **Product → Archive**。详见
[真机打包与安装](Docs/IPHONE_INSTALL.md)，测速与验收步骤见
[NEEDS_MACOS_VALIDATION.md](NEEDS_MACOS_VALIDATION.md)。

## 离线工具（Windows / macOS，Python）

`Tools/Validation/` 提供原始 CSV 校验、MIT-BIH 下载与冻结划分、R 峰评测器、App 算法镜像评测，
以及 SciPy 版原型。依赖见 `Tools/Validation/prototype-requirements.txt`：

```bash
python -m unittest discover -s Tools/Validation/tests
python Tools/Validation/evaluate_swift_analyzer_mirror.py        # 需先下载 MIT-BIH
python Tools/Validation/validate_raw_ecg_csv.py <App 导出的 CSV>
```

## 目录

```text
ECGCore/          平台无关的 Swift Package：ECGSignal、R 峰检测、早搏分析、报告契约
iOS/              SwiftUI App、HealthKit 读取层、Xcode 工程与单元测试
Tools/            Swift 测试脚本；Validation/ 为离线 Python 验证工具
Docs/             架构、算法、契约、验证、隐私、监管、发行与 ADR
```

## 隐私

All ECG processing is performed locally on the user's device.

不需要账号、服务器、广告、遥测或崩溃上传；不持久化原始 ECG 副本，不在日志中写入 ECG 数值、
HealthKit 标识或日期，不向 HealthKit 写入任何内容。只有用户主动操作时才导出文件。
见 [Docs/PRIVACY.md](Docs/PRIVACY.md)。

## 文档

[架构](Docs/ARCHITECTURE.md) · [契约](Docs/CONTRACTS.md) · [算法](Docs/ALGORITHM.md) ·
[验证记录](Docs/VALIDATION.md) · [真机安装](Docs/IPHONE_INSTALL.md) · [数据集](Docs/DATASETS.md) ·
[隐私](Docs/PRIVACY.md) · [监管表述](Docs/REGULATORY.md) · [发行](Docs/DISTRIBUTION.md) ·
[依赖](Docs/DEPENDENCIES.md) · [ADR](Docs/ADR/) · [TODO](TODO.md) ·
[第三方声明](THIRD_PARTY_NOTICES.md)

## 许可证与贡献

项目采用 [MIT License](LICENSE)。贡献前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。
