<p align="center">
  <img src="iOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="180" alt="WatchBeat App Icon">
</p>

<h1 align="center">WatchBeat</h1>

<p align="center">
  从 Apple Health 读取 Apple Watch 单导联 ECG，完全在 iPhone 本地标记疑似早搏候选。
</p>

<p align="center">
  <code>iOS 17+</code> · <code>HealthKit 只读</code> · <code>端侧分析</code> · <code>开源</code>
</p>

> [!WARNING]
> WatchBeat 仅用于信息展示和研究，不提供医疗诊断。检测结果可能漏报或误报，不得用于急症、
> 治疗或用药决策。出现胸痛、晕厥、明显呼吸困难或持续严重心悸时，请及时就医。

## 它做什么

WatchBeat 是一个隐私优先的开源 iPhone App。它读取 Apple Watch 官方 ECG App 已保存到
Apple Health 的心电记录，在设备本地完成信号检查、R 峰检测与 RR 间期分析，并保守地标记
**疑似早搏候选**。

```text
Apple Watch ECG
      ↓  HealthKit（只读）
iPhone 本地信号检查与 R 峰检测
      ↓  RR 间期分析
疑似早搏候选、波形标记与用户主动导出
```

当前算法只依据 RR 时序发现提前心搏，因此不会把候选强行判成房早或室早。Apple 自带的 ECG
分类只展示，不参与模型判断。

## 核心能力

- **完全本地：** 无账号、服务器、网络推理、广告或遥测。
- **只读 HealthKit：** 不向 Apple Health 写入任何分析结果。
- **可解释结果：** 显示 R–R 间期、候选位置、RR 比值、拒判原因，以及最短/最长 R–R、逐搏心率范围、
  QRS 峰谷电压差等描述性数值。
- **完整波形：** 细节波形下方显示整段 ECG 概览，点击或拖动任意位置快速定位，蓝色选框同步显示当前可见范围；
  时间轴与电压轴（mV）可分别缩放；黄色标记疑似早搏候选并可一键逐个跳转；
  内置适合手机操作的两点测量工具，读取任意两点的时间差与电压差。
- **安全导出：** 经用户确认后，通过系统分享导出 CSV 与 JSON。
- **可直接体验：** 内置确定性合成 ECG 示例，无授权或无数据时也能查看完整流程。
- **跨记录概览：** 按全部、近 7 天、近 30 天或自定义日期汇总记录数、心率趋势、候选总数、
  分析覆盖情况与自述标签分布；趋势图每页最多 14 天／12 个月，超出可左右滑动；点击标签可查看对应记录。
- **增量筛查：** 每条记录的筛查结果（仅候选数，不含波形）保存在本机受保护缓存，重新打开只分析
  新增记录；算法或参数变化时自动重算，设置中可清除。
- **组合查找：** 日期、分析结果、预设症状／自定义标签和批注关键字联合筛选；历史查询不再
  限于最近 200 条。多个选中标签匹配任意一个，其余条件同时满足。
- **记录感受：** 每条 ECG 可多选当时的症状、复用或添加自定义标签并保存文字批注。
  批注仅保存在本机受保护文件，设置中可清除；合成示例批注只在本次进程内保留。
- **中英双语：** 简体中文与 English 可即时切换。

## 当前状态

**v0.5.0 (6) MVP** 已接通“读取 → 波形 → 本机分析 → 结果 → 导出”流程。

当前版本仍需在 macOS / Xcode 上完成最新源码的构建、模拟器和真机 HealthKit 验证；公开数据
评测也不能替代 Apple Watch 真实数据验证。具体验收项见
[NEEDS_MACOS_VALIDATION.md](NEEDS_MACOS_VALIDATION.md)。

跨记录分析和批注源码已接入，新 Swift 测试尚需在 Mac 执行。概览仅汇总实际记录的 ECG，
不估算全天早搏负荷；用户标签不参与算法判断。

### 公开数据开发集基线

在 MIT-BIH development 划分的 1,800 个独立 30 秒窗口上：

| 任务 | 灵敏度 | 阳性预测值 |
|---|---:|---:|
| R 峰检测 | 98.36% | 99.69% |
| 早搏候选 | 44.9% | 66.7% |

R 峰检测已经较稳定；RR-only 早搏规则仍会漏掉约一半标注早搏，是当前最重要的算法限制。
完整口径和复现实验见 [验证记录](Docs/VALIDATION.md)。

## 快速开始

需要一台安装 Xcode、具备 iOS 17+ SDK 的 Mac：

```bash
git clone https://github.com/FelixYuE9/WatchBeat.git
cd WatchBeat

bash Tools/run-core-tests.sh --parallel
bash Tools/run-app-tests.sh --parallel
open iOS/WatchBeat.xcodeproj
```

在 Xcode 中打开 **WatchBeatApp → Signing & Capabilities**，选择自己的开发团队与唯一
Bundle ID，然后连接 iPhone 并运行。完整步骤见
[真机打包与安装](Docs/IPHONE_INSTALL.md)。

## 项目结构

| 路径 | 内容 |
|---|---|
| `ECGCore/` | 平台无关的 Swift 算法、信号模型和报告契约 |
| `iOS/` | SwiftUI App、HealthKit 读取层、资源与测试 |
| `Tools/Validation/` | 公开数据下载、算法镜像、评测和 CSV 校验工具 |
| `Docs/` | 架构、算法、隐私、验证与发行文档 |

## 进一步阅读

- [算法说明](Docs/ALGORITHM.md)
- [输入与输出契约](Docs/CONTRACTS.md)
- [ECG 可扩展指标](Docs/ECG_METRICS.md)
- [验证记录](Docs/VALIDATION.md)
- [隐私政策](Docs/PRIVACY.md)
- [真机安装](Docs/IPHONE_INSTALL.md)
- [架构说明](Docs/ARCHITECTURE.md)

## 许可证

WatchBeat 采用 [MIT License](LICENSE)。欢迎阅读
[贡献指南](CONTRIBUTING.md) 后参与改进。
