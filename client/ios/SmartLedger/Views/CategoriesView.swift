import SwiftUI
import UIKit

struct CategoriesView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var showCreateSheet = false
    @State private var selectedFlowType: FlowType = .expense
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Picker("类型", selection: $selectedFlowType) {
                        ForEach(FlowType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        categoryStat(title: "一级分类", value: "\(filteredRoots.count)")
                        categoryStat(title: "总分类", value: "\(filteredCount)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top)

                List {
                    ForEach(categoryRows) { entry in
                        CategoryListRow(category: entry.category, depth: entry.depth)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .appBackdrop()
            }
            .navigationTitle("分类")
            .searchable(text: $searchText, prompt: "搜索分类名")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateCategoryView()
                    .environmentObject(store)
            }
            .task {
                if store.categories.isEmpty {
                    await store.loadCategories()
                }
            }
        }
        .appBackdrop()
    }

    private var filteredRoots: [LedgerCategory] {
        store.categories
            .filter { $0.flowType == selectedFlowType }
            .filter { searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || categoryMatches($0) }
    }

    private var filteredCount: Int {
        filteredRoots.map { $0.flattened().count }.reduce(0, +)
    }

    /// 每一个分类都是 List 中的独立行，二级及更深分类通过缩进表达层级，
    /// 从而保证任意分类都能正常左滑操作。
    private var categoryRows: [CategoryListEntry] {
        flattenedRows(from: filteredRoots)
    }

    private func flattenedRows(from nodes: [LedgerCategory], depth: Int = 0) -> [CategoryListEntry] {
        nodes.flatMap { category in
            [CategoryListEntry(category: category, depth: depth)]
                + flattenedRows(from: category.children, depth: depth + 1)
        }
    }

    private func categoryMatches(_ category: LedgerCategory) -> Bool {
        let keyword = searchText.lowercased()
        if keyword.isEmpty { return true }
        if category.name.lowercased().contains(keyword) { return true }
        return category.children.contains(where: categoryMatches)
    }

    private func categoryStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 18, strokeOpacity: 0.22)
    }
}

private struct CategoryListEntry: Identifiable {
    let category: LedgerCategory
    let depth: Int
    var id: Int { category.id }
}

struct CategoryEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var flowType: FlowType = .expense
    @State private var parentId: Int?
    @State private var icon = "folder"
    @State private var color = "#5AA38B"
    @State private var iconPickerExpanded = false
    @State private var saveFailureMessage: String?

    let title: String
    var preselectedFlowType: FlowType?
    var preselectedParentId: Int?
    var onCreated: ((LedgerCategory) -> Void)?

    init(
        title: String = "新增分类",
        preselectedFlowType: FlowType? = nil,
        preselectedParentId: Int? = nil,
        onCreated: ((LedgerCategory) -> Void)? = nil
    ) {
        self.title = title
        self.preselectedFlowType = preselectedFlowType
        self.preselectedParentId = preselectedParentId
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("分类名称", text: $name)
                    Picker("类型", selection: $flowType) {
                        ForEach(FlowType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(preselectedFlowType != nil)
                }

                Section("层级设置") {
                    HierarchicalCategoryPicker(
                        title: "上级分类",
                        categories: store.categories.filter { $0.flowType == flowType },
                        placeholder: "作为一级分类",
                        helperText: nil,
                        selectedCategoryId: $parentId,
                        flowType: flowType,
                        onCreateCategory: nil
                    )
                    Text("可选择任意已有分类作为上级；没有子分类的项目会直接选中，不显示空层级。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("展示信息") {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            iconPickerExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(previewColor.opacity(0.18))
                                .frame(width: 34, height: 34)
                                .overlay {
                                    Image(systemName: icon.isEmpty ? "folder" : icon)
                                        .foregroundStyle(previewColor)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("图标")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(icon.isEmpty ? "选择一个分类图标" : icon)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: iconPickerExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    if iconPickerExpanded {
                        ScrollView {
                            iconPickerGrid(options: DisplayPalette.icons, selected: $icon, previewColor: previewColor)
                                .padding(.top, 2)
                        }
                        .frame(maxHeight: 220)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(previewColor)
                                .frame(width: 34, height: 34)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("分类颜色")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("选择一个颜色")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        colorPickerGrid(options: DisplayPalette.colors, selected: $color)
                    }
                }
            }
            .navigationTitle(title)
            .onAppear {
                if let preselectedFlowType {
                    flowType = preselectedFlowType
                }
                if let preselectedParentId {
                    parentId = preselectedParentId
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        Task {
                            store.errorMessage = nil
                            let draft = CategoryDraft(
                                name: name,
                                flowType: flowType,
                                icon: icon.isEmpty ? nil : icon,
                                color: color.isEmpty ? nil : color,
                                parentId: parentId
                            )
                            await store.createCategory(draft)
                            if let error = store.errorMessage {
                                saveFailureMessage = error
                                return
                            }
                            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let candidates = store.flattenedCategories.filter { $0.name == trimmedName }
                            if let created = candidates.first(where: { $0.flowType == flowType && $0.parentId == parentId }) {
                                onCreated?(created)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .alert("无法保存分类", isPresented: Binding(get: { saveFailureMessage != nil }, set: { if !$0 { saveFailureMessage = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(saveFailureMessage ?? "请检查分类信息后重试。")
            }
        }
    }

    private var previewColor: Color {
        if color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return flowType == .expense ? .orange : .green
        }
        return Color(hex: color)
    }

    @ViewBuilder
    private func iconPickerGrid(options: [String], selected: Binding<String>, previewColor: Color) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options, id: \.self) { option in
                Button {
                    selected.wrappedValue = option
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected.wrappedValue == option ? previewColor.opacity(0.16) : Color(UIColor.systemBackground))
                        Image(systemName: option)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(selected.wrappedValue == option ? previewColor : .primary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(selected.wrappedValue == option ? previewColor : Color.clear, lineWidth: 1.5)
                            )
                    }
                    .frame(height: 52)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selected.wrappedValue)
    }

    @ViewBuilder
    private func colorPickerGrid(options: [String], selected: Binding<String>) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(options, id: \.self) { option in
                Button {
                    selected.wrappedValue = option
                } label: {
                    Circle()
                        .fill(Color(hex: option))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(selected.wrappedValue == option ? Color.primary : Color.clear, lineWidth: 2)
                                .padding(-4)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CategoryListRow: View {
    @EnvironmentObject private var store: LedgerStore
    let category: LedgerCategory
    let depth: Int
    @State private var deletionMessage: String?

    var body: some View {
        row
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    delete(category)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        .alert("无法删除分类", isPresented: deletionAlertPresented) {
            Button("知道了", role: .cancel) {
                deletionMessage = nil
            }
        } message: {
            Text(deletionMessage ?? "")
        }
        .contextMenu {
            Button(role: .destructive) { delete(category) } label: { Label("删除分类", systemImage: "trash") }
        }
    }

    private var row: some View {
        HStack {
            if depth > 0 {
                Color.clear
                    .frame(width: CGFloat(min(depth, 4)) * 16)
            }

            ZStack {
                Circle()
                    .fill(category.flowType == .expense ? Color.orange : Color.green)
                    .opacity(0.12)
                Image(systemName: category.icon ?? "folder")
                    .foregroundStyle(category.flowType == .expense ? .orange : .green)
                    .frame(width: 28)

            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading) {
                Text(category.displayName)
                    .font(.body.weight(.medium))
                Text("\(category.flowType.title) · 第 \(category.level) 级")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if category.children.isEmpty {
                Text("叶子")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.tertiarySystemBackground), in: Capsule())
            }
        }
        .padding(.vertical, 1)
    }

    private var deletionAlertPresented: Binding<Bool> {
        Binding(
            get: { deletionMessage != nil },
            set: { if !$0 { deletionMessage = nil } }
        )
    }

    private func delete(_ item: LedgerCategory) {
        Task {
            store.errorMessage = nil
            await store.deleteCategory(item.id)
            if let error = store.errorMessage {
                deletionMessage = error
            }
        }
    }
}

private struct CreateCategoryView: View {
    var body: some View {
        CategoryEditorSheet()
    }
}
// Duplicate declaration removed; the private view above is the sheet entry point.
/*
    }
}
*/
