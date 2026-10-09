# Mac 打包与测试清单 — v0.5.0 (6) MVP

本版在 Windows 上整理完成：Python 工具与工程配置测试 48/48 通过，App 算法的 NumPy 镜像已在
MIT-BIH 上复测；**Swift 源码尚未在本版本编译**，请按下列顺序在 Mac 上跑一遍并记录结果。

历史记录（供对照）：macOS 26.7 / Xcode 26.6 (17F113，位于 `~/Downloads/Xcode.app`) 曾通过
ECGCore 7 项测试、App/测试 target 构建，并在 iPhone 17 Pro / iOS 26.5 模拟器上运行 v0.3.0。

### 2026-10-07 新增：跨记录分析、筛选与批注

本轮实际执行 `python -m unittest Tools.Validation.tests.test_ios_project_configuration -v`，
10/10 工程配置测试通过；`git diff --check` 通过。Windows 没有 Swift/Xcode，下面新增的
Swift 功能测试和 UI 验收均未执行，不能据此声称 App 已编译或真机通过。

新增源码：`ECGAnnotation.swift`、`ECGAnnotationStore.swift`、`ECGRecordInsights.swift`、
`ECGRecordFilterView.swift`、`ECGAnnotationView.swift`，以及 Swift Charts 概览。新增
`ECGRecordInsightsTests.swift` 的 14 项测试和 repository 全历史查询测试已加入 Xcode target。

在 Mac 跑本文件下方的 core/app 测试及 scheme 构建后，重点验收：

1. 概览首次启动即逐条筛查；日期切换正确，按日／按月图表、心率均值、候选总数、分析
   覆盖情况与标签分布一致。待分析、无法分析和失败不能被统计为零候选。
2. 零数据／无授权、全为拒判、没有心率、仅单条记录的图表状态；合成数据不进入统计。
3. 超过 200 条 HealthKit ECG 仍能查到早期记录；大量历史数据下检查加载与筛查响应。
4. 全部、近 7/30 天、自定义范围包含结束日期整天；反向日期不匹配；日期、结果、标签与
   文字搜索组合正确。多个标签为 OR；从概览标签点击跳转后正确保留日期及标签。
5. 详情多选症状、“没有不适”互斥、自定义标签去重与复用、自由批注、保存／取消、单条
   清空并保存。返回列表／概览立即更新，退出并重启后真实批注仍存在。
6. Apple 症状与本应用自述感受分开；批注不改变模型候选、波形或原有导出。
7. 合成示例批注只在当前进程内保留。设置清除全部批注后，真实 HealthKit ECG 仍存在，
   搜索及概览无残留标签。已有筛选无匹配时可重置。
8. 真机检查 `WatchBeatAnnotations` 目录排除备份、批注文件 protection 为 complete；锁定
   或读取失败时禁止覆盖，保存失败保留草稿并可重试。损坏文件不能被静默重建。
9. 中英文切换、VoiceOver、最大文字尺寸、小屏及深浅色下的筛选、标签、编辑表单和图表。

### 2026-10-07 界面布局统一（未编译）

只改界面，不改模型、筛选逻辑和存储。`AppStyle.swift` 去掉半透明 `watchBeatCard()`，全 App
统一使用不透明的 `watchBeatPanel()`，背景改为系统分组底色 + 顶部淡粉色。新增 `WatchBeatFlowLayout`
（自定义 `Layout`，标签按内容宽度换行）、`WatchBeatChip`、`WatchBeatIconBadge`、
`WatchBeatGroupHeader`、`WatchBeatFootnote`；`ECGListView.swift` 新增 `ECGEmptyStateCard`。

- 概览：合并重复指标为 2×2 数值卡；分析覆盖改为分段条 + 图例；趋势用分段控件切换
  “记录数（有候选为黄色堆叠）/平均心率”；免责声明改为页脚。
- 数据：搜索框 + 筛选按钮 + 日期分段直接放在页面上，“结果与标签”改为底部弹窗，已选条件
  以可移除标签显示；记录按月分组；行内显示日期、心率、Apple 分类与时长；有记录时示例移到底部。
- 详情：“感受与批注”移到分析结果之后、导出之前；编辑页标签改为胶囊多选，已有标签可一键添加。
- 设置分区重排并加图标；首次启动免责声明页重做，按钮固定在底部。

- 波形：去掉左侧 40pt 电压刻度栏，波形占满卡片宽度；mV 刻度改为图内左上的小标签（不拦截测量点击），
  最高刻度带 “mV” 单位。全段预览的视窗换算同步改为整宽。
- 概览趋势：点击柱形／心率点选中当天（或当月），图下显示记录数、有候选记录数、平均心率和最多 5 条
  记录（可直接打开详情），并可跳到“数据”页按该日期筛选；再次点击或点 ✕ 取消。用的是
  `chartOverlay` + `ChartProxy.plotFrame` / `value(atX:as:)` 的点击手势，不影响页面上下滚动。

重点看：`WatchBeatFlowLayout` 的 `Layout` 一致性与尾随闭包调用、`Chart` 的
`foregroundStyle(by:)` 堆叠柱形和 `chartForegroundStyleScale`，以及 Form 中多个胶囊按钮
是否能分别点击。

### 2026-10-08 筛查结果本地缓存与趋势图分页（未编译）

本轮实际执行 `python -m unittest Tools.Validation.tests.test_ios_project_configuration -v`（10/10 通过）
和 `git diff --check`；Swift 未编译。

- 新文件 `Models/ECGScreeningCache.swift`（已写入 `project.pbxproj`，WatchBeatModels target）：
  `ECGScreeningCacheStorage` 协议、`ECGScreeningCacheFileStorage`、`ECGScreeningCacheIdentity`。
  `ECGScreeningSummary` 新增 `Codable`；批注文件写入路径抽成共用的 `ECGProtectedFile`。
- `ECGRepository` 新增 `screeningStorage` 注入、`cachedScreeningSummaries(for:)`、
  `flushScreeningCache()`、`clearScreeningCache()`；`ECGListViewModel` 先一次性填入已缓存结果，
  只对其余记录读取电压。`SettingsView` 改为 `init(listViewModel:)`，新增“清除已保存的筛查结果”。
- 概览趋势图去掉 `chartOverlay` 点击层，改用 iOS 17 的 `chartXSelection` + `chartGesture`
  (`SpatialTapGesture` → `proxy.selectXValue(at:)`)，并在超过 14 天／12 个月时启用
  `chartScrollableAxes`、`chartXVisibleDomain`、`chartScrollPosition(x:)`、
  `chartScrollTargetBehavior(.valueAligned(matching:majorAlignment:))`。
- `ECGRepositoryStateTests` 新增 7 项：重启后不重读电压、仅新增记录未缓存、全量刷新删除已移除记录
  （限量查询不删）、缓存暂不可读时不覆盖、清除、文件往返与算法变化失效、损坏文件视为空。

重点验收：

1. 首次启动逐条筛查；完全退出（上滑杀掉）再打开，概览“分析覆盖”立即完整、不再逐条转圈；
   新录一条 ECG 后下拉刷新，只有新记录显示筛查进度。
2. 在健康 App 删除一条 ECG 或关闭读取权限后刷新，统计中不再出现该记录。
3. 设置清除后返回，下次启动重新逐条筛查；真机检查 `Library/Caches/WatchBeatScreening` 排除备份、
   文件 protection 为 complete。
4. 近 30 天／全部且记录跨度超过 14 天（或按月超过 12 个月）时：趋势图默认显示最近一页、纵轴固定、
   左右滑动流畅且按天／月对齐、快速滑动按周／年对齐，横轴每页都有日期标签；上下滚动页面不被图表拦截。
5. 滑动后点击柱形／心率点，选中的是手指下的那天（重点确认滚动偏移后坐标没有错位）；再次点击取消。
   不足一页时图表与之前一样不可滑动，点击选择正常。切换日期范围后回到最近一页。

如果 `xcode-select` 仍指向 Command Line Tools，先执行：

```bash
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
```

## 1. 单元测试（约 2 分钟）

在仓库根目录：

```bash
bash Tools/run-core-tests.sh --parallel   # ECGCore：应为 15 项全部通过
bash Tools/run-app-tests.sh --parallel    # iOS 包：WatchBeatAppTests 全部通过
```

预期 ECGCore 15 项 = ECGSignalInspectorTests 5 项 + PublicContractTests 10 项：结果词汇、默认配置/版本 `1.0.1-rr-research`、输入契约、早搏检出与节律摘要、规则心律
0 候选、缺测拒判、不规则采样拒判、直流偏移不改变检测结果、**描述性 R–R/QRS 峰谷值（新增）**、
**QRS 峰谷测量缺测与边界（新增）**。
iOS 包覆盖内置示例的 35 个 R 峰 / 2 个疑似早搏候选，并新增列表摘要缓存、列表/详情请求
互不干扰及滚动秒数刻度测试；本轮新增示例描述性数值、marker 候选标记、最近采样点/局部峰谷查找、
测量读数（B − A 与心动周期换算）和 mV 刻度测试。

本轮增加整段波形概览的窗口换算测试：任意时间点定位、手动滚动、首尾边界、缩放、短记录与无效几何。
Windows 环境无法运行 Swift 测试，需在 Mac 上执行上述命令。

**本轮未在 Mac 上编译过的新代码（请重点看编译报错）：** `ECGWaveformView.swift`（重写）、
新文件 `ECGCaliperView.swift` 与 `ECGCore/.../Signal/ECGQRSAmplitude.swift`（均已写入
`project.pbxproj`）、`SettingsView` 研究调试开关、`ECGAnalysisResultView` 可点击候选。
详情页布局重排：`AppStyle.swift` 新增 `watchBeatPanel()`、`WatchBeatMetricTile`、
`WatchBeatSectionTitle`；`ECGDetailView`、`ECGAnalysisResultView` 拆分卡片；`ECGWaveformView`
的缩放滑块改为 − / + 步进、图例说明移入“如何阅读波形”弹窗。

## 2. Xcode 构建与模拟器测试

```bash
cd iOS
xcodebuild -project WatchBeat.xcodeproj -scheme WatchBeatApp -showdestinations
xcodebuild -project WatchBeat.xcodeproj -scheme WatchBeatApp \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

本版从 Xcode 工程中移除了 `BeatClassifying.swift`、`ECGQuality.swift`、`RPeakDetecting.swift`
三个文件（`project.pbxproj` 已同步修改）。如果 Xcode 提示找不到文件，说明工程引用没对齐，请告诉我。

## 3. 真机打包安装

1. 打开 `iOS/WatchBeat.xcodeproj` → target **WatchBeatApp** → **Signing & Capabilities**。
2. 选择你的 Team，把 Bundle ID `com.watchbeat.WatchBeat` 改成你自己的唯一 ID；确认 HealthKit 仍在。
3. 选择已连接并解锁的 iPhone（iOS 17+，必要时开启开发者模式）→ **Run**。
4. 打包 Release：**Product → Archive**，或参见 [Docs/IPHONE_INSTALL.md](Docs/IPHONE_INSTALL.md)。

签名证书、描述文件、Team ID 不要提交到 Git。

## 4. 测速

详情页底部“技术详情（供专业人员参考）”展开后的 **分析耗时（Analysis time）**，是
`PrematureBeatAnalyzer.analyze` 单次执行的墙钟时间（不含 HealthKit 读取和绘图）。

1. **用 Release 构建测速**（Debug 未优化，Swift 数组代码会慢 5–20 倍）：Scheme → Edit Scheme →
   Run → Build Configuration 选 Release，或直接安装 Archive 出来的包。
2. 打开“数据 → 示例 ECG 数据”（30 秒、500 Hz、15,000 点），记录分析耗时。
   注意：示例在 App 启动时分析一次，这个数字包含冷启动开销，可重启 App 多看几次。
3. 打开 3–5 条真实 Apple Watch ECG（30 秒、约 512 Hz、约 15,360 点），逐条记录分析耗时。
   每次进入详情页都会重新读取并分析，可以反复进出取中位数。
4. 同时粗略感受“点进详情 → 波形出现”的总等待时间（主要是 HealthKit 读取）。

需要更细的剖析时，用 Instruments 的 Time Profiler 录一次“打开真实记录”的过程。

参考量级：算法主要是两次双向 biquad 滤波 + 每 30 秒块若干次排序，复杂度约 O(n log n)；
15k 点在现代 iPhone 的 Release 构建下预期为毫秒级。若超过 ~50 ms，请把数字发给我。

## 5. 真机功能验收

使用 Apple 健康中已有 Apple Watch 心电记录的 iPhone：

1. 首次安装先出现研究用途声明。
2. 主屏幕与 App 切换器显示新的 WatchBeat 图标，Xcode 不报告 AppIcon 尺寸或透明通道错误。
3. 申请权限时，健康权限页只出现心电**读取**，没有写入项。
4. 拒绝/不授权时，界面显示“没有可访问的心电”，不断言“已拒绝”。
5. 授权后列表加载正常；数据卡与背景有清晰对比，逐条显示筛查进度，有候选时显示候选数，
   无法分析时给出提示；零候选时不显示额外筛查徽标，保留 Apple 原始分类。
   仅 Apple 分类为窦性心律的记录显示“窦性心律”，不能用零候选覆盖房颤或无法判定分类。
   有候选的行使用**黄色**旗标、描边和左侧色条；无候选的行图标与左侧色条为**灰色**，不再显示粉红色。
   “这条记录无法分析”的徽标为灰色。
6. 打开一条记录，导航栏为小标题；页面顺序为：头部卡片 → 波形 → 疑似早搏候选（仅有候选时）→
   心率与节律 → 导出 → 技术详情（默认折叠）→ 底部声明文字。卡片与“数据”页同款不透明底色，
   卡片间距一致，不拥挤。头部卡片以开始日期时间为大标题，下方三格数字：平均心率、时长、
   疑似早搏候选数（有候选时为黄色，0 为普通灰底，载入中或无法分析为“—”），再下方为 Apple 分类和症状。
   核对这些值以及技术详情里的开始时间、采样率、声明测量数，均与“健康”App 一致。输入契约、模型、
   算法版本、分析耗时和测量完整性只出现在技术详情里。中文声明文字不再在句中断行。
7. 详情页默认**不**显示模型 R 峰竖线和候选竖线；上方 R–R 间期正常显示，候选处有黄色底色、
   `#序号 精确秒数`，其前方偏短的 R–R 数字为黄色胶囊；或给出具体的拒判原因。横向滚动时下方秒数
   坐标轴同步移动，左侧 mV 刻度保持固定。设置 › 研究调试 打开两个开关后，橙色 R 峰线与黄色候选
   粗线出现，关闭后消失。
   - 候选导航条的 ‹ › 能逐个把候选滚动到**屏幕中央**，中央秒数与导航条显示的秒数一致（例如 19 秒的
     候选要落在 19 秒处，而不是 10 秒左右），并加深底色；在“分析结果”卡片里点某个候选，页面回到
     波形并跳到该候选；定位后点时间缩放的 + / −，候选仍保持在中央。
   - 细节波形**下方**的“全段预览”一次显示完整 30 秒（其他时长按真实时间范围绘制），首尾时间均可见。
     在概览上点击或拖动任意位置，上方细节窗口实时定位到对应时间；无候选记录也可操作。
     蓝色选框与“当前 x–y 秒”随上方手动滑动、时间轴缩放、候选跳转同步更新；概览本身始终显示全段，
     不随时间或电压缩放改变范围。拖到最左/最右时，细节窗口停在记录首尾，不留空白。
     黄色标记与候选位置一致；概览拖动不放置或改变测量点。VoiceOver 上下轻扫可逐窗口导航。
   - 波形下方一行缩放控件：时间 ↔ 1×–8×、电压 ↕ 1×–4× 两组 − / + 步进，到上下限时对应按钮置灰；
     最右 ↺ 在 1×/1× 时置灰，缩放后可一键复位。VoiceOver 选中步进器后上下轻扫可调整。
   - 测量、R–R 间期、峰谷电压差三个开关为**纯图标小按钮，位于“波形”标题右侧**，开启时有着色背景；
     VoiceOver 能读出各自名称。标题最右的 ⓘ 打开“如何阅读波形”半屏说明（坐标轴、缩放、全段预览、
     R–R、候选、峰谷电压差、测量、采样点数），可上拉到全屏，点“完成”关闭。
   - 波形卡片底部只显示一行颜色图例（R–R 间期、疑似早搏候选、峰谷电压差，按开关显示），窄屏时自动换成竖排。
   - 电压缩放 1×–4×：图表变高、R 峰之间的幅度差被放大，mV 刻度同步变密。
   - “峰谷电压差”开关同时控制纵轴电压数字（含 mV 单位）及每个 R 峰旁的青色竖括号和数值；
     关闭后两者一起隐藏，重新开启后恢复。没有可计算峰谷差的记录也能用此按钮控制纵轴数值。
     开关状态在重新进入详情后保持；缩放、滚动、网格与测量工具仍正常。峰谷差数值与分析 JSON 中
     `qrsPeakToTroughMillivolts` 一致；示例 ECG 正常搏约 1.27 mV，PVC 样搏约 1.72 mV。
   - “测量”开关：依次点击波形放置 A、B；拖动圆点时页面不滚动、其他位置仍可左右滑动；
     ‹ › 逐采样点移动、“吸附峰/谷”跳到 ±40 ms 内极值；读数为 B − A 的 Δt（ms）与 ΔV（mV），
     Δt 在 250–3000 ms 时显示换算次/分；关闭“贴合波形”后可把点放在任意高度。
   - 深色模式下黄色文字（候选秒数、旗标）清晰可读。
8. 有候选时单独一张“疑似早搏候选”卡片：右上角黄色计数，每行为序号圆点（与波形上 #序号一致）、
   精确秒数、RR 比值和定位图标，点击可定位；超过 8 个时提示用 ‹ › 查看其余。
   “心率与节律”卡片以三格数字显示中位心率、R–R 中位数、R–R 四分位距，有候选时再列候选占比；
   零候选时不出现候选卡片和候选占比，不再出现“未标记疑似早搏候选”文案。
   中位心率与 Apple 元数据平均心率接近但不必完全相同，界面明确声明它不是临床 HRV。
   同卡片底部“更多节律与波形描述”默认折叠，展开后显示最短/最长 R–R、逐搏心率范围、>2 秒间期数、
   相邻候选对数与 QRS 峰谷电压差（中位、范围），并附非诊断说明。无法分析时显示灰色“这段记录无法分析”卡片和原因。
9. 快速切换记录，旧记录结果不会覆盖当前页面；列表后台筛查也不会让已打开的详情失效。
10. 导出卡片为三行列表（分析结果 JSON、原始波形 CSV、记录元数据 JSON），点任一行先弹出确认再分享。
    分享原始 CSV / metadata JSON / analysis JSON：CSV 行数、顺序、时间戳与 HealthKit 测量一致；
    JSON 的 `dataSource` 为 `healthKit`，analysis 含 `watchbeat.rr-summary.v1`；文件名和内容中没有
    HealthKit UUID。
11. 设置页“版本”显示 `0.5.0 (6)`。
12. 抽查签名产物包含 `com.apple.developer.healthkit`，且没有网络上传行为。

内置合成示例只用于教程和测速，不能替代任何真机 HealthKit 验收项。

## 6. 记录方式

记录设备型号/系统版本、Xcode/Swift 版本、提交号、测试通过数、分析耗时（中位数）和脱敏错误码。
不要把心电波形、HealthKit 标识、精确采集时间、Apple 账号或设备标识写进仓库。
