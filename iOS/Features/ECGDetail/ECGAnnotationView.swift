import SwiftUI
import WatchBeatModels

struct ECGAnnotationView: View {
    let record: ECGRecord
    let source: ECGMeasurementSource
    @Environment(ECGAnnotationStore.self) private var store
    @Environment(\.appLanguage) private var language
    @State private var showsEditor = false

    private var isExample: Bool { source == .builtInSyntheticExample }
    private var annotation: ECGAnnotation {
        isExample ? store.exampleAnnotation : store.annotation(for: record.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                WatchBeatSectionTitle(language.text("Feelings and notes", "感受与批注"), systemImage: "text.bubble")
                Spacer(minLength: 8)
                if !annotation.isEmpty, !(store.hasLoadFailure && !isExample) {
                    Button {
                        showsEditor = true
                    } label: {
                        Label(language.text("Edit", "编辑"), systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }

            if store.hasLoadFailure && !isExample {
                HStack {
                    Text(language.text(
                        "Saved annotations could not be read. Retry before editing.",
                        "无法读取已保存的批注，请重试后再编辑。"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    Spacer(minLength: 8)
                    Button(language.text("Retry", "重试")) { store.reload() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else if annotation.isEmpty {
                Button {
                    showsEditor = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.pink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.text("How did you feel during this recording?", "记录期间感觉如何？"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(language.text(
                                "Add symptoms, your own tags or a note to remember the context.",
                                "选择当时的症状、添加自己的标签或文字批注，方便以后回顾。"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.pink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ECGAnnotationTags(tags: annotation.tags)
                if !annotation.note.isEmpty {
                    Text(annotation.note)
                        .font(.subheadline)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.watchBeatInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            Label(
                language.text(
                    isExample
                        ? "Example annotations last only for this app session."
                        : "Saved only on this iPhone. You can clear them in Settings.",
                    isExample ? "示例批注仅保留到本次应用关闭。" : "仅保存在此 iPhone，可在设置中清除。"
                ),
                systemImage: isExample ? "clock" : "lock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .watchBeatPanel()
        .sheet(isPresented: $showsEditor) {
            ECGAnnotationEditor(
                annotation: annotation,
                availableTags: isExample ? [] : Array(Set(store.annotations.values.flatMap(\.customTags))).sorted(),
                canSave: isExample || !store.hasLoadFailure
            ) { updated in
                if isExample { store.exampleAnnotation = updated.normalized; return true }
                return store.save(updated, for: record.id)
            }
        }
    }
}

/// Self-reported feelings and custom tags as wrapping chips.
struct ECGAnnotationTags: View {
    let tags: [ECGRecordTag]
    @Environment(\.appLanguage) private var language

    var body: some View {
        if !tags.isEmpty {
            WatchBeatFlowLayout {
                ForEach(tags) { tag in
                    WatchBeatChip(title: tag.title(in: language), systemImage: chipSymbol(tag))
                }
            }
        }
    }

    private func chipSymbol(_ tag: ECGRecordTag) -> String? {
        if case .custom = tag { return "number" }
        return nil
    }
}

private struct ECGAnnotationEditor: View {
    @State private var draft: ECGAnnotation
    @State private var newTag = ""
    @State private var showsSaveError = false
    @State private var showsTagError = false
    let availableTags: [String]
    let canSave: Bool
    let save: (ECGAnnotation) -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    init(annotation: ECGAnnotation, availableTags: [String], canSave: Bool, save: @escaping (ECGAnnotation) -> Bool) {
        _draft = State(initialValue: annotation)
        self.availableTags = availableTags
        self.canSave = canSave
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WatchBeatFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(ECGFeeling.allCases) { feeling in
                            ECGSelectableTag(
                                title: ECGRecordTag.feeling(feeling).title(in: language),
                                selected: draft.feelings.contains(feeling)
                            ) { draft.toggle(feeling) }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(language.text("How did you feel during this recording?", "记录期间感觉如何？"))
                } footer: {
                    Text(language.text("Choose all that apply, or leave this unanswered.", "可多选，也可以不填写。"))
                }

                Section {
                    if !draft.customTags.isEmpty {
                        WatchBeatFlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(draft.customTags, id: \.self) { tag in
                                Button {
                                    draft.customTags.removeAll { $0 == tag }
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(tag)
                                        Image(systemName: "xmark")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.pink.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(language.text("Remove \(tag)", "移除 \(tag)"))
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    HStack {
                        TextField(language.text("For example: after coffee", "例如：咖啡后、运动后"), text: $newTag)
                            .onSubmit { addTag() }
                        Button(language.text("Add", "添加")) { addTag() }
                            .buttonStyle(.borderless)
                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if showsTagError {
                        Text(language.text("This tag is empty or already selected.", "标签为空或已经添加。"))
                            .font(.caption).foregroundStyle(.orange)
                    }

                    if !suggestedTags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(language.text("Saved tags", "已有标签"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            WatchBeatFlowLayout(spacing: 8, lineSpacing: 8) {
                                ForEach(suggestedTags, id: \.self) { tag in
                                    Button {
                                        draft.addCustomTag(tag)
                                    } label: {
                                        Label(tag, systemImage: "plus")
                                            .font(.subheadline)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(Color.watchBeatInset, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(language.text("Add saved tag \(tag)", "添加已有标签 \(tag)"))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(language.text("Custom tags", "自定义标签"))
                }

                Section(language.text("Note", "文字批注")) {
                    TextEditor(text: $draft.note)
                        .frame(minHeight: 110)
                        .accessibilityLabel(language.text("Recording note", "记录批注"))
                }

                Section {
                    Button(language.text("Clear this annotation", "清空这条批注"), role: .destructive) {
                        draft = ECGAnnotation()
                    }
                    .disabled(draft.isEmpty)
                } footer: {
                    Text(language.text("Changes, including clearing, take effect when you tap Save.", "点击“保存”后，修改或清空才会生效。"))
                }
            }
            .navigationTitle(language.text("Recording annotation", "记录批注"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Cancel", "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Save", "保存")) {
                        // Do not silently discard a tag still in the input field.
                        if !newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            draft.addCustomTag(newTag)
                        }
                        if save(draft) { dismiss() } else { showsSaveError = true }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .alert(language.text("Annotation was not saved", "批注未保存"), isPresented: $showsSaveError) {
                Button(language.text("OK", "好"), role: .cancel) {}
            } message: {
                Text(language.text("Your edits are still here. Unlock the device and try saving again.", "修改仍保留在此页面，请解锁设备后重试保存。"))
            }
        }
    }

    /// Saved custom tags from other records that this draft does not have yet.
    private var suggestedTags: [String] {
        let current = Set(draft.customTags.map(ECGAnnotation.tagKey))
        return availableTags.filter { !current.contains(ECGAnnotation.tagKey($0)) }
    }

    private func addTag() {
        if draft.addCustomTag(newTag) { newTag = ""; showsTagError = false }
        else { showsTagError = true }
    }
}
