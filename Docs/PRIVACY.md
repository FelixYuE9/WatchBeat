# Privacy policy and engineering requirements

## 原则

All ECG processing is performed locally on the user's device.

ECG 属于敏感健康数据。项目默认最小读取、最小保留、无网络处理，并要求任何未来改动先
更新本文件和威胁模型。App 只在设备本地处理用户授权读取的 ECG。

## 数据生命周期

| 阶段 | 允许行为 | 禁止/默认关闭 |
|---|---|---|
| 读取 | 仅请求 HealthKit ECG read access | 不请求写入，不读取无关健康类型 |
| 处理 | iPhone 内存中完成完整性、质量和研究分析 | 不上传，不调用在线模型/后端 |
| 日志 | 仅非敏感技术状态和聚合错误码 | 不记录波形、HealthKit ID、日期或可识别 metadata |
| 持久化 | 用户主动保存的症状、标签和批注保存在本机受保护文件 | 不保存原始 ECG 副本、分析报告或采集日期，不参与 iCloud 备份 |
| 导出 | 用户主动触发系统 share sheet | 不自动分享，不静默写入公共目录 |
| 删除 | 临时文件分享完成后尽快清理 | 不保留隐藏副本 |

“概览”或“数据”页出现后，App 会按顺序读取每条可访问记录的电压，在本机运行同一研究分析，
并只在进程内缓存“候选数 / 未标记候选 / 无法分析”等简要列表结果。完整电压数组在该次
筛查结束后释放，不写入文件或列表缓存；打开详情时按需重新读取，以显示波形和完整报告。

若未来确需本地缓存，必须使用 iOS file protection、排除 iCloud backup、提供清除机制，并在
实现前更新此文档和 UI 告知。不得向 HealthKit 写入本项目推断结果。

## 用户批注与统计

用户可主动保存“记录期间感觉如何”的预设症状、自定义标签和文字批注。为在重启后仍能
对应同一条记录，本地批注文件包含 HealthKit sample UUID 作为关联键；该键不进入日志、
现有导出或网络。文件位于 Application Support 的独立目录，iOS 使用 complete file
protection，并在写入前将目录排除备份。设置页提供“清除所有本地批注”，详情页也可清空
单条批注；不影响 Apple Health 中的记录。无法读取原文件时禁止覆盖，显示重试提示。

合成示例的批注只保留在本次进程内，不写入真实记录的批注文件，也不进入概览统计。
标签和症状来自用户自述，与 Apple 原始症状状态分开显示，不参与算法判断。
概览只对可访问记录进行描述性汇总；未分析、无法分析和读取失败独立计数，不被计为
零候选。心率趋势来自 Apple 记录的平均心率，标签分布只统计已保存的自述标签，不推断
症状与心律的因果关系，也不将短时抽样记录外推为全天早搏负荷。

## HealthKit 权限

- 只请求 `HKElectrocardiogramType` 读取。
- `requestAuthorization(toShare:read:)` 的 share 集合必须为空。
- 只提供读取用途文案；不得用宽泛文案暗示需要其他健康数据。
- HealthKit 不向 App 可靠披露用户是否拒绝读取。零结果必须显示：
  “没有可访问的 ECG；请检查健康权限或先使用 Apple Watch 记录 ECG”，不能断言拒绝。

Apple 文档说明 ECG sample type 用于请求读取和查询，不能写入：
<https://developer.apple.com/documentation/healthkit/hkelectrocardiogramtype>。

## 导出

在导出 raw CSV、feature CSV 或 metadata JSON 前必须说明文件含敏感健康信息。原始 CSV
保持 HealthKit measurement 顺序、时间戳和 `nil`，不能为了美观静默清洗。导出文件名
尽量避免直接包含姓名、HealthKit ID 或完整采集时间。

内置教学 ECG 是确定性数学合成数据，不来自 HealthKit，也不包含个人健康信息。其 UI 标题、
metadata JSON 的 `dataSource` 以及导出文件名都必须明确包含 synthetic/example 语义，防止用户把
它误当作真人记录。它不能作为算法准确率或 Apple Watch 域验证数据。

## UI 与系统表面

- 不在锁屏通知、widget、Spotlight 或剪贴板自动暴露分类结果。
- 没有后台持续监测或实时报警。
- 分享、截图和文件保存由用户明确触发；界面提示接收方可能继续保存数据。

## 第三方与网络

MVP 不包含账号、服务器、广告 SDK、分析 SDK、崩溃上传、LLM 或在线推理。未来若新增会
产生网络流量的依赖，必须单独决策并重新获得产品范围批准；它不能默认接触 ECG 数据。

## 开发与验证数据

- `PrivateValidationData/` 除安全说明外由 Git 忽略。
- 个人 ECG 不进入 issue、PR、测试 fixture、日志或截图。
- 公共数据集下载到 Git 忽略目录，并记录许可、版本和 checksum。
- 发布前运行 secret、签名材料、设备 ID 和波形数据审计。
