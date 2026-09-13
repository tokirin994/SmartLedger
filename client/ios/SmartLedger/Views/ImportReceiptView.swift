import PhotosUI
import SwiftUI
import UIKit

struct ImportReceiptView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject var settings: AppSettings
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var recognizedText: String = ""
    @State private var isRecognizing = false
    @State private var draft = TransactionDraft(source: "ocr")
    @State private var selectedBatchIDs: Set<String> = []
    @State private var showClearConfirmation = false
    @State private var editingBatchItem: OCRImportResult?
    private let ocrService = OCRImportService()
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                SectionCard(title: "导入截图") {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("选择截图", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Text("OCR")

        .font(.caption2.weight(.bold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.72), in: Capsule())
        .foregroundStyle(.white)
        .padding(10)
                            }
                    }
                }
    
    if isRecognizing {
        ProgressView("正在识别截图...")
    }
    
    Group {
        if store.parsedImportItems.count > 1 {
            batchImportSection
        } else if let parsed = store.parsedImport {
            singleImportSection(parsed: parsed)
        } else if selectedImage != nil, !isRecognizing, !recognizedText.isEmpty {
            SectionCard(title: "未解析出结构化账单") {
                EmptyView()
            }
        }
    }
    .padding()
}
.appBackground()
.navigationTitle("图片识别")
.toolbar {
    if selectedImage != nil || store.hasPendingOCRImport {
        ToolbarItem(placement: .topBarTrailing) {
            Button("清空", role: .destructive) { showClearConfirmation = true }
        }
    }
}
.onChange(of: selectedItem) { _, newValue in
    guard let newValue else { return }
    Task { await loadImage(from: newValue) }
}
.onReceive(NotificationCenter.default.publisher(for: .smartLedgerDiscardOCRImport)) { _ in
    clearImportState()
}
.alert("清空识别内容？", isPresented: $showClearConfirmation) {
    Button("清空", role: .destructive) { clearImportState() }
    Button("取消", role: .cancel) {}
} message: {
    Text("将丢弃当前图片、识别结果和所有待确认流水，已保存的流水不会受影响。")
}
.sheet(item: $editingBatchItem) { item in
    OCRBatchItemEditor(item: item) { updated in
        replaceBatchItem(updated)
    }
    .environmentObject(store)
    .environmentObject(settings)
}
        }
    }

private var batchImportSection: some View {
    SectionCard(title: "待确认流水（\(store.parsedImportItems.count) 笔）") {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.parsedImportItems) { item in
                Button {
                    toggleBatchSelection(item.id)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: selectedBatchIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedBatchIDs.contains(item.id) ? .blue : .secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.title ?? "未命名流水")
                                    .font(.headline)
                                Spacer()
                                Text(item.amount.map { $0.cnyText } ?? "待填写")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(item.amount == nil ? .orange : .primary)
                            }
                            Text(item.happenedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未识别时间")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let merchant = item.merchant, merchant != item.title {
                                Text("商户: \(merchant)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let paymentMethod = item.paymentMethod, !paymentMethod.isEmpty {
                                Text("支付路径: \(paymentMethod)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text((item.categoryPath ?? []).isEmpty ? "未分类" : (item.categoryPath ?? []).joined(separator: " / "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 16, strokeOpacity: 0.22)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottomTrailing) {
                    Button("编辑") { editingBatchItem = item }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .padding(18)
                }
            }
            HStack(spacing: 12) {
                Button("全选") {
                    selectedBatchIDs = Set(store.parsedImportItems.map(\.id))
                }
                .buttonStyle(.bordered)

                Button("取消全选") {
                    selectedBatchIDs.removeAll()
                }
                .buttonStyle(.bordered)

                Spacer()
                
                Button("批量保存") {
                    Task { await saveSelectedBatchItems() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedBatchIDs.isEmpty)
            }
        }
    }
}

@ViewBuilder
private func singleImportSection(parsed: OCRImportResult) -> some View {
    SectionCard(title: "结构化结果") {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("金额", value: (parsed.amount ?? 0).cnyText)
            LabeledContent("类型", value: (parsed.kind ?? .expense).title)
            LabeledContent("标题", value: parsed.title ?? "—")
            LabeledContent("商户", value: parsed.merchant ?? "—")
            LabeledContent("支付路径", value: parsed.paymentMethod ?? "—")
            LabeledContent("时间", value: parsed.happenedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            if let original = parsed.originalAmount {
                LabeledContent("原价", value: original.cnyText)
            }
            if let discount = parsed.discountAmount {
                LabeledContent("优惠", value: discount.cnyText)
            }
            LabeledContent("分类", value: (parsed.categoryPath ?? []).joined(separator: " / "))
            LabeledContent("置信度", value: "\(((parsed.confidence ?? 0) * 100).formatted(.number.precision(.fractionLength(0))))%")

            if !(parsed.details ?? []).isEmpty {
                Divider()
                ForEach(parsed.details ?? []) { item in
                    LabeledContent(item.label, value: item.value)
                }
            }
        }
    }

    SectionCard(title: "确认入账") {
        importDraftForm(parsed: parsed)
    }
}

@ViewBuilder
private func importDraftForm(parsed: OCRImportResult) -> some View {
    VStack(spacing: 12) {
        TextField("标题", text: $draft.title)
            .textFieldStyle(.roundedBorder)
        TextField("金额", text: $draft.amount)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
        PaymentChannelPickerCard(selection: $draft.paymentMethod)
        DatePicker("时间", selection: $draft.happenedAt)
        Picker("类型", selection: $draft.kind) {
            ForEach(FlowType.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        HierarchicalCategoryPicker(
            title: "分类",
            categories: store.categories.filter { $0.flowType == draft.kind },
            placeholder: "请选择",
            helperText: nil,
            selectedCategoryId: $draft.categoryId,
            flowType: draft.kind,
            onCreateCategory: nil
        )
        Picker("主题账本", selection: $draft.bookId) {
            Text("不归集到主题账本").tag(Int?.none)
            ForEach(store.books) { book in
                Text(book.name).tag(Int?.some(book.id))
            }
        }
        Toggle("启用分期", isOn: $draft.installmentEnabled)
        if draft.installmentEnabled {
            Stepper("分期月数: \(draft.installmentMonths)", value: $draft.installmentMonths, in: 1...24)
            DatePicker("起始月份", selection: $draft.installmentStartMonth, displayedComponents: .date)
        }
        GroupBox("高级信息") {
            VStack(spacing: 12) {
                TextField("商户", text: $draft.merchant)
                    .textFieldStyle(.roundedBorder)
                TextField("备注", text: $draft.note)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(maxWidth: .infinity)
        }
        Button("保存这笔账单") {
            Task {
                if !draft.paymentMethod.isEmpty {
                    draft.paymentMethod = settings.registerPaymentChannel(draft.paymentMethod) ?? draft.paymentMethod
                }
                await store.createTransaction(draft)
                clearImportState()
            }
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .onAppear {
        applyParsedDefaults(parsed: parsed)
        if store.books.isEmpty {
            Task { await store.loadBooks() }
        }
        if store.categories.isEmpty {
            Task {
                await store.loadCategories()
                applyParsedCategorySuggestion(parsed: parsed)
            }
        }
    }
    .onChange(of: draft.kind) { _, newKind in
        if let selectedCategoryId = draft.categoryId,
           !store.selectableCategories(for: newKind).contains(where: { $0.id == selectedCategoryId }) {
            draft.categoryId = nil
        }
    }
    .onChange(of: draft.installmentEnabled) { _, enabled in
        if enabled {
            draft.installmentMonths = 1
        }
    }
}

private func applyParsedDefaults(parsed: OCRImportResult) {
    draft = TransactionDraft(parsed: parsed, source: "ocr")
    draft.ocrText = recognizedText
    applyParsedCategorySuggestion(parsed: parsed)
}

private func applyParsedCategorySuggestion(parsed: OCRImportResult) {
    guard let matched = store.findCategory(bySuggestedPath: parsed.categoryPath ?? []), matched.flowType == draft.kind else {
        return
    }
    draft.categoryId = matched.id
}

private func loadImage(from item: PhotosPickerItem) async {
    do {
        isRecognizing = true
        store.clearOCRImport()
        selectedBatchIDs.removeAll()
        recognizedText = ""
        if let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            selectedImage = image
            recognizedText = try await ocrService.recognizeText(from: image)
            await store.parseOCR(text: recognizedText)
            selectedBatchIDs = Set(store.parsedImportItems.map(\.id))
        }
        isRecognizing = false
    } catch {
        isRecognizing = false
        store.errorMessage = error.localizedDescription
    }
}

private func saveSelectedBatchItems() async {
    let selected = store.parsedImportItems.filter { selectedBatchIDs.contains($0.id) }
    for item in selected {
        var draft = TransactionDraft(parsed: item, source: "ocr")
        draft.ocrText = recognizedText
        if !draft.paymentMethod.isEmpty {
            draft.paymentMethod = settings.registerPaymentChannel(draft.paymentMethod) ?? draft.paymentMethod
        }
        if let matched = store.findCategory(bySuggestedPath: item.categoryPath ?? []), matched.flowType == draft.kind {
            draft.categoryId = matched.id
        }
        await store.createTransaction(draft)
    }
    clearImportState()
}

private func toggleBatchSelection(_ id: String) {
    if selectedBatchIDs.contains(id) {
        selectedBatchIDs.remove(id)
    } else {
        selectedBatchIDs.insert(id)
    }
}

private func clearImportState() {
    store.clearOCRImport()
    selectedItem = nil
    selectedImage = nil
    recognizedText = ""
    selectedBatchIDs.removeAll()
    draft = TransactionDraft(source: "ocr")
}

private struct OCRBatchItemEditor: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let item: OCRImportResult
    let onSave: (OCRImportResult) -> Void
    @State private var draft: TransactionDraft

    init(item: OCRImportResult, onSave: @escaping (OCRImportResult) -> Void) {
        self.item = item
        self.onSave = onSave
        _draft = State(initialValue: TransactionDraft(parsed: item, source: "ocr"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("待确认流水") {
                    TextField("标题", text: $draft.title)
                    TextField("金额", text: $draft.amount).keyboardType(.decimalPad)
                    Picker("类型", selection: $draft.kind) {
                        ForEach(FlowType.allCases) { kind in Text(kind.title).tag(kind) }
                    }
                    DatePicker("时间", selection: $draft.happenedAt)
                    TextField("商户", text: $draft.merchant)
                    TextField("支付渠道", text: $draft.paymentMethod)
                    Picker("分类", selection: $draft.categoryId) {
                        Text("未分类").tag(Int?.none)
                        ForEach(store.selectableCategories(for: draft.kind)) { category in
                            Text(category.name).tag(Int?.some(category.id))
                        }
                    }
                }
            }
            .navigationTitle("编辑识别结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = item
                        updated.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名流水" : draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.amount = Double(draft.amount)
                        updated.kind = draft.kind
                        updated.happenedAt = draft.happenedAt
                        let merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
                        let paymentMethod = draft.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.merchant = merchant.isEmpty ? nil : merchant
                        updated.paymentMethod = paymentMethod.isEmpty ? nil : paymentMethod
                        if let categoryId = draft.categoryId,
                           let category = store.selectableCategories(for: draft.kind).first(where: { $0.id == categoryId }) {
                            updated.categoryPath = category.pathComponents
                        } else {
                            updated.categoryPath = []
                        }
                        if !draft.paymentMethod.isEmpty {
                            _ = settings.registerPaymentChannel(draft.paymentMethod)
                        }
                        onSave(updated)
                        dismiss()
                    }
                }
            }
            .task { if store.categories.isEmpty { await store.loadCategories() } }
        }
    }
}

private struct PaymentChannelPickerCard: View {
    @Binding var selection: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("支付渠道")
            PaymentChannelField(selection: $selection, title: "")
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .glassCard(cornerRadius: 12, strokeOpacity: 0.20)
        }
    }
}

private func replaceBatchItem(_ updated: OCRImportResult) {
    guard let index = store.parsedImportItems.firstIndex(where: { $0.id == updated.id }) else { return }
    store.parsedImportItems[index] = updated
    if store.parsedImport?.id == updated.id {
        store.parsedImport = updated
    }
}

}
