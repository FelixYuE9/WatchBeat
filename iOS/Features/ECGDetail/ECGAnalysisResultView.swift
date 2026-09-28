import ECGCore
import Foundation
import SwiftUI

/// Presents one immutable `ECGAnalysisReport`; no algorithm rule is reimplemented in the UI.
struct ECGAnalysisResultView: View {
    let report: ECGAnalysisReport
    let analysisDurationSeconds: Double
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
                    "The model flagged possible premature beats.",
                    "模型标记了疑似早搏候选。"
                ),
                systemImage: "exclamationmark.circle"
            )
            .foregroundStyle(.orange)

            ForEach(prematureCandidates.prefix(8), id: \.sampleIndex) { beat in
                let ratio = beat.prematurityRatio.map { String(format: "%.2f", $0) } ?? "—"
                Text(language.text(
                    String(format: "· %.3f s · RR ratio %@", beat.timeSeconds, ratio),
                    String(format: "· %.3f 秒 · RR 比值 %@", beat.timeSeconds, ratio)
                ))
                .font(.caption.monospacedDigit())
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
