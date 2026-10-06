import ECGCore
import Foundation
import SwiftUI

/// User-facing results of one immutable `ECGAnalysisReport`: candidates, rate summary and
/// descriptive values. How the analysis ran lives in `ECGAnalysisTechnicalDetails`, shown at the
/// bottom of the page for professionals. No algorithm rule is reimplemented in the UI.
struct ECGAnalysisResultView: View {
    let report: ECGAnalysisReport
    /// Called with a candidate's time so the detail page can bring it into view on the waveform.
    var onSelectCandidate: ((Double) -> Void)?
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(language.text("Results", "分析结果"), systemImage: "waveform.path.ecg")
                .font(.headline)

            switch report.status {
            case .analyzed:
                analyzedContent
            case .notAnalyzed:
                refusedContent
            }

            Text(language.text(
                "Research screening only. A candidate is not a diagnosis, and zero candidates " +
                    "does not rule out an arrhythmia.",
                "仅供研究筛查。候选结果不等于诊断；候选数为零也不能排除心律失常。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .watchBeatCard()
    }

    @ViewBuilder
    private var analyzedContent: some View {
        if prematureCandidates.isEmpty {
            Label(
                language.text(
                    "No premature candidate was flagged in this recording.",
                    "这段记录中未标记出疑似早搏候选。"
                ),
                systemImage: "info.circle"
            )
            .foregroundStyle(.secondary)
        } else {
            Label(
                language.text(
                    "\(prematureCandidates.count) premature candidate(s) — tap one to show it on the waveform",
                    "\(prematureCandidates.count) 处疑似早搏候选，点击可在波形上定位"
                ),
                systemImage: "flag.fill"
            )
            .font(.subheadline.bold())
            .foregroundStyle(Color.watchBeatAttentionText)

            ForEach(prematureCandidates.prefix(8), id: \.sampleIndex) { beat in
                candidateRow(beat)
            }
            if prematureCandidates.count > 8 {
                Text(language.text(
                    "+ \(prematureCandidates.count - 8) more — use ‹ › above the waveform",
                    "另有 \(prematureCandidates.count - 8) 个，可用波形上方的 ‹ › 逐个查看"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }

        if let metrics = report.rhythmMetrics {
            Divider()
            Text(language.text("Rate and rhythm", "心率与节律"))
                .font(.subheadline.bold())
            ECGInfoRow(
                language.text("Median heart rate", "中位心率"),
                String(format: "%.0f BPM", metrics.medianDetectedHeartRateBPM)
            )
            ECGInfoRow(
                language.text("Median R–R interval", "R–R 间期中位数"),
                String(format: "%.0f ms", metrics.medianRRMilliseconds)
            )
            ECGInfoRow(
                language.text("R–R interquartile range", "R–R 四分位距"),
                String(format: "%.0f ms", metrics.rrInterquartileRangeMilliseconds)
            )
            ECGInfoRow(
                language.text("Candidate share", "候选占比"),
                String(
                    format: "%.1f%% (%ld/%ld)",
                    metrics.prematureCandidateFraction * 100,
                    report.summary.prematureCandidateCount,
                    report.summary.classifiedBeatCount
                )
            )
            Text(language.text(
                "R–R spread describes this recording only; it is not a clinical HRV measurement.",
                "R–R 离散程度只描述这一段记录，不属于临床 HRV 指标。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let descriptors = report.recordingDescriptors {
            Divider()
            descriptorContent(descriptors)
        }
    }

    @ViewBuilder
    private var refusedContent: some View {
        Label(
            language.text("This recording could not be analyzed", "这段记录无法分析"),
            systemImage: "nosign"
        )
        .foregroundStyle(.orange)
        if let reason = report.reason {
            Text(ECGAnalysisReasonText.text(for: reason, language: language))
                .font(.caption)
        }
    }

    @ViewBuilder
    private func candidateRow(_ beat: ECGAnalyzedBeat) -> some View {
        let ratio = beat.prematurityRatio.map { String(format: "%.2f", $0) } ?? "—"
        let text = Text(language.text(
            String(format: "%.3f s · RR ratio %@", beat.timeSeconds, ratio),
            String(format: "%.3f 秒 · RR 比值 %@", beat.timeSeconds, ratio)
        ))
        .font(.caption.monospacedDigit())

        if let onSelectCandidate {
            Button {
                onSelectCandidate(beat.timeSeconds)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.watchBeatAttentionText)
                    text
                    Spacer(minLength: 8)
                    Image(systemName: "scope")
                        .font(.body)
                        .foregroundStyle(Color.watchBeatAttentionText)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Color.watchBeatAttention.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(language.text("Shows this candidate on the waveform", "在波形上定位这个候选"))
        } else {
            text
        }
    }

    @ViewBuilder
    private func descriptorContent(_ descriptors: ECGRecordingDescriptors) -> some View {
        Text(language.text("More rhythm and waveform descriptors", "更多节律与波形描述"))
            .font(.subheadline.bold())
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
