import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
// Batch import UI supports screenshots and exported bill files.

func ocrOffsetIncomeCategoryID(in categories: [LedgerCategory], presetKey: String? = nil) -> Int? {
    let income = categories.filter { $0.flowType == .income }
    let preference = presetKey == "meituan_enterprise_meal"
        ? ["补贴", "报销", "退款"]
        : ["报销", "退款", "补贴"]
    return preference.compactMap { keyword in
        income.first(where: { $0.displayName.contains(keyword) })?.id
    }.first ?? income.first?.id
}

struct ImportReceiptView: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject var settings: AppSettings
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var previewedImage: OCRImagePreviewItem?
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
    @State private var showBatchCategoryEditor = false
    @State private var batchDraftOverrides: [String: TransactionDraft] = [:]
    @State private var importSaveError: String?
    private let ocrService = OCRImportService()

    private var unboundSplitCount: Int { draft.splitParticipantIds.count }

    private var unboundSplitEnabled: Bool {
        draft.hasExplicitBookSelection && !draft.manuallySelectBooks && draft.bookIds.isEmpty && unboundSplitCount > 1
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
                                        Button {
                                            previewedImage = OCRImagePreviewItem(image: image)
                                        } label: {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 86, height: 86)
                                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                .overlay(alignment: .topTrailing) {
                                                    Image(systemName: "magnifyingglass")
                                                        .font(.caption.weight(.bold))
                                                        .padding(6)
                                                        .background(Color.black.opacity(0.72), in: Circle())
                                                        .foregroundStyle(.white)
                                                        .padding(5)
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("预览识别图片")
                                    }
                                }
                            }
                            Text("已选择 \(selectedImages.count) 张截图，将合并为一个待确认列表")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            guard !isRecognizing else { return }
                            showFileImporter = true
                        } label: {
                            Label("选择账单文件（可多选）", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRecognizing)
                        Text("支持支付宝、微信、美团、京东账单文件，以及银行导出的 PDF / CSV / TXT / XLSX")
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
.scrollDismissesKeyboard(.interactively)
.fullScreenCover(item: $previewedImage) { item in
    OCRImagePreview(image: item.image)
}
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
.sheet(isPresented: $showFileImporter) {
    DocumentPickerView(
        onPick: { urls in
            // Reset the presentation state before starting any parsing work.
            // This guarantees the picker cannot remain over the recognition UI.
            showFileImporter = false
            isRecognizing = true
            Task { @MainActor in
                await importBillFiles(.success(urls))
            }
        },
        onCancel: {
            showFileImporter = false
        }
    )
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
    OCRBatchItemEditor(
        item: item,
        initialDraft: batchDraftOverrides[item.id] ?? makeBatchDraft(for: item)
    ) { updated, editedDraft in
        replaceBatchItem(updated)
        batchDraftOverrides[item.id] = editedDraft
    }
    .environmentObject(store)
    .environmentObject(settings)
}
.sheet(isPresented: $showBatchCategoryEditor) {
    let selectedItems = store.parsedImportItems.filter { selectedBatchIDs.contains($0.id) }
    let flowTypes = Set(selectedItems.map { $0.kind ?? .expense })
    BatchCategoryEditorSheet(flowTypes: flowTypes) { updateExpense, expenseCategoryId, updateIncome, incomeCategoryId in
        var updatedItems = store.parsedImportItems
        for index in updatedItems.indices where selectedBatchIDs.contains(updatedItems[index].id) {
            let kind = updatedItems[index].kind ?? .expense
            let shouldUpdate = kind == .expense ? updateExpense : updateIncome
            guard shouldUpdate else { continue }
            let categoryId = kind == .expense ? expenseCategoryId : incomeCategoryId
            updatedItems[index].categoryPath = categoryId.flatMap { id in
                store.flattenedCategories.first(where: { $0.id == id })?.pathComponents
            } ?? []
            if var override = batchDraftOverrides[updatedItems[index].id] {
                override.kind = kind
                override.categoryId = categoryId
                batchDraftOverrides[updatedItems[index].id] = override
            }
        }
        store.setPendingImportItems(updatedItems)
    }
    .environmentObject(store)
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

private struct OCRImagePreviewItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct OCRImagePreview: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    @State private var verticalDrag: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 12)
                .offset(y: verticalDrag)
                .gesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { value in
                            if value.translation.height > 0 { verticalDrag = value.translation.height }
                        }
                        .onEnded { value in
                            if value.translation.height > 110 {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    verticalDrag = 0
                                }
                            }
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
            .accessibilityLabel("关闭图片预览")
        }
        .statusBarHidden()
    }
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

            Button("批量改分类") { showBatchCategoryEditor = true }
                .buttonStyle(.bordered)
                .disabled(selectedBatchIDs.isEmpty)

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
        OCRBookSplitEditor(
            bookIds: $draft.bookIds,
            bookId: $draft.bookId,
            splitSettings: $draft.ledgerSplitSettings,
            hasExplicitSelection: $draft.hasExplicitBookSelection,
            manuallySelectBooks: $draft.manuallySelectBooks,
            books: store.books,
            automaticBooks: automaticOCRBooks
        )
        if draft.hasExplicitBookSelection && !draft.manuallySelectBooks && draft.bookIds.isEmpty {
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
        OCRInstallmentEditor(
            isEnabled: $draft.installmentEnabled,
            months: $draft.installmentMonths,
            startMonth: $draft.installmentStartMonth
        )
        if draft.kind == .expense {
            if !draft.offsetEnabled {
                Button {
                    draft.offsetEnabled = true
                    draft.offsetCategoryId = preferredOCRIncomeCategoryID
                } label: {
                    Label("添加抵扣 / 报销", systemImage: "plus.circle.fill")
                }
            } else {
                HierarchicalCategoryPicker(
                    title: "抵扣类型",
                    categories: store.categories.filter { $0.flowType == .income },
                    placeholder: "请选择收入分类",
                    helperText: nil,
                    selectedCategoryId: $draft.offsetCategoryId,
                    flowType: .income,
                    onCreateCategory: nil
                )
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
                await saveSingleImport(presetKey: parsed.presetKey)
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
                applyOCRPresetDefaults(parsed, to: &draft)
            }
        }
    }
    .onChange(of: draft.kind) { _, newKind in
        if let selectedCategoryId = draft.categoryId,
           !store.selectableCategories(for: newKind).contains(where: { $0.id == selectedCategoryId }) {
            draft.categoryId = nil
        }
    }
}

private var preferredOCRIncomeCategoryID: Int? {
    ocrOffsetIncomeCategoryID(in: store.flattenedCategories)
}

private var ocrOffsetAmount: Double {
    ((Double(draft.amount) ?? 0) * min(max(draft.offsetRatio, 0), 100) / 100 * 100).rounded() / 100
}

private var automaticOCRBooks: [LedgerBook] {
    store.recommendedBooks(for: draft.happenedAt).filter {
        store.shouldAutoCollect(into: $0, date: draft.happenedAt, categoryId: draft.categoryId, kind: draft.kind)
    }
}

private func applyParsedDefaults(parsed: OCRImportResult) {
    draft = TransactionDraft(parsed: parsed, source: pendingImportSource)
    draft.ocrText = recognizedText
    applyParsedCategorySuggestion(parsed: parsed)
    applyOCRPresetDefaults(parsed, to: &draft)
}

private func applyParsedCategorySuggestion(parsed: OCRImportResult) {
    guard let matched = store.findCategory(bySuggestedPath: parsed.categoryPath ?? []), matched.flowType == draft.kind else {
        return
    }
    draft.categoryId = matched.id
}

private func makeBatchDraft(for item: OCRImportResult) -> TransactionDraft {
    var batchDraft = TransactionDraft(parsed: item, source: pendingImportSource)
    if let matched = store.findCategory(bySuggestedPath: item.categoryPath ?? []), matched.flowType == batchDraft.kind {
        batchDraft.categoryId = matched.id
    }
    applyOCRPresetDefaults(item, to: &batchDraft)
    return batchDraft
}

private func applyOCRPresetDefaults(_ parsed: OCRImportResult, to draft: inout TransactionDraft) {
    guard parsed.presetKey == "meituan_enterprise_meal" else { return }
    draft.kind = .expense
    draft.paymentMethod = "公司补贴"
    draft.offsetEnabled = true
    draft.offsetRatio = 100
    draft.offsetCategoryId = ocrOffsetIncomeCategoryID(
        in: store.flattenedCategories,
        presetKey: parsed.presetKey
    )
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
    if store.categories.isEmpty { await store.loadCategories() }
    let selected = store.parsedImportItems.filter { selectedBatchIDs.contains($0.id) }
    let invalid = selected.filter { ($0.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ($0.amount ?? 0) <= 0 }
    guard invalid.isEmpty else {
        importSaveError = "待确认流水中有 \(invalid.count) 笔缺少标题或有效金额，请先点击“编辑”补全后再保存。"
        return
    }
    for item in selected {
        var draft = batchDraftOverrides[item.id] ?? makeBatchDraft(for: item)
        if draft.offsetEnabled && draft.offsetCategoryId == nil {
            draft.offsetCategoryId = ocrOffsetIncomeCategoryID(
                in: store.flattenedCategories,
                presetKey: item.presetKey
            )
        }
        draft.source = pendingImportSource
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
        let remainingIDs = Set(remaining.map(\.id))
        selectedBatchIDs.removeAll()
        batchDraftOverrides = batchDraftOverrides.filter { remainingIDs.contains($0.key) }
    }
}

private func saveSingleImport(presetKey: String? = nil) async {
    if store.categories.isEmpty { await store.loadCategories() }
    if draft.offsetEnabled && draft.offsetCategoryId == nil {
        draft.offsetCategoryId = ocrOffsetIncomeCategoryID(
            in: store.flattenedCategories,
            presetKey: presetKey
        )
    }
    guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        importSaveError = "请填写流水标题。"
        return
    }
    guard let amount = Double(draft.amount), amount > 0 else {
        importSaveError = "请填写大于 0 的有效金额。"
        return
    }
    if draft.offsetEnabled && draft.offsetCategoryId == nil {
        importSaveError = "请为抵扣流水选择“补贴”“报销”或“退款”分类。"
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
    batchDraftOverrides.removeAll()
    draft = TransactionDraft(source: "ocr")
    pendingModeAfterDiscard = nil
}

private struct OCRBatchItemEditor: View {
    @EnvironmentObject private var store: LedgerStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let item: OCRImportResult
    let onSave: (OCRImportResult, TransactionDraft) -> Void
    @State private var draft: TransactionDraft
    @State private var validationMessage: String?

    init(item: OCRImportResult, initialDraft: TransactionDraft?, onSave: @escaping (OCRImportResult, TransactionDraft) -> Void) {
        self.item = item
        self.onSave = onSave
        _draft = State(initialValue: initialDraft ?? TransactionDraft(parsed: item, source: "ocr"))
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
                    PaymentChannelField(selection: $draft.paymentMethod, title: "支付渠道")
                    TextField("原价", text: $draft.originalAmount).keyboardType(.decimalPad)
                    TextField("优惠金额", text: $draft.discountAmount).keyboardType(.decimalPad)
                    TextField("溢价金额", text: $draft.premiumAmount).keyboardType(.decimalPad)
                    HierarchicalCategoryPicker(
                        title: "分类",
                        categories: store.categories.filter { $0.flowType == draft.kind },
                        placeholder: "未分类",
                        helperText: nil,
                        selectedCategoryId: $draft.categoryId,
                        flowType: draft.kind,
                        onCreateCategory: nil
                    )
                }
                Section("账本与分账") {
                    OCRBookSplitEditor(
                        bookIds: $draft.bookIds,
                        bookId: $draft.bookId,
                        splitSettings: $draft.ledgerSplitSettings,
                        hasExplicitSelection: $draft.hasExplicitBookSelection,
                        manuallySelectBooks: $draft.manuallySelectBooks,
                        books: store.books,
                        automaticBooks: store.recommendedBooks(for: draft.happenedAt).filter {
                            store.shouldAutoCollect(into: $0, date: draft.happenedAt, categoryId: draft.categoryId, kind: draft.kind)
                        }
                    )
                    .listRowInsets(EdgeInsets())
                    if draft.hasExplicitBookSelection && !draft.manuallySelectBooks && draft.bookIds.isEmpty {
                        Text("不绑定账本时可使用匿名均分；首页和流水统计只计算你自己的份额。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("分期") {
                    OCRInstallmentEditor(
                        isEnabled: $draft.installmentEnabled,
                        months: $draft.installmentMonths,
                        startMonth: $draft.installmentStartMonth
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
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
                        onSave(updated, draft)
                        dismiss()
                    }
                }
            }
            .task {
                if store.categories.isEmpty { await store.loadCategories() }
                if item.presetKey == "meituan_enterprise_meal", draft.offsetCategoryId == nil {
                    draft.offsetCategoryId = ocrOffsetIncomeCategoryID(
                        in: store.flattenedCategories,
                        presetKey: item.presetKey
                    )
                }
                if store.books.isEmpty { await store.loadBooks() }
            }
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

private struct OCRInstallmentEditor: View {
    @Binding var isEnabled: Bool
    @Binding var months: Int
    @Binding var startMonth: Date

    var body: some View {
        Group {
            Toggle("启用分期", isOn: $isEnabled)
                .onChange(of: isEnabled) { _, enabled in
                    if enabled && months < 2 {
                        months = 2
                    }
                }
            if isEnabled {
                Stepper("分期月数：\(months)", value: $months, in: 2...24)
                DatePicker("起始月份", selection: $startMonth, displayedComponents: .date)
            }
        }
    }
}

private struct OCRBookSplitEditor: View {
    @Binding var bookIds: [Int]
    @Binding var bookId: Int?
    @Binding var splitSettings: [Int: TransactionLedgerSplitDraft]
    @Binding var hasExplicitSelection: Bool
    @Binding var manuallySelectBooks: Bool
    let books: [LedgerBook]
    let automaticBooks: [LedgerBook]

    private enum BindingMode: String, CaseIterable, Identifiable {
        case automatic, unbound, selected
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: "自动归集"
            case .unbound: "不绑定账本"
            case .selected: "选择账本"
            }
        }
    }

    private var mode: BindingMode {
        get {
            guard hasExplicitSelection else { return .automatic }
            return manuallySelectBooks ? .selected : .unbound
        }
        nonmutating set {
            switch newValue {
            case .automatic:
                hasExplicitSelection = false
                manuallySelectBooks = false
                bookIds = []
                bookId = nil
            case .unbound:
                hasExplicitSelection = true
                manuallySelectBooks = false
                bookIds = []
                bookId = nil
            case .selected:
                hasExplicitSelection = true
                manuallySelectBooks = true
            }
        }
    }

    private var modeBinding: Binding<BindingMode> {
        Binding(get: { mode }, set: { mode = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("账本归集")
                .font(.headline)
            Picker("账本归集", selection: modeBinding) {
                ForEach(BindingMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if mode == .automatic {
                Label("按账本的自动归集规则选择账本；分账设置仍按每本账分别处理。", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if automaticBooks.isEmpty {
                    Text("当前流水不符合任何自动归集账本的条件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(automaticBooks) { book in
                        ledgerSplitCard(book)
                    }
                }
            } else if mode == .unbound {
                Label("此流水不关联主题账本。", systemImage: "tray")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("可多选；每本账本的付款人和分账成员互不影响。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(books) { book in
                        Button { toggleBook(book) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: bookIds.contains(book.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(bookIds.contains(book.id) ? Color.accentColor : Color.secondary)
                                Text(book.name).foregroundStyle(.primary)
                                Spacer()
                                Text(book.splitEnabled ? "多人分账" : "不分账")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if bookIds.contains(book.id) {
                            ledgerSplitCard(book)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear(perform: seedMissingDefaults)
        .onChange(of: bookIds) { _, _ in seedMissingDefaults() }
    }

    @ViewBuilder
    private func ledgerSplitCard(_ book: LedgerBook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: book.splitEnabled ? "person.2.fill" : "person.fill")
                    .foregroundStyle(.tint)
                Text(book.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(book.splitEnabled ? "本账本独立分账" : "此账本不开分账")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if book.splitEnabled {
                let participants = book.participants
                Picker("付款人", selection: payerBinding(for: book, participants: participants)) {
                    ForEach(participants) { participant in
                        Text(participant.name).tag(participant.id)
                    }
                }
                Text("参与分账成员（默认只有“我”，可选一人或多人）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(participants) { participant in
                    Toggle(participant.name, isOn: memberBinding(for: book, participant: participant))
                        .font(.subheadline)
                }
                Text("付款人和参与成员仅作用于“\(book.name)”；不影响其他绑定账本。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("该账本未启用多人分账，保存后此账本按整笔金额统计。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toggleBook(_ book: LedgerBook) {
        hasExplicitSelection = true
        if bookIds.contains(book.id) {
            bookIds.removeAll { $0 == book.id }
        } else {
            bookIds.append(book.id)
            seedDefault(for: book)
        }
        bookId = bookIds.first
    }

    private func seedMissingDefaults() {
        for book in books where bookIds.contains(book.id) {
            seedDefault(for: book)
        }
        bookId = bookIds.first
    }

    private func seedDefault(for book: LedgerBook) {
        guard book.splitEnabled, splitSettings[book.id] == nil else { return }
        let own = book.participants.first(where: { $0.name == "我" }) ?? book.participants.first
        splitSettings[book.id] = TransactionLedgerSplitDraft(
            payerParticipantId: own?.id,
            splitParticipantIds: own.map { [$0.id] } ?? []
        )
    }

    private func payerBinding(for book: LedgerBook, participants: [BookParticipant]) -> Binding<String> {
        Binding(
            get: {
                splitSettings[book.id]?.payerParticipantId
                    ?? participants.first(where: { $0.name == "我" })?.id
                    ?? participants.first?.id
                    ?? ""
            },
            set: { newValue in
                var setting = currentSetting(for: book)
                setting.payerParticipantId = newValue
                splitSettings[book.id] = setting
            }
        )
    }

    private func memberBinding(for book: LedgerBook, participant: BookParticipant) -> Binding<Bool> {
        Binding(
            get: { currentSetting(for: book).splitParticipantIds.contains(participant.id) },
            set: { enabled in
                var setting = currentSetting(for: book)
                if enabled, !setting.splitParticipantIds.contains(participant.id) {
                    setting.splitParticipantIds.append(participant.id)
                } else if !enabled, setting.splitParticipantIds.count > 1 {
                    setting.splitParticipantIds.removeAll { $0 == participant.id }
                }
                splitSettings[book.id] = setting
            }
        )
    }

    private func currentSetting(for book: LedgerBook) -> TransactionLedgerSplitDraft {
        if let setting = splitSettings[book.id] { return setting }
        let own = book.participants.first(where: { $0.name == "我" }) ?? book.participants.first
        return TransactionLedgerSplitDraft(payerParticipantId: own?.id, splitParticipantIds: own.map { [$0.id] } ?? [])
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

/// Explicit document picker wrapper. Using the delegate lets us close the
/// picker immediately for both success and cancellation, instead of relying
/// on the presentation state callback timing of `.fileImporter`.
private struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // A generic data type accepts CSV/TXT/XLSX/PDF/HTML exports from both
        // iCloud Drive and third-party Files providers. Importing as a copy
        // avoids provider hand-off stalls when the source is cloud-backed.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: () -> Void
        private var didFinish = false

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !didFinish else { return }
            didFinish = true
            let callback = onPick
            // 文件提供商的回调不保证和 SwiftUI 状态更新处于同一个主线程。
            // 先在主线程关闭 sheet 并启动解析，再结束 UIKit picker；不要把
            // 解析任务放在 dismiss completion 里，否则部分提供商不会回调它。
            DispatchQueue.main.async {
                callback(urls)
                controller.dismiss(animated: true)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !didFinish else { return }
            didFinish = true
            let callback = onCancel
            DispatchQueue.main.async {
                callback()
                controller.dismiss(animated: true)
            }
        }
    }
}
     // ignored legacy brace
        // ignored legacy close
    // ignored legacy close
// ignored legacy close
// Removed stray token that broke compilation.
