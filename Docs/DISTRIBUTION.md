# Funding, App Store and distribution boundary

## 当前建议

保留**一个免费 App**，所有 ECG 功能对所有用户一致开放。若以后希望让海外用户自愿支持开发，
优先在同一个 App 中加入 Apple In-App Purchase 的一次性“支持开发”项目，购买前后不解锁功能、
不提高算法准确率、不改变医疗提示，也不制造“未付费用户得到较差分析”的印象。

不要提交两个功能、内容和界面完全相同、仅价格不同的 Bundle ID。Apple App Review Guideline
4.3(a) 明确要求不要为同一个 App 创建多个 Bundle ID；因此“免费版 + 完全相同的象征性收费版”
有很高的 duplicate/spam 拒审风险：
<https://developer.apple.com/app-store/review/guidelines/#spam>。

Apple 当前明确允许 App 通过 In-App Purchase 接受给开发者的 tip。若在 App 内提供支持入口，
这是比外部收款码更稳妥的全球 App Store 路径：
<https://developer.apple.com/app-store/review/guidelines/#in-app-purchase>。

## GitHub 项目赞助

在 GitHub 仓库外部接受对开源开发的自愿支持，原则上不改变项目源码的 MIT 许可证，也不阻止
以后在 App Store 收费发行。GitHub 官方支持通过 `.github/FUNDING.yml` 展示 GitHub Sponsors、
第三方 funding platform 或自定义链接：
<https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/displaying-a-sponsor-button-in-your-repository>。

发布时优先使用可点击、可审计、可更新的 `FUNDING.yml`，二维码只作为 README 的辅助展示。
如果收款主体不是经认可的公益组织，建议写“赞助 / 支持开发”，不要声称 charitable donation、
免税捐款或开具公益抵税凭证。所有收入仍可能涉及收款账户、税务申报、退款、制裁/地区限制和
支付平台规则；应按开发者及收款主体所在地单独咨询会计或法律专业人士。GitHub 也提示赞助通常
不当然具有税前扣除资格：
<https://docs.github.com/en/sponsors/sponsoring-open-source-contributors/about-sponsorships-fees-and-taxes>。

不要在 App 内直接放个人收款二维码作为默认方案。各 storefront 的外部购买链接规则不同且会
变化；Apple 当前允许 IAP tip，而外部付款 CTA 在美国以外通常受限制。仓库、官网或其他 App
之外的沟通可以独立进行，但不得把付款和任何数字功能、内容、优先分析或准确率关联起来。

## 开源与收费并存的条件

收费的是 Apple 分发、便利性和持续维护，不是把他人许可证改成闭源。当前策略允许商业发行，
但每次 release 都必须：

- 保留本项目 MIT License；
- 对将来实际链接/分发的任何第三方代码保留完整版权、许可证和所需 notices（当前 App 无第三方
  runtime 依赖）；
- 对修改过的 Apache 文件作显著说明，并检查上游是否出现 NOTICE；
- 不把 PhysioNet 数据、许可证或公开数据指标包装成自有临床证据；
- 新依赖先做许可证扫描，避免把 GPL、禁止商业使用、禁止医疗使用或来源不明的代码误接入 App；
- 不使用 Apple 商标、图标或产品措辞暗示 Apple 认可本 App 或算法结果。

开源用户可以自行构建免费版本；这与 App Store 中提供官方签名、自动更新和自愿 IAP 支持并不
矛盾。README 和 App Store metadata 应把这一点写清楚，避免让付费用户误以为买到了额外医学能力。

## 医疗与健康数据风险

最大的发布风险不是收费方式，而是 App 对 ECG 的解释。Apple Guideline 1.4.1 会更严格审核
可能用于诊断/治疗或可能提供不准确信息的医疗 App，要求披露支持健康测量准确性声明的数据与
方法；无法验证时可能拒审，并要求提醒用户在作医疗决定前咨询医生：
<https://developer.apple.com/app-store/review/guidelines/#physical-harm>。

免责声明有必要，但不会改变软件实际功能和 intended use。美国 FDA 的现行 guidance 明确把
“分析和解释 EKG 波形以检测心脏功能异常”的软件列为可能受监管的设备软件功能示例：
<https://www.fda.gov/regulatory-information/search-fda-guidance-documents/policy-device-software-functions-and-mobile-medical-applications>。
欧盟也按软件的医疗目的、所提供信息和决策影响判断 Medical Device Software：
<https://health.ec.europa.eu/document/download/b45335c5-1679-4c71-a91c-fc7a4d37f12b_en?filename=md_mdcg_2019_11_en.pdf>。

因此公开发布前至少要做以下独立 gate：

1. 冻结目标市场和 intended use；逐地区判断是否属于医疗器械软件及其分类/注册要求。
2. 在没有足够证据或监管路径前，不把 PAC/PVC 输出宣传为诊断、筛查、报警或治疗依据。
3. 完成公开数据评测、独立 Apple Watch 域逐 beat 验证、失败案例、Uncertain coverage 和版本锁定。
4. 准备算法方法、数据来源、限制、用户说明、风险分析、变更控制和审核备注；有许可/批准时才声称。
5. 保持所有处理本地化；HealthKit 数据不得用于广告/营销或未经许可的数据挖掘，不写入虚假健康
   数据，也不把个人健康信息存进 iCloud。Apple 的相关规则见：
   <https://developer.apple.com/app-store/review/guidelines/#health-and-health-research>。

## 商店与运营检查

- 一个 App、一个 Bundle ID、一个用户群；免费核心功能 + 可选 IAP tip。
- 在 App Review notes 中解释：tip 完全可选，购买前后功能完全相同。
- 销售 App 或提供 IAP 前，Account Holder 需接受 Paid Apps Agreement，并完成税务和银行资料：
  <https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements>。
- 准备隐私政策、Support URL、开发者联系方式、App Privacy 回答、第三方许可证页面与可访问性。
- 对价格、退款、消费者保护、税务、医疗器械、隐私和出口/制裁要求按目标 storefront 复核。
- 发布前重新读取最新规则；App Review 和各地区法律均可能变化。

本文件是工程与发布风险清单，不构成法律、税务、医学或监管意见。
