# Validation

## 验证状态摘要

截至 2026-09-26，本仓库处于 Milestone 0。没有 R 峰或 beat 分类性能报告，也没有
Apple Watch 域准确率。任何 sensitivity、specificity、precision、recall 或 accuracy
声明在当前阶段都是不真实的。

## 实际环境审计

工作目录：当前 Git repository root。公开文档不固化本机用户名或绝对路径；原始 `pwd`
结果只用于本次开发会话审计。

| 检查 | 实际结果 |
|---|---|
| Git | 新仓库，`master`，尚无 commit；开始时除 `.git` 外为空 |
| OS | Windows 10.0.19045，PowerShell 7.6.5 |
| `uname -a` | 命令不可用 |
| `git --version` | `2.39.1.windows.1` |
| `python --version` | `3.10.9` |
| `swift --version` | 命令不可用 |
| `xcodebuild -version` | 命令不可用 |

因此本轮可以执行 Python 离线工具测试和文本/结构审计，但不能执行 Swift/Xcode 验证。
`swift test`、Xcode build、iOS simulator 和真机 HealthKit 均为**未验证**；绝不能把“已写
Swift 测试源码”表述为“Swift 测试通过”。

## 本轮实际执行结果

```text
python -m unittest discover -s Tools/Validation/tests -v
```

首次运行失败：测试通过 `importlib` 动态载入模块时未先登记 `sys.modules`，Python 3.10
的 `dataclass` 无法解析模块 namespace。修复测试 loader 后重新运行：3 tests，全部通过，
exit 0。保留此失败记录，避免把“最终通过”写成“一次即通过”。

```text
python Tools/Validation/validate_raw_ecg_csv.py \
  Tools/Validation/tests/fixtures/raw_valid.csv
```

结果：exit 0；4 samples；missing index `[2]` 被保留；推断 500 Hz；relative MAD 0；
`structurally_valid: true`。fixture 是手工合成结构数据，不是人体 ECG，也不证明算法表现。

其他实际审计：

- `python -m compileall -q Tools/Validation`：通过。
- required-file existence check：15/15 存在。
- local Markdown link target check：通过，无缺失的本地目标。
- trailing-whitespace scan：通过。
- `ECGCore/Package.swift` external `.package(...)` scan：无第三方 Swift dependency。
- `git check-ignore`：私有 ECG、下载数据和用户导出示例均命中预期忽略规则。

## Milestone 0 验收表

| 条件 | 状态 | 证据/限制 |
|---|---|---|
| 环境与 Git 审计 | 完成 | 上表记录实际输出 |
| 文档结构 | 完成 | `README.md`、`Docs/`、`TODO.md` 等 |
| 平台无关 ECGCore | 源码完成，编译未验证 | `ECGCore/Package.swift` 无外部依赖 |
| 最小 pure-function tests | 源码完成，运行未验证 | `ECGCore/Tests/` |
| Python raw CSV checker | 完成并在 Python 3.10.9 通过 3 tests | 仅结构检查，不是 ECG 算法 |
| dependency ADR | 完成 | `Docs/ADR/0001-...md` |
| 私有 ECG Git 隔离 | 完成 | `.gitignore` 与目录安全说明 |
| iOS App / HealthKit reader | 未开始 | 无 Xcode；符合条件性范围 |
| 真实 iPhone ECG | 未验证 | 需要兼容 iPhone、权限和真实记录 |

## 首次可用 Swift 环境的必跑命令

```bash
cd ECGCore
swift package describe
swift test --parallel
```

在 macOS/Xcode 建立 app 后还必须执行实际 scheme 名称对应的 `xcodebuild build` 和
`xcodebuild test`。命令、Xcode/Swift 版本、destination 和完整结果摘要要回填本文件。

## 计划中的离线验证

### R 峰

以预先冻结的时间容差匹配 reference beat，至少报告：recall/sensitivity、precision/PPV、
F1、FP/30 s、FN/30 s、timing error median/p95，并按 record 和噪声分层。容差和一对一
匹配算法必须写入报告。

### Beat 分类

逐 beat 报告 PAC/PVC precision、recall、F1，premature detection 指标，完整 confusion
matrix、Uncertain rate/coverage、selective accuracy 和 false alerts/30 s。不得删除
Uncertain 后只展示覆盖子集的漂亮结果。

### 防泄漏

- 按 patient/record 切分 development 与 held-out test。
- 阈值只在 development set 调整；冻结决策后才运行 held-out test。
- 私有 Apple Watch 样本不能同时用于逐例调参与最终准确率。
- 公开动态 ECG 的结果必须标为 public-dataset validation，不能改称 Apple Watch accuracy。

## 真机验收边界

模拟器或 mock 可测试 UI 状态和 mapper，但不能证明：HealthKit 授权语义、measurement
完整性、真实 sampling metadata、Apple Watch 波形兼容性或端到端导出一致性。真机步骤见
[NEEDS_MACOS_VALIDATION.md](../NEEDS_MACOS_VALIDATION.md)。
