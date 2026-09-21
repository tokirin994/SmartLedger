import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
// Batch import UI supports screenshots and exported bill files.

struct ImportReceiptView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject var settings: AppSettings
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var recognizedText: String = ""
    @State private var isRecognizing = false
    @State private var importMode: ImportMode = .image
    @State private var showFileImporter = false
    @State private var importedFileNames: [String] = []
    @State private var pendingImportSource = "ocr"
    @State private var pendingModeAfterDiscard: ImportMode?
    @State private var showModeDiscardConfirmation = false
    @State private var isRevertingMode = false
    @State private var activeImportToken = UUID()
    @State private var draft = TransactionDraft(source: "ocr")
    @State private var selectedBatchIDs: Set<String> = []
    @State private var showClearConfirmation = false
    @State private var editingBatchItem: OCRImportResult?
    @State private var importSaveError: String?
    private let ocrService = OCRImportService()

    private var unboundSplitCount: Int { draft.splitParticipantIds.count }

    private var unboundSplitEnabled: Bool {
        draft.bookId == nil && unboundSplitCount > 1
    }

    private func setUnboundSplitCount(_ count: Int) {
        guard count > 1 else {
            draft.splitParticipantIds = []
            draft.paidByParticipantId = nil
            return
        }
        draft.splitParticipantIds = ["我"] + (2...count).map { "分账成员\($0)" }
        draft.paidByParticipantId = nil
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                SectionCard(title: "导入流水") {
                    Picker("导入方式", selection: $importMode) {
                        ForEach(ImportMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if importMode == .image {
                        PhotosPicker(selection: $selectedItems, maxSelectionCount: 12, matching: .images) {
                            Label("选择一张或多张截图", systemImage: "photo.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        if !selectedImages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { _, image in
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 86, height: 86)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            .overlay(alignment: .topTrailing) {
                                                Text("OCR")
                                                    .font(.caption2.weight(.bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 4)
                                                    .background(Color.black.opacity(0.72), in: Capsule())
                                                    .foregroundStyle(.white)
                                                    .padding(5)
                                            }
                                    }
                                }
                            }
                            Text("已选择 \(selectedImages.count) 张截图，将合并为一个待确认列表")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("选择账单文件（可多选）", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Text("支持支付宝、微信、美团、京东导出的 CSV / TXT / XLSX 文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !importedFileNames.isEmpty {
                            Label(importedFileNames.joined(separator: "、"), systemImage: "doc.text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
    
    if isRecognizing {
        ProgressView(importMode == .image ? "正在识别截图..." : "正在读取账单文件...")
    }
    
    Group {
        if store.parsedImportItems.count > 1 {
            batchImportSection
        } else if let parsed = store.parsedImport {
            singleImportSection(parsed: parsed)
        } else if (!selectedImages.isEmpty || !importedFileNames.isEmpty), !isRecognizing {
            SectionCard(title: "未解析出结构化账单") {
                Text("未解析出结构化流水，请更换文件或图片后重试。")
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
}
.appBackground()
.navigationTitle(importMode == .image ? "识图导入" : "文件导入")
.toolbar {
    if !selectedImages.isEmpty || !importedFileNames.isEmpty || store.hasPendingOCRImport {
        ToolbarItem(placement: .topBarTrailing) {
            Button("清空", role: .destructive) { showClearConfirmation = true }
        }
    }
}
.onChange(of: selectedItems) { _, newValue in
    guard !newValue.isEmpty else { return }
    Task { await loadImages(from: newValue) }
}
.onChange(of: importMode) { oldValue, newValue in
    if isRevertingMode {
        isRevertingMode = false
        return
    }
    guard oldValue != newValue, store.hasPendingOCRImport else { return }
    pendingModeAfterDiscard = newValue
    isRevertingMode = true
    importMode = oldValue
    showModeDiscardConfirmation = true
}
.fileImporter(
    isPresented: $showFileImporter,
    // Let the parser validate the extension/header so generic exports are not
    // silently rejected by the system document picker.
    allowedContentTypes: [.item],
    allowsMultipleSelection: true
) { result in
    Task { @MainActor in
        await importBillFiles(result)
    }
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
.alert("无法保存流水", isPresented: Binding(get: { importSaveError != nil }, set: { if !$0 { importSaveError = nil } })) {
    Button("知道了", role: .cancel) {}
} message: {
    Text(importSaveError ?? "请补全标题和金额后重试。")
}
.alert("切换导入方式？", isPresented: $showModeDiscardConfirmation) {
    Button("切换并丢弃", role: .destructive) {
        clearImportState()
        if let mode = pendingModeAfterDiscard {
            pendingModeAfterDiscard = nil
            isRevertingMode = true
            importMode = mode
        }
    }
    Button("留在当前页面", role: .cancel) { pendingModeAfterDiscard = nil }
} message: {
    Text("当前还有未保存的识别结果，切换方式会丢弃这些待确认流水。")
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

private enum ImportMode: String, CaseIterable, Identifiable, Hashable {
    case image
    case file

    var id: String { rawValue }
    var title: String { self == .image ? "截图识别" : "账单文件" }
    var systemImage: String { self == .image ? "camera.viewfinder" : "doc.badge.plus" }
}

private var batchImportSection: some View {
    SectionCard(title: "待确认流水（\(store.parsedImportItems.count) 笔）") {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.parsedImportItems) { item in
                HStack(alignment: .top, spacing: 8) {
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
                                if let source = item.details?.first(where: { $0.label == "导入来源" })?.value {
                                    Text(source)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button("编辑") { editingBatchItem = item }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                }
                .glassCard(cornerRadius: 16, strokeOpacity: 0.22)
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
        .textSelection(.enabled)
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
        if draft.bookId == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("多人分账")
                    .font(.headline)
                Toggle("启用分账", isOn: Binding(
                    get: { unboundSplitEnabled },
                    set: { enabled in setUnboundSplitCount(enabled ? max(unboundSplitCount, 2) : 0) }
                ))
                if unboundSplitEnabled {
                    Stepper(
                        "分账人数：\(unboundSplitCount)",
                        value: Binding(
                            get: { unboundSplitCount },
                            set: { setUnboundSplitCount($0) }
                        ),
                        in: 2...20
                    )
                    Text("按人数均分，原始金额不变；首页和流水统计只计入我的份额。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        Toggle("启用分期", isOn: $draft.installmentEnabled)
        if draft.installmentEnabled {
            Stepper("分期月数: \(draft.installmentMonths)", value: $draft.installmentMonths, in: 1...24)
            DatePicker("起始月份", selection: $draft.installmentStartMonth, displayedComponents: .date)
        }
        if draft.kind == .expense {
            if !draft.offsetEnabled {
                Button {
                    draft.offsetEnabled = true
                    draft.offsetCategoryId = preferredOCRIncomeCategoryID
                } label: {
                    Label("添加抵扣 / 报销", systemImage: "plus.circle.fill")
                }
            } else {
                Picker("抵扣类型", selection: $draft.offsetCategoryId) {
                    Text("请选择收入分类").tag(Int?.none)
                    ForEach(store.flattenedCategories.filter { $0.flowType == .income }) { category in
                        Text(category.displayName).tag(Int?.some(category.id))
                    }
                }
                HStack { Text("抵扣比例"); Slider(value: $draft.offsetRatio, in: 0...100, step: 1); Text("\(Int(draft.offsetRatio))%").monospacedDigit().frame(width: 42, alignment: .trailing) }
                LabeledContent("预计生成收入", value: ocrOffsetAmount.cnyText)
                    .font(.subheadline.weight(.semibold))
                Button("移除抵扣", role: .destructive) { draft.offsetEnabled = false; draft.offsetCategoryId = nil }
            }
        }
        GroupBox("高级信息") {
            VStack(spacing: 12) {
                TextField("商户", text: $draft.merchant)
                    .textFieldStyle(.roundedBorder)
                TextField("备注", text: $draft.note)
                    .textFieldStyle(.roundedBorder)
                TextField("原价", text: $draft.originalAmount)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                TextField("优惠金额", text: $draft.discountAmount)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                TextField("溢价金额", text: $draft.premiumAmount)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
            .frame(maxWidth: .infinity)
        }
        Button("保存这笔账单") {
            Task {
                if !draft.paymentMethod.isEmpty {
                    draft.paymentMethod = settings.registerPaymentChannel(draft.paymentMethod) ?? draft.paymentMethod
                }
                await saveSingleImport()
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

private var preferredOCRIncomeCategoryID: Int? {
    let income = store.flattenedCategories.filter { $0.flowType == .income }
    return income.first(where: { $0.displayName.contains("报销") })?.id
        ?? income.first(where: { $0.displayName.contains("退款") })?.id
        ?? income.first?.id
}

private var ocrOffsetAmount: Double {
    ((Double(draft.amount) ?? 0) * min(max(draft.offsetRatio, 0), 100) / 100 * 100).rounded() / 100
}

private func applyParsedDefaults(parsed: OCRImportResult) {
    draft = TransactionDraft(parsed: parsed, source: pendingImportSource)
    draft.ocrText = recognizedText
    applyParsedCategorySuggestion(parsed: parsed)
}

private func applyParsedCategorySuggestion(parsed: OCRImportResult) {
    guard let matched = store.findCategory(bySuggestedPath: parsed.categoryPath ?? []), matched.flowType == draft.kind else {
        return
    }
    draft.categoryId = matched.id
}

private func loadImages(from items: [PhotosPickerItem]) async {
    do {
        let token = UUID()
        activeImportToken = token
        isRecognizing = true
        store.clearOCRImport()
        store.beginImportSelection()
        selectedBatchIDs.removeAll()
        recognizedText = ""
        pendingImportSource = "ocr"
        importedFileNames.removeAll()
        selectedImages.removeAll()
        var texts: [String] = []
        for item in items {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
            guard activeImportToken == token else { return }
            selectedImages.append(image)
            texts.append(try await ocrService.recognizeText(from: image))
        }
        guard activeImportToken == token else { return }
        recognizedText = texts.joined(separator: "\n")
        await store.parseOCRBatch(texts: texts)
        guard activeImportToken == token else { return }
        selectedBatchIDs = Set(store.parsedImportItems.map(\.id))
        isRecognizing = false
    } catch {
        isRecognizing = false
        importSaveError = "识别失败：\(error.localizedDescription)"
    }
}

private func importBillFiles(_ result: Result<[URL], Error>) async {
    do {
        let urls = try result.get()
        guard !urls.isEmpty else {
            isRecognizing = false
            importSaveError = "没有选择账单文件，请重新选择后点击‘打开’。"
            return
        }
        let token = UUID()
        activeImportToken = token
        isRecognizing = true
        store.clearOCRImport()
        store.beginImportSelection()
        selectedBatchIDs.removeAll()
        selectedImages.removeAll()
        recognizedText = ""
        pendingImportSource = "file"
        // Keep security-scoped access alive while parsing, but move the
        // potentially expensive CSV/XLSX work off the UI thread.  Otherwise
        // tapping “打开” can look like it did nothing for a large export.
        let scopedURLs = urls.map { url in
            (url, url.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, accessed) in scopedURLs where accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let parsedFiles = await Task.detached(priority: .userInitiated) {
            let parser = BillFileImportService()
            var items: [OCRImportResult] = []
            var failures: [String] = []
            for url in urls {
                do {
                    items.append(contentsOf: try parser.parse(url: url))
                } catch {
                    failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                }
            }
            return (items, failures)
        }.value
        let items = parsedFiles.0
        let failures = parsedFiles.1
        let names = urls.map(\.lastPathComponent)
        guard activeImportToken == token else { return }
        importedFileNames = names
        await store.setPendingImportItems(items)
        guard activeImportToken == token else { return }
        selectedBatchIDs = Set(store.parsedImportItems.map(\.id))
        isRecognizing = false
        if items.isEmpty {
            importSaveError = failures.isEmpty ? "文件中没有识别到可导入的收支流水。" : failures.joined(separator: "\n")
        } else if !failures.isEmpty {
            importSaveError = "部分文件未能导入：\n" + failures.joined(separator: "\n")
        }
    } catch {
        isRecognizing = false
        importSaveError = error.localizedDescription
    }
}

private func saveSelectedBatchItems() async {
    let selected = store.parsedImportItems.filter { selectedBatchIDs.contains($0.id) }
    let invalid = selected.filter { ($0.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ($0.amount ?? 0) <= 0 }
    guard invalid.isEmpty else {
        importSaveError = "待确认流水中有 \(invalid.count) 笔缺少标题或有效金额，请先点击“编辑”补全后再保存。"
        return
    }
    for item in selected {
        var draft = TransactionDraft(parsed: item, source: pendingImportSource)
        draft.ocrText = recognizedText
        if !draft.paymentMethod.isEmpty {
            draft.paymentMethod = settings.registerPaymentChannel(draft.paymentMethod) ?? draft.paymentMethod
        }
        if let matched = store.findCategory(bySuggestedPath: item.categoryPath ?? []), matched.flowType == draft.kind {
            draft.categoryId = matched.id
        }
        store.errorMessage = nil
        await store.createTransaction(draft)
        if let error = store.errorMessage {
            importSaveError = "“\(draft.title)”保存失败：\(error)"
            return
        }
    }
    let remaining = store.parsedImportItems.filter { !selectedBatchIDs.contains($0.id) }
    if remaining.isEmpty {
        clearImportState()
    } else {
        store.setPendingImportItems(remaining)
        selectedBatchIDs.removeAll()
    }
}

private func saveSingleImport() async {
    guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        importSaveError = "请填写流水标题。"
        return
    }
    guard let amount = Double(draft.amount), amount > 0 else {
        importSaveError = "请填写大于 0 的有效金额。"
        return
    }
    if draft.offsetEnabled && draft.offsetCategoryId == nil {
        importSaveError = "请为抵扣流水选择“报销”或“退款”分类。"
        return
    }
    store.errorMessage = nil
    await store.createTransaction(draft)
    if let error = store.errorMessage {
        importSaveError = error
        return
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
    activeImportToken = UUID()
    isRecognizing = false
    store.clearOCRImport()
    selectedItems.removeAll()
    selectedImages.removeAll()
    recognizedText = ""
    importedFileNames.removeAll()
    pendingImportSource = "ocr"
    selectedBatchIDs.removeAll()
    draft = TransactionDraft(source: "ocr")
    pendingModeAfterDiscard = nil
}

private struct OCRBatchItemEditor: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let item: OCRImportResult
    let onSave: (OCRImportResult) -> Void
    @State private var draft: TransactionDraft
    @State private var validationMessage: String?

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
                    TextField("原价", text: $draft.originalAmount).keyboardType(.decimalPad)
                    TextField("优惠金额", text: $draft.discountAmount).keyboardType(.decimalPad)
                    TextField("溢价金额", text: $draft.premiumAmount).keyboardType(.decimalPad)
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
            .dismissKeyboardWhenTappedOutside()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { validationMessage = "请填写流水标题。"; return }
                        guard let amount = Double(draft.amount), amount > 0 else { validationMessage = "请填写大于 0 的有效金额。"; return }
                        var updated = item
                        updated.title = title
                        updated.amount = amount
                        updated.kind = draft.kind
                        updated.happenedAt = draft.happenedAt
                        let merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
                        let paymentMethod = draft.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.merchant = merchant.isEmpty ? nil : merchant
                        updated.paymentMethod = paymentMethod.isEmpty ? nil : paymentMethod
                        updated.originalAmount = Double(draft.originalAmount)
                        updated.discountAmount = Double(draft.discountAmount)
                        updated.premiumAmount = Double(draft.premiumAmount)
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
            .alert("无法保存待确认流水", isPresented: Binding(get: { validationMessage != nil }, set: { if !$0 { validationMessage = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: { Text(validationMessage ?? "") }
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
// End of ImportReceiptView.
//
//
