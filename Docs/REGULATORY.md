# Regulatory and product-language boundary

## 产品定位

这是个人研究和信息展示工具，不是医疗诊断、急症分诊或治疗决策系统。免责声明不会自动
豁免 App Store 医疗审核、当地医疗器械法规、隐私法规或消费者保护义务。公开发布是独立
milestone，需要医学、法律和监管评估。

## 必须显示的声明

首次启动、结果页和 README 必须清楚显示：

> This app is intended for informational and research purposes only. It does not
> provide a medical diagnosis. Possible PAC/PVC-like classifications may be
> incorrect. Do not use this app for emergency or treatment decisions.

并说明：出现胸痛、晕厥、明显呼吸困难、持续严重心悸或其他严重症状时，应寻求专业医疗
帮助。本 App 不承担急症分诊功能。

## 允许与禁止的语言

允许：Normal Beat、Possible PAC-like Beat、Possible PVC-like Beat、Premature Beat —
Uncertain、Noise / Invalid Beat、Not Analyzed 及其批准的中文对应词。

禁止：

- “You have PAC/PVC”或“确诊房早/室早”。
- 声称 Apple Watch 漏诊某种疾病。
- 没有独立 Apple Watch 逐 beat 真值验证时宣传灵敏度、特异度或准确率。
- 把 MIT-BIH/Icentia 等公共数据结果称为 Apple Watch accuracy。
- 用“FDA approved”“clinically validated”等措辞暗示不存在的审批或证据。

## 发布前检查

1. 重新阅读发布时最新的 Apple App Review Guidelines，尤其医疗相关 1.4.1：
   <https://developer.apple.com/app-store/review/guidelines/>。
2. 确认目标司法辖区的医疗器械、健康数据和研究要求。
3. 独立审查准确性报告、failure cases、Uncertain coverage 和用户可理解性。
4. 核对所有 UI、App Store metadata、截图和 README 没有越界声明。
5. 完成 HealthKit、隐私清单、签名和数据处理披露。

本文件不是法律意见，也不判断该产品在任何司法辖区的最终监管分类。
