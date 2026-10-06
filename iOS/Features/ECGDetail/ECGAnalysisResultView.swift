import ECGCore
import Foundation
import SwiftUI

/// Presents one immutable `ECGAnalysisReport`; no algorithm rule is reimplemented in the UI.
struct ECGAnalysisResultView: View {
    let report: ECGAnalysisReport
    let analysisDurationSeconds: Double
    /// Called with a candidate's time so the detail page can bring it into view on the waveform.
    var onSelectCandidate: ((Double) -> Void)?
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                language.text("On-device research analysis", "本机研究分析"),
                systemImage: "waveform.path.ecg"
            )
            .font(.headline)

            row(language.text("Input contract", "输入契约"), report.inputFormat)
            row(language.text("Model", "模型"), report.detectorIdentifier)
            row(language.text("Algorithm version", "算法版本"), report.algorithmVersion)
            row(
                language.text("Analysis time", "分析耗时"),
                String(format: "%.1f ms", analysisDurationSeconds * 1_000)
            )

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
        row(language.text("Detected R peaks", "检测到的 R 峰"), "\(report.summary.rPeakCount)")
        row(
            language.text("Premature candidates", "疑似早搏候选"),
            "\(report.summary.prematureCandidateCount)"
        )

        if let metrics = report.rhythmMetrics {
            Divider()
            Text(language.text("Rate and timing summary", "心率与节律摘要"))
                .font(.subheadline.bold())
            row(
                language.text("Median detected rate", "检测中位心率"),
                String(format: "%.0f BPM", metrics.medianDetectedHeartRateBPM)
            )
            row(
                language.text("Median R–R interval", "R–R 间期中位数"),
                String(format: "%.0f ms", metrics.medianRRMilliseconds)
            )
            row(
                language.text("R–R interquartile range", "R–R 四分位距"),
                String(format: "%.0f ms", metrics.rrInterquartileRangeMilliseconds)
            )
            row(
                language.text("Usable R–R intervals", "可用 R–R 间期"),
                "\(metrics.plausibleRRIntervalCount)"
            )
            row(
                language.text("Candidate share", "候选占比"),
                String(
                    format: "%.1f%% (%d/%d)",
                    metrics.prematureCandidateFraction * 100,
                    report.summary.prematureCandidateCount,
                    report.summary.classifiedBeatCount
                )
            )
            Text(language.text(
                "Calculated from plausible intervals between model-detected R peaks. " +
                    "R–R spread is not a clinical HRV measurement.",
                "仅根据模型检测到的 R 峰之间可信间期计算；R–R 离散程度不属于临床 HRV 指标。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
        }

        if let descriptors = report.recordingDescriptors {
            descriptorContent(descriptors)
            Divider()
        }

        if report.summary.prematureCandidateCount == 0 {
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
                    "The model flagged possible premature beats for review.",
                    "模型标记了疑似早搏候选，供你复核。"
                ),
                systemImage: "flag.fill"
            )
            .foregroundStyle(Color.watchBeatAttentionText)

            ForEach(prematureCandidates.prefix(8), id: \.sampleIndex) { beat in
                candidateRow(beat)
            }
            if prematureCandidates.count > 8 {
                Text(language.text(
                    "+ \(prematureCandidates.count - 8) more in the analysis JSON",
                    "另有 \(prematureCandidates.count - 8) 个，见分析结果 JSON"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var refusedContent: some View {
        Label(
            language.text("This recording was not analyzed", "这段记录未进行分析"),
            systemImage: "nosign"
        )
        .foregroundStyle(.orange)
        if let reason = report.reason {
            Text(reasonText(reason))
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
                    Label(language.text("Show", "定位"), systemImage: "scope")
                        .font(.caption.bold())
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
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
        row(
            language.text("Shortest / longest R–R", "最短 / 最长 R–R"),
            String(
                format: "%.0f / %.0f ms",
                descriptors.shortestRRMilliseconds,
                descriptors.longestRRMilliseconds
            )
        )
        if let lowest = descriptors.minimumInstantaneousHeartRateBPM,
           let highest = descriptors.maximumInstantaneousHeartRateBPM {
            row(
                language.text("Beat-to-beat rate range", "逐搏心率范围"),
                String(format: "%.0f–%.0f BPM", lowest, highest)
            )
        }
        row(
            language.text("R–R intervals over 2 s", "超过 2 秒的 R–R 间期"),
            "\(descriptors.longRRIntervalCount)"
        )
        row(
            language.text("Back-to-back candidate pairs", "相邻出现的候选（成对）"),
            "\(descriptors.consecutiveCandidatePairCount)"
        )
        if let median = descriptors.medianQRSPeakToTroughMillivolts,
           let lowest = descriptors.minimumQRSPeakToTroughMillivolts,
           let highest = descriptors.maximumQRSPeakToTroughMillivolts {
            row(
                language.text("QRS peak-to-trough (median)", "QRS 峰谷电压差（中位）"),
                String(format: "%.2f mV", median)
            )
            row(
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

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func reasonText(_ reason: ECGAnalysisReason) -> String {
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
