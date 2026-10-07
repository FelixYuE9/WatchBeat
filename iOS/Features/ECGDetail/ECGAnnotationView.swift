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
            HStack(alignment: .top) {
                Label(language.text("How did you feel during this recording?", "记录期间感觉如何？"), systemImage: "text.bubble")
                    .font(.headline)
                Spacer()
                Button(language.text(annotation.isEmpty ? "Add" : "Edit", annotation.isEmpty ? "添加" : "编辑")) {
                    showsEditor = true
                }
            }
            if store.hasLoadFailure && !isExample {
                Text(language.text("Saved annotations could not be read. Retry before editing.", "无法读取已保存的批注，请重试后再编辑。"))
                    .font(.caption).foregroundStyle(.orange)
                Button(language.text("Retry", "重试")) { store.reload() }
            } else if annotation.isEmpty {
                Text(language.text("Add symptoms, your own tags or a note to remember the context.", "选择当时的症状、添加自己的标签或文字批注，方便以后回顾。"))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ECGAnnotationTags(tags: annotation.tags)
                if !annotation.note.isEmpty {
                    Text(annotation.note).font(.subheadline).lineLimit(4)
                }
            }
            Text(language.text(
                isExample ? "Example annotations last only for this app session." : "Your notes are saved only on this iPhone. You can clear them in Settings.",
                isExample ? "示例批注仅保留到本次应用关闭。" : "你的批注仅保存在此 iPhone，可在设置中清除。"
            ))
            .font(.caption).foregroundStyle(.secondary)
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

struct ECGAnnotationTags: View {
    let tags: [ECGRecordTag]
    @Environment(\.appLanguage) private var language

    var body: some View {
        if !tags.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], alignment: .leading, spacing: 6) {
                ForEach(tags) { tag in
                    Text(tag.title(in: language))
                        .font(.caption)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.pink.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))], spacing: 8) {
                        ForEach(ECGFeeling.allCases) { feeling in
                            ECGSelectableTag(
                                title: ECGRecordTag.feeling(feeling).title(in: language),
                                selected: draft.feelings.contains(feeling)
                            ) { draft.toggle(feeling) }
                        }
                    }
                } header: {
                    Text(language.text("How did you feel during this recording?", "记录期间感觉如何？"))
                } footer: {
                    Text(language.text("Choose all that apply, or leave this unanswered.", "可多选，也可以不填写。"))
                }
                Section {
                    ForEach(draft.customTags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                            Spacer()
                            Button(role: .destructive) { draft.customTags.removeAll { $0 == tag } } label: {
                                Image(systemName: "minus.circle")
                            }
                            .accessibilityLabel(language.text("Remove \(tag)", "移除 \(tag)"))
                        }
                    }
                    HStack {
                        TextField(language.text("For example: after coffee", "例如：咖啡后、运动后"), text: $newTag)
                            .onSubmit { addTag() }
                        Button(language.text("Add", "添加")) { addTag() }
                            .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if showsTagError {
                        Text(language.text("This tag is empty or already selected.", "标签为空或已经添加。"))
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if !availableTags.isEmpty {
                        Menu(language.text("Reuse a saved tag", "使用已有标签")) {
                            ForEach(availableTags, id: \.self) { tag in
                                Button(tag) { draft.addCustomTag(tag) }
                            }
                        }
                    }
                } header: { Text(language.text("Custom tags", "自定义标签")) }
                Section(language.text("Note", "文字批注")) {
                    TextEditor(text: $draft.note).frame(minHeight: 110)
                        .accessibilityLabel(language.text("Recording note", "记录批注"))
                }
                Section {
                    Button(language.text("Clear this annotation", "清空这条批注"), role: .destructive) {
                        draft = ECGAnnotation()
                    }
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

    private func addTag() {
        if draft.addCustomTag(newTag) { newTag = ""; showsTagError = false }
        else { showsTagError = true }
    }
}
