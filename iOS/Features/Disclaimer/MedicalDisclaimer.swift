import Foundation

/// Non-diagnostic wording required on first launch and on every result page.
public enum MedicalDisclaimer {
    public static let acceptanceKey = "hasAcceptedResearchDisclaimer"

    public static let english = """
        This app is intended for informational and research purposes only. It does not provide a \
        medical diagnosis. Possible PAC/PVC-like classifications may be incorrect. Do not use this \
        app for emergency or treatment decisions.
        """

    public static let chinese = """
        本项目仅用于信息展示和研究，不提供医疗诊断。未来显示的“疑似房性早搏样心搏”或“疑似室性\
        早搏样心搏”可能不正确，不得用于急症判断、治疗或用药决策。出现胸痛、晕厥、明显呼吸困难、\
        持续严重心悸或其他严重症状时，应及时寻求专业医疗帮助。
        """
}
