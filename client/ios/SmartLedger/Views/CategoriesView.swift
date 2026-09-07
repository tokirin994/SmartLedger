import SwiftUI

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
                    ForEach(filteredRoots) { category in
                        CategoryRowView(category: category)
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
        filteredRoots.reduce(0) { partial, category in
            partial + category.flattened.count
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

struct CategoryEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var flowType: FlowType = .expense
    @State private var parentId: Int?
    @State private var icon = "folder"
    @State private var color = "#5AA38B"
    @State private var iconPickerExpanded = false

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
                        selectedCategoryId: $parentId,
                        flowType: flowType
                    )
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
                            let draft = CategoryDraft(
                                name: name,
                                flowType: flowType,
                                icon: icon.isEmpty ? nil : icon,
                                color: color.isEmpty ? nil : color,
                                parentId: parentId
                            )
                            await store.createCategory(draft)
                            if let created = store.flattenedCategories.first(where: {
                                $0.name == name.trimmingCharacters(in: .whitespacesAndNewlines) &&
                                $0.flowType == flowType &&
                                $0.parentId == parentId
                            }) {
                                onCreated?(created)
                            }
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
                            .fill(selected.wrappedValue == option ? previewColor.opacity(0.16) : Color.systemBackground)
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
                        .fill(swatchColor)
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

private struct CategoryNodeView: View {
    let category: LedgerCategory

    var body: some View {
        Group {
            if category.children.isEmpty {
                row(for: category)
            } else {
                DisclosureGroup {
                    VStack(spacing: 6) {
                        ForEach(category.children) { child in
                            if child.children.isEmpty {
                                row(for: child)
                            } else {
                                CategoryNodeView(category: child)
                            }
                        }
                    }
                    .padding(.top, 6)
                    .padding(.leading, 10)
                } label: {
                    row(for: category)
                }
            }
        }
        .padding(12)
        .background(Color.secondarySystemBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(for item: LedgerCategory) -> some View {
        HStack {
            ZStack {
                Circle()
                    .fill(item.flowType == .expense ? Color.orange : Color.green)
                    .opacity(0.12)
                Image(systemName: item.icon ?? "folder")
                    .foregroundStyle(item.flowType == .expense ? .orange : .green)
                    .frame(width: 28)

            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading) {
                Text(item.displayName)
                    .font(.body.weight(.medium))
                Text("\(item.flowType.title) · 第 \(item.level) 级")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.children.isEmpty {
                Text("叶子")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.tertiarySystemBackground, in: Capsule())
            }
        }
        .padding(.vertical, 1)
    }
}

private struct CreateCategoryView: View {
    var body: some View {
        CategoryEditorSheet()
    }
}

private extension Color {
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let r, g, b: UInt64
        switch cleaned.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 24, 144, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

