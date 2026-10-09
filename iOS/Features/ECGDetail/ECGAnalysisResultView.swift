import Charts
import ECGCore
import Foundation
import SwiftUI

/// User-facing results of one immutable `ECGAnalysisReport`, as separate cards: candidates first,
/// then rate and rhythm. How the analysis ran lives in `ECGAnalysisTechnicalDetails`, shown at the
/// bottom of the page for professionals. No algorithm rule is reimplemented in the UI.
struct ECGAnalysisResultView: View {
    let report: ECGAnalysisReport
    /// Called with a candidate's time so the detail page can bring it into view on the waveform.
    var onSelectCandidate: ((Double) -> Void)?
    @State private var showsDescriptors = false
    @Environment(\.appLanguage) private var language

    private let visibleCandidateLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch report.status {
            case .analyzed:
                if !prematureCandidates.isEmpty {
                    candidatesCard
                }
                if report.rhythmMetrics != nil || report.recordingDescriptors != nil {
                    rhythmCard
                }
                if let metrics = report.rrVariability {
                    ECGRRVariabilityCard(metrics: metrics, beats: report.beats)
                }
            case .notAnalyzed:
                refusedCard
            }
        }
    }

    // MARK: - Candidates

    private var candidatesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(language.text("Premature candidates", "疑似早搏候选"))
                        .font(.headline)
                } icon: {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(Color.watchBeatAttentionText)
                }
                Spacer(minLength: 8)
                Text("\(prematureCandidates.count)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(Color.watchBeatAttentionText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.watchBeatAttention.opacity(0.2), in: Capsule())
            }
            if onSelectCandidate != nil {
                Text(language.text(
                    "Numbers match the # labels on the waveform. Tap one to show it there.",
                    "序号与波形上的 # 标记一致，点击即可在波形上定位。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(
                    Array(prematureCandidates.prefix(visibleCandidateLimit).enumerated()),
                    id: \.element.sampleIndex
                ) { index, beat in
                    if index > 0 {
                        Divider().padding(.leading, 38)
                    }
                    candidateRow(beat, number: index + 1)
                }
            }

            if prematureCandidates.count > visibleCandidateLimit {
                let remaining = prematureCandidates.count - visibleCandidateLimit
                Text(language.text(
                    "+ \(remaining) more — use ‹ › above the waveform",
                    "另有 \(remaining) 个，可用波形上方的 ‹ › 逐个查看"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .watchBeatPanel()
    }

    @ViewBuilder
    private func candidateRow(_ beat: ECGAnalyzedBeat, number: Int) -> some View {
        let ratio = beat.prematurityRatio.map { String(format: "%.2f", $0) } ?? "—"
        let content = HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(Color.watchBeatAttentionText)
                .frame(width: 26, height: 26)
                .background(Color.watchBeatAttention.opacity(0.22), in: Circle())
            Text(language.text(
                String(format: "%.3f s", beat.timeSeconds),
                String(format: "%.3f 秒", beat.timeSeconds)
            ))
            .font(.subheadline.monospacedDigit())
            Spacer(minLength: 8)
            Text(language.text("RR ratio \(ratio)", "RR 比值 \(ratio)"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if onSelectCandidate != nil {
                Image(systemName: "scope")
                    .foregroundStyle(Color.watchBeatAttentionText)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())

        if let onSelectCandidate {
            Button {
                onSelectCandidate(beat.timeSeconds)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityHint(language.text("Shows this candidate on the waveform", "在波形上定位这个候选"))
        } else {
            content
        }
    }

    // MARK: - Rate and rhythm

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WatchBeatSectionTitle(language.text("Rate and rhythm", "心率与节律"), systemImage: "heart.text.square")

            if let metrics = report.rhythmMetrics {
                HStack(spacing: 10) {
                    WatchBeatMetricTile(
                        value: String(format: "%.0f BPM", metrics.medianDetectedHeartRateBPM),
                        label: language.text("Median rate", "中位心率")
                    )
                    WatchBeatMetricTile(
                        value: String(format: "%.0f ms", metrics.medianRRMilliseconds),
                        label: language.text("Median R–R", "R–R 中位数")
                    )
                    WatchBeatMetricTile(
                        value: String(format: "%.0f ms", metrics.rrInterquartileRangeMilliseconds),
                        label: language.text("R–R IQR", "R–R 四分位距")
                    )
                }
                .fixedSize(horizontal: false, vertical: true)

                if !prematureCandidates.isEmpty {
                    ECGInfoRow(
                        language.text("Candidate share", "候选占比"),
                        String(
                            format: "%.1f%% (%ld/%ld)",
                            metrics.prematureCandidateFraction * 100,
                            report.summary.prematureCandidateCount,
                            report.summary.classifiedBeatCount
                        )
                    )
                }
                Text(language.text(
                    "R–R spread describes this recording only; it is not a clinical HRV measurement.",
                    "R–R 离散程度只描述这一段记录，不属于临床 HRV 指标。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let descriptors = report.recordingDescriptors {
                Divider()
                DisclosureGroup(isExpanded: $showsDescriptors) {
                    descriptorContent(descriptors)
                        .padding(.top, 10)
                } label: {
                    Text(language.text("More rhythm and waveform descriptors", "更多节律与波形描述"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .watchBeatPanel()
    }

    private func descriptorContent(_ descriptors: ECGRecordingDescriptors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ECGInfoRow(
                language.text("Shortest / longest R–R", "最短 / 最长 R–R"),
                String(
                    format: "%.0f / %.0f ms",
                    descriptors.shortestRRMilliseconds,
                    descriptors.longestRRMilliseconds
                )
            )
            if let lowest = descriptors.minimumInstantaneousHeartRateBPM,
               let highest = descriptors.maximumInstantaneousHeartRateBPM {
                ECGInfoRow(
                    language.text("Beat-to-beat rate range", "逐搏心率范围"),
                    String(format: "%.0f–%.0f BPM", lowest, highest)
                )
            }
            ECGInfoRow(
                language.text("R–R intervals over 2 s", "超过 2 秒的 R–R 间期"),
                "\(descriptors.longRRIntervalCount)"
            )
            ECGInfoRow(
                language.text("Back-to-back candidate pairs", "相邻出现的候选（成对）"),
                "\(descriptors.consecutiveCandidatePairCount)"
            )
            if let median = descriptors.medianQRSPeakToTroughMillivolts,
               let lowest = descriptors.minimumQRSPeakToTroughMillivolts,
               let highest = descriptors.maximumQRSPeakToTroughMillivolts {
                ECGInfoRow(
                    language.text("QRS peak-to-trough (median)", "QRS 峰谷电压差（中位）"),
                    String(format: "%.2f mV", median)
                )
                ECGInfoRow(
                    language.text("QRS peak-to-trough range", "QRS 峰谷电压差范围"),
                    String(format: "%.2f–%.2f mV", lowest, highest)
                )
            }
            Text(language.text(
                "Descriptive values for this single-lead recording only. A long R–R interval can also " +
                    "come from a missed R peak. Peak-to-trough voltage changes with wrist contact and " +
                    "arm position and is not a clinical voltage criterion.",
                "仅描述这一段单导联记录。超过 2 秒的间期也可能来自漏检的 R 峰；峰谷电压差会随手腕接触和" +
                    "手臂姿势变化，不能作为临床电压诊断标准。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Not analyzed

    private var refusedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            WatchBeatSectionTitle(
                language.text("This recording could not be analyzed", "这段记录无法分析"),
                systemImage: "nosign"
            )
            if let reason = report.reason {
                Text(ECGAnalysisReasonText.text(for: reason, language: language))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .watchBeatPanel()
    }

    private var prematureCandidates: [ECGAnalyzedBeat] {
        report.beats.filter { $0.classification == .prematureUncertain }
    }
}

/// How the report was produced. Shown only inside the page's collapsed technical section.
struct ECGAnalysisTechnicalDetails: View {
    let report: ECGAnalysisReport
    let analysisDurationSeconds: Double
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("Analysis", "分析信息"))
                .font(.subheadline.bold())
            ECGInfoRow(language.text("Input contract", "输入契约"), report.inputFormat)
            ECGInfoRow(language.text("Model", "模型"), report.detectorIdentifier)
            ECGInfoRow(language.text("Algorithm version", "算法版本"), report.algorithmVersion)
            ECGInfoRow(
                language.text("Analysis time", "分析耗时"),
                String(format: "%.1f ms", analysisDurationSeconds * 1_000)
            )
            if report.status == .analyzed {
                ECGInfoRow(language.text("Detected R peaks", "检测到的 R 峰"), "\(report.summary.rPeakCount)")
                ECGInfoRow(
                    language.text("Classified beats", "已分类心搏"),
                    "\(report.summary.classifiedBeatCount)"
                )
                if let metrics = report.rhythmMetrics {
                    ECGInfoRow(
                        language.text("Usable R–R intervals (300–2,000 ms)", "可用 R–R 间期（300–2000 ms）"),
                        "\(metrics.plausibleRRIntervalCount)"
                    )
                }
                ECGInfoRow(
                    language.text("Prematurity threshold", "提前判定阈值"),
                    language.text(
                        String(format: "R–R < %.0f%% of local median", report.parameters.prematurityThreshold * 100),
                        String(format: "R–R < 局部中位数的 %.0f%%", report.parameters.prematurityThreshold * 100)
                    )
                )
            }
            if let reason = report.reason {
                ECGInfoRow(language.text("Refusal code", "拒判代码"), reason.rawValue)
            }
        }
    }
}

/// One label/value line used by the result and technical cards.
struct ECGInfoRow: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

enum ECGAnalysisReasonText {
    static func text(for reason: ECGAnalysisReason, language: AppLanguage) -> String {
        switch reason {
        case .missingOrMismatchedSamples:
            return language.text(
                "The timestamp and voltage arrays are empty or do not align.",
                "时间戳与电压数组为空或没有逐点对齐。"
            )
        case .missingOrNonFiniteSamples:
            return language.text(
                "At least one original timestamp or Lead I voltage is missing or invalid.",
                "至少一个原始时间戳或 I 导联电压缺失或无效。"
            )
        case .invalidTimestamps:
            return language.text(
                "Timestamps are not finite and strictly increasing.",
                "时间戳不是有限且严格递增的。"
            )
        case .unsupportedSamplingOrDuration:
            return language.text(
                "The recording duration, sampling rate or timestamp regularity is unsupported.",
                "记录时长、采样率或时间戳规律性不受支持。"
            )
        case .unsupportedConfiguration:
            return language.text(
                "This build contains an unsupported analysis configuration.",
                "此版本包含不受支持的分析配置。"
            )
        case .insufficientDetectedBeats:
            return language.text(
                "Too few reliable R peaks were found to establish a local RR baseline.",
                "可靠 R 峰数量不足，无法建立局部 RR 基线。"
            )
        case .insufficientReliableRRContext:
            return language.text(
                "Detected peaks did not provide enough plausible RR intervals for classification.",
                "检测到的峰没有提供足够可信的 RR 间期用于分类。"
            )
        }
    }
}

/// RR metrics and plots share the same range mask from ECGCore, without inventing NN intervals.
private struct ECGRRVariabilityCard: View {
    let metrics: ECGRRVariabilityMetrics
    let beats: [ECGAnalyzedBeat]
    @Environment(\.appLanguage) private var language
    @State private var showsPlots = false

    private struct HistogramBin: Identifiable {
        let lower: Int
        let count: Int
        var id: Int { lower }
    }

    private struct RRPair: Identifiable {
        let id: Int
        let previous: Double
        let current: Double
    }

    private var intervals: [Double?] { ECGRRVariabilityMetrics.plausibleIntervals(from: beats) }

    private var histogram: [HistogramBin] {
        // Avoid splitting a constant RR at a bin edge due only to timestamp roundoff.
        let counts = Dictionary(grouping: intervals.compactMap { $0 }) { Int(floor(($0 + 1e-9) / 50)) * 50 }
        return counts.keys.sorted().map { HistogramBin(lower: $0, count: counts[$0]?.count ?? 0) }
    }

    private var pairs: [RRPair] {
        let values = intervals
        guard values.count > 1 else { return [] }
        return (1..<values.count).compactMap { index in
            guard let previous = values[index - 1], let current = values[index] else { return nil }
            return RRPair(id: index, previous: previous, current: current)
        }
    }

    private var plotDomain: ClosedRange<Double> {
        let values = intervals.compactMap { $0 }
        return max(0, (values.min() ?? 300) - 50)...((values.max() ?? 2_000) + 50)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WatchBeatSectionTitle(
                language.text("R–R variability", "R–R 变异统计"),
                systemImage: "chart.xyaxis.line"
            )
            ECGInfoRow(language.text("Mean R–R", "平均 R–R"), String(format: "%.1f ms", metrics.meanRRMilliseconds))
            ECGInfoRow(language.text("R–R standard deviation (SDRR)", "R–R 标准差 SDRR"), String(format: "%.1f ms", metrics.sdrrMilliseconds))
            ECGInfoRow(language.text("R–R coefficient of variation", "R–R 变异系数 CV"), String(format: "%.1f%%", metrics.coefficientOfVariationPercent))
            ECGInfoRow(
                language.text("Successive difference RMS (RR)", "相邻差值均方根 RMSSD_RR"),
                metricText(metrics.successiveDifferenceRMSMilliseconds, format: "%.1f ms")
            )
            ECGInfoRow(
                language.text("Successive differences > 50 ms", "相邻差值 > 50 ms 的比例 pRR50"),
                metricText(metrics.successiveDifferenceOver50MillisecondsPercent, format: "%.1f%%")
            )
            Divider()
            ECGInfoRow(
                language.text("Recording length", "记录时长"),
                String(format: "%.1f s", metrics.recordingDurationSeconds)
            )
            ECGInfoRow(
                language.text("Included / detected R–R", "纳入 / 检测间期数"),
                "\(metrics.includedIntervalCount) / \(metrics.detectedIntervalCount)"
            )
            ECGInfoRow(language.text("Excluded intervals", "排除间期数"), "\(metrics.excludedIntervalCount)")
            ECGInfoRow(language.text("Original adjacent pairs", "原序列相邻间期对数"), "\(metrics.successivePairCount)")
            if metrics.candidateAdjacentIntervalCount > 0 {
                Text(language.text(
                    "\(metrics.candidateAdjacentIntervalCount) included interval(s) touch a premature candidate. This can raise variability and does not mean better recovery.",
                    "纳入间期中有 \(metrics.candidateAdjacentIntervalCount) 个连接疑似早搏候选，可能抬高变异数值，不表示恢复更好。"
                ))
                .font(.caption)
                .foregroundStyle(Color.watchBeatAttentionText)
            }
            Text(language.text(
                "Timing range: 300–2,000 ms; no artifact correction or confirmation of normal sinus beats. CV = SDRR / mean RR × 100%. These describe this recording, not clinical SDNN/HRV, a stress score or a diagnosis.",
                "纳入 300–2000 ms 的间期，未校正伪迹或确认正常窦性心搏。CV = SDRR / 平均 RR × 100%。仅描述本次记录，不等于临床 SDNN/HRV、压力评分或诊断。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            if metrics.recordingDurationSeconds < 300 {
                Text(language.text(
                    "Under 5 minutes: do not compare with standard 5-minute or 24-hour HRV reference values.",
                    "不足 5 分钟：不能与标准 5 分钟或 24 小时 HRV 参考值直接比较。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            DisclosureGroup(isExpanded: $showsPlots) {
                plots.padding(.top, 10)
            } label: {
                Text(language.text("R–R distribution and adjacent-pair plot", "R–R 分布与相邻间期散点图"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .watchBeatPanel()
    }

    private func metricText(_ value: Double?, format: String) -> String {
        value.map { String(format: format, $0) }
            ?? language.text("No adjacent pairs", "无相邻间期对")
    }

    private var plots: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("R–R histogram · 50 ms bins", "R–R 直方图 · 每格 50 ms"))
                .font(.caption.weight(.semibold))
            Chart(histogram) { bin in
                BarMark(
                    xStart: .value("R–R (ms)", bin.lower),
                    xEnd: .value("R–R (ms)", bin.lower + 50),
                    y: .value(language.text("Intervals", "间期数"), bin.count)
                )
                .foregroundStyle(Color.blue.opacity(0.7))
            }
            .chartXAxisLabel("R–R (ms)")
            .chartYAxisLabel(language.text("Count", "数量"))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 150)
            .accessibilityLabel(language.text("Distribution of included R–R intervals", "纳入间期的 R–R 分布"))

            if !pairs.isEmpty {
                Text(language.text("Poincaré · original adjacent R–R pairs", "Poincaré 散点图 · 原序列相邻 R–R"))
                    .font(.caption.weight(.semibold))
                Chart(pairs) { pair in
                    PointMark(
                        x: .value("RR(n) (ms)", pair.previous),
                        y: .value("RR(n+1) (ms)", pair.current)
                    )
                    .foregroundStyle(Color.blue.opacity(0.7))
                }
                .chartXScale(domain: plotDomain)
                .chartYScale(domain: plotDomain)
                .chartXAxisLabel("RR(n) (ms)")
                .chartYAxisLabel("RR(n+1) (ms)")
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                .frame(height: 170)
                .accessibilityLabel(language.text("Original adjacent R–R interval pairs", "原序列相邻 R–R 间期对"))
            }
            Text(language.text(
                "Excluded intervals leave gaps; adjacent-pair statistics and plots never join across them. Plot shape alone cannot identify AFib or a disease.",
                "排除间期保留断点，相邻统计和散点图不会跨断点配对。图形形状本身不能识别房颤或疾病。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
