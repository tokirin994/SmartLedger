import SwiftUI
import UIKit

struct CategoriesView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var showCreateSheet = false
    @State private var selectedFlowType: FlowType = .expense
    @State private var searchText = ""
    @State private var deletionMessage: String?
    @State private var isReordering = false
    @State private var draggedCategoryID: Int?
    @State private var dropTargetID: Int?
    @State private var dropAfterTarget = false
    @State private var categoryRowFrames: [Int: CGRect] = [:]
    @State private var listViewportFrame: CGRect = .zero
    @State private var lastDragLocation: CGPoint?
    @State private var autoScrollDirection: Int?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    if isReordering {
                        Label("拖到列表边缘可自动滚动；仅能在同级分类间排序", systemImage: "arrow.up.and.down")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
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

                ScrollViewReader { scrollProxy in
                    List {
                        Color.clear
                            .frame(height: 6)
                            .listRowInsets(.init())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        // OutlineGroup preserves the hierarchy; rows remain identifiable
                        // so edge auto-scroll can reveal off-screen siblings while dragging.
                        OutlineGroup(filteredRoots, children: \.outlineChildren) { category in
                            CategoryListRow(
                                category: category,
                                allowsReordering: isReordering,
                                draggedCategoryID: $draggedCategoryID,
                                dropTargetID: $dropTargetID,
                                dropAfterTarget: $dropAfterTarget,
                                onDeletionFailure: { message in deletionMessage = message },
                                onDragChanged: updateReorderTarget,
                                onDragEnded: finishReorder
                            )
                                .id(category.id)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    // Prevent finger movement from accidentally scrolling the list
                    // during a reorder; the ScrollViewReader still performs the
                    // deliberate edge auto-scroll below.
                    .scrollDisabled(draggedCategoryID != nil)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: CategoryListViewportPreferenceKey.self, value: proxy.frame(in: .global))
                        }
                    }
                    .onPreferenceChange(CategoryRowFramePreferenceKey.self) { frames in
                        categoryRowFrames = frames
                        if let draggedCategoryID, let lastDragLocation {
                            updateReorderTarget(sourceID: draggedCategoryID, location: lastDragLocation)
                        }
                    }
                    .onPreferenceChange(CategoryListViewportPreferenceKey.self) { frame in
                        listViewportFrame = frame
                        updateAutoScrollDirection()
                    }
                    .task(id: autoScrollDirection) {
                        guard let direction = autoScrollDirection else { return }
                        while !Task.isCancelled {
                            scrollToNextSibling(direction: direction, using: scrollProxy)
                            try? await Task.sleep(nanoseconds: 420_000_000)
                        }
                    }
                    .appBackdrop()
                }
            }
            .navigationTitle("分类")
            .searchable(text: $searchText, prompt: "搜索分类名")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if isReordering { finishReorder() }
                        withAnimation(.snappy(duration: 0.22)) { isReordering.toggle() }
                    } label: {
                        Label(isReordering ? "完成" : "排序", systemImage: isReordering ? "checkmark" : "arrow.up.and.down")
                    }
                    .disabled(!searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
            .alert("无法删除分类", isPresented: Binding(get: { deletionMessage != nil }, set: { if !$0 { deletionMessage = nil } })) {
                Button("知道了", role: .cancel) { deletionMessage = nil }
            } message: {
                Text(deletionMessage ?? "")
            }
            .task {
                if store.categories.isEmpty {
                    await store.loadCategories()
                }
            }
            .onChange(of: searchText) { _, value in
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    withAnimation(.snappy(duration: 0.22)) { isReordering = false }
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

    private func updateReorderTarget(sourceID: Int, location: CGPoint) {
        lastDragLocation = location
        updateAutoScrollDirection()
        guard let source = store.flattenedCategories.first(where: { $0.id == sourceID }) else { return }
        let siblings = store.flattenedCategories.filter {
            $0.id != sourceID && $0.parentId == source.parentId && $0.flowType == source.flowType
        }
        guard let destination = siblings.compactMap({ category -> (LedgerCategory, CGRect)? in
            guard let frame = categoryRowFrames[category.id] else { return nil }
            return (category, frame)
        }).min(by: { lhs, rhs in
            verticalDistance(from: location.y, to: lhs.1) < verticalDistance(from: location.y, to: rhs.1)
        }) else { return }

        let after = location.y >= destination.1.midY
        guard dropTargetID != destination.0.id || dropAfterTarget != after else { return }
        let changedTarget = dropTargetID != destination.0.id
        withAnimation(.interactiveSpring(response: 0.20, dampingFraction: 0.82)) {
            dropTargetID = destination.0.id
            dropAfterTarget = after
        }
        if changedTarget { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    private func verticalDistance(from y: CGFloat, to frame: CGRect) -> CGFloat {
        if frame.minY...frame.maxY ~= y { return 0 }
        return min(abs(y - frame.minY), abs(y - frame.maxY))
    }

    private func finishReorder() {
        let sourceID = draggedCategoryID
        let targetID = dropTargetID
        let after = dropAfterTarget
        draggedCategoryID = nil
        dropTargetID = nil
        lastDragLocation = nil
        autoScrollDirection = nil
        guard let sourceID, let targetID, sourceID != targetID else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await store.reorderCategory(sourceID, relativeTo: targetID, after: after) }
    }

    private func updateAutoScrollDirection() {
        guard draggedCategoryID != nil, let y = lastDragLocation?.y, listViewportFrame.height > 0 else {
            autoScrollDirection = nil
            return
        }
        let edgeInset: CGFloat = 68
        if y < listViewportFrame.minY + edgeInset {
            autoScrollDirection = -1
        } else if y > listViewportFrame.maxY - edgeInset {
            autoScrollDirection = 1
        } else {
            autoScrollDirection = nil
        }
    }

    private func scrollToNextSibling(direction: Int, using proxy: ScrollViewProxy) {
        guard let sourceID = draggedCategoryID,
              let source = store.flattenedCategories.first(where: { $0.id == sourceID }) else { return }
        let siblings = store.flattenedCategories
            .filter { $0.parentId == source.parentId && $0.flowType == source.flowType }
            .sorted { $0.sortOrder < $1.sortOrder }
        let visibleSiblings = siblings.compactMap { sibling -> (LedgerCategory, CGRect)? in
            guard let frame = categoryRowFrames[sibling.id], frame.maxY > listViewportFrame.minY, frame.minY < listViewportFrame.maxY else { return nil }
            return (sibling, frame)
        }
        guard !visibleSiblings.isEmpty else { return }

        if direction > 0 {
            guard let edge = visibleSiblings.max(by: { $0.1.maxY < $1.1.maxY }),
                  let index = siblings.firstIndex(where: { $0.id == edge.0.id }),
                  siblings.index(after: index) < siblings.endIndex else { return }
            let next = siblings[siblings.index(after: index)]
            withAnimation(.linear(duration: 0.32)) { proxy.scrollTo(next.id, anchor: .bottom) }
        } else {
            guard let edge = visibleSiblings.min(by: { $0.1.minY < $1.1.minY }),
                  let index = siblings.firstIndex(where: { $0.id == edge.0.id }),
                  index > siblings.startIndex else { return }
            let previous = siblings[siblings.index(before: index)]
            withAnimation(.linear(duration: 0.32)) { proxy.scrollTo(previous.id, anchor: .top) }
        }
    }

    private var filteredCount: Int {
        filteredRoots.map { $0.flattened().count }.reduce(0, +)
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
    @State private var saveFailureMessage: String?

    let title: String
    var preselectedFlowType: FlowType?
    var preselectedParentId: Int?
    var editingCategory: LedgerCategory?
    var onCreated: ((LedgerCategory) -> Void)?

    init(
        title: String = "新增分类",
        preselectedFlowType: FlowType? = nil,
        preselectedParentId: Int? = nil,
        editingCategory: LedgerCategory? = nil,
        onCreated: ((LedgerCategory) -> Void)? = nil
    ) {
        self.title = title
        self.preselectedFlowType = preselectedFlowType
        self.preselectedParentId = preselectedParentId
        self.editingCategory = editingCategory
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
                            iconPickerGrid(selected: $icon, previewColor: previewColor)
                                .padding(.top, 2)
                        }
                        .frame(maxHeight: 360)
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
            .dismissKeyboardWhenTappedOutside()
            .onAppear {
                if let preselectedFlowType {
                    flowType = preselectedFlowType
                }
                if let preselectedParentId {
                    parentId = preselectedParentId
                }
                if let editingCategory {
                    name = editingCategory.displayName
                    flowType = editingCategory.flowType
                    parentId = editingCategory.parentId
                    icon = editingCategory.icon ?? "folder"
                    color = editingCategory.color ?? "#5AA38B"
                } else if let parentId,
                          let parent = store.flattenedCategories.first(where: { $0.id == parentId }) {
                    // New children inherit the visual identity of their parent;
                    // the user can still choose another color below.
                    color = parent.color ?? color
                }
            }
            .onChange(of: parentId) { _, newParentId in
                guard editingCategory == nil,
                      let newParentId,
                      let parent = store.flattenedCategories.first(where: { $0.id == newParentId }) else { return }
                color = parent.color ?? color
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
                            if let editingCategory {
                                await store.updateCategory(editingCategory.id, draft: draft)
                            } else {
                                await store.createCategory(draft)
                            }
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
    private func iconPickerGrid(selected: Binding<String>, previewColor: Color) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(DisplayPalette.iconGroups) { group in
                VStack(alignment: .leading, spacing: 7) {
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(group.icons, id: \.self) { option in
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
                            .accessibilityLabel(option)
                        }
                    }
                }
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
    let allowsReordering: Bool
    @Binding var draggedCategoryID: Int?
    @Binding var dropTargetID: Int?
    @Binding var dropAfterTarget: Bool
    let onDeletionFailure: (String) -> Void
    let onDragChanged: (Int, CGPoint) -> Void
    let onDragEnded: () -> Void
    @State private var showEditSheet = false

    var body: some View {
        Group {
            if allowsReordering {
                rowCard
                    .simultaneousGesture(reorderGesture)
            } else {
                rowCard
            }
        }
        .sheet(isPresented: $showEditSheet) {
            CategoryEditorView(title: "修改分类", editingCategory: category)
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private var rowCard: some View {
        if allowsReordering {
            rowCardContent
        } else {
            rowCardContent
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button { showEditSheet = true } label: { Label("修改", systemImage: "pencil") }
                        .tint(.blue)
                    Button(role: .destructive) {
                        delete(category)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
        }
    }

    private var rowCardContent: some View {
        row
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(categoryBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isDropTarget ? Color.accentColor.opacity(0.8) : (allowsReordering ? Color.accentColor.opacity(0.16) : .clear), lineWidth: isDropTarget ? 2 : 1)
            }
            .overlay(alignment: dropAfterTarget ? .bottom : .top) {
                if isDropTarget {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 4)
                        .padding(.horizontal, 10)
                        .shadow(color: Color.accentColor.opacity(0.45), radius: 5)
                        .allowsHitTesting(false)
                }
            }
            .opacity(allowsReordering && draggedCategoryID == category.id ? 0.42 : 1)
            .scaleEffect(allowsReordering && draggedCategoryID == category.id ? 1.015 : 1)
            .animation(.interactiveSpring(response: 0.20, dampingFraction: 0.82), value: draggedCategoryID)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CategoryRowFramePreferenceKey.self,
                        value: [category.id: proxy.frame(in: .global)]
                    )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture {
                if !allowsReordering { showEditSheet = true }
            }
    }

    private var row: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(categoryColor)
                    .opacity(0.12)
                Image(systemName: category.icon ?? "folder")
                    .foregroundStyle(categoryColor)
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

        }
        .padding(.vertical, 1)
    }

    private var dragPreview: some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon ?? "folder")
                .foregroundStyle(categoryColor)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.displayName)
                    .font(.body.weight(.semibold))
                Text("拖动以调整顺序")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Image(systemName: "arrow.up.and.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(categoryColor.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }

    private var reorderGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.42, maximumDistance: 7)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    // Keep scrolling available until the long-press actually moves.
                    break
                case .second(true, let drag?):
                    if draggedCategoryID != category.id {
                        withAnimation(.interactiveSpring(response: 0.20, dampingFraction: 0.82)) {
                            draggedCategoryID = category.id
                            dropTargetID = nil
                        }
                    }
                    onDragChanged(category.id, drag.location)
                default:
                    break
                }
            }
            .onEnded { value in
                if case .second(true, _) = value { onDragEnded() }
            }
    }

    private var categoryColor: Color { Color(hex: category.color ?? (category.flowType == .expense ? "#F59E0B" : "#22C55E")) }

    private var categoryBackground: Color {
        category.children.isEmpty ? Color(UIColor.secondarySystemBackground) : categoryColor.opacity(0.12)
    }

    private var isDropTarget: Bool {
        allowsReordering && dropTargetID == category.id && draggedCategoryID != category.id
    }

    private func delete(_ item: LedgerCategory) {
        Task {
            store.errorMessage = nil
            await store.deleteCategory(item.id)
            if let error = store.errorMessage {
                // 该错误已由分类页的专用弹窗接管；及时消费全局状态，
                // 否则切换到首页时 Dashboard 会再次展示同一条错误。
                store.errorMessage = nil
                onDeletionFailure(error)
            }
        }
    }
}

private struct CategoryRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

private struct CategoryListViewportPreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct CreateCategoryView: View {
    var body: some View {
        CategoryEditorSheet()
    }
}
/* /* Legacy duplicate generated tail removed.
}
// duplicate tail marker {
// duplicate tail removed
t()
    }
}
*/
*/
/*
        guard isDragging else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            isDragging = false
            dragOffset = .zero
        }
        lastMoveStep = 0
    }

    private var categoryColor: Color { Color(hex: category.color ?? (category.flowType == .expense ? "#F59E0B" : "#22C55E")) }

    private var categoryBackground: Color {
        category.children.isEmpty ? Color(UIColor.secondarySystemBackground) : categoryColor.opacity(0.12)
    }

    private func delete(_ item: LedgerCategory) {
        Task {
            store.errorMessage = nil
            await store.deleteCategory(item.id)
            if let error = store.errorMessage {
                // 该错误已由分类页的专用弹窗接管；及时消费全局状态，
                // 否则切换到首页时 Dashboard 会再次展示同一条错误。
                store.errorMessage = nil
                onDeletionFailure(error)
            }
        }
    }
}

private struct CreateCategoryView: View {
    var body: some View {
        CategoryEditorSheet()
    }
}
/* /* Legacy duplicate generated tail removed.
}
// duplicate tail marker {
// duplicate tail removed
t()
    }
}
*/
*/
// legacy generated tail removed
*/
// il removed
/*
rivate var categoryBackground: Color {
        category.children.isEmpty ? Color(UIColor.secondarySystemBackground) : categoryColor.opacity(0.12)
    }

    private func delete(_ item: LedgerCategory) {
        Task {
            store.errorMessage = nil
            await store.deleteCategory(item.id)
            if let error = store.errorMessage {
                // 该错误已由分类页的专用弹窗接管；及时消费全局状态，
                // 否则切换到首页时 Dashboard 会再次展示同一条错误。
                store.errorMessage = nil
                onDeletionFailure(error)
            }
        }
    }
}

private struct CreateCategoryView: View {
    var body: some View {
        CategoryEditorSheet()
    }
}
/* /* Legacy duplicate generated tail removed.
}
// duplicate tail marker {
// duplicate tail removed
t()
    }
}
*/
*/
// legacy generated tail removed
*/
// il removed

// legacy generated tail removed
// legacy generated tail removed
/*
rivate var categoryBackground: Color {
        category.children.isEmpty ? Color(UIColor.secondarySystemBackground) : categoryColor.opacity(0.12)
    }

    private func delete(_ item: LedgerCategory) {
        Task {
            store.errorMessage = nil
            await store.deleteCategory(item.id)
            if let error = store.errorMessage {
                // 该错误已由分类页的专用弹窗接管；及时消费全局状态，
                // 否则切换到首页时 Dashboard 会再次展示同一条错误。
                store.errorMessage = nil
                onDeletionFailure(error)
            }
        }
    }
}

private struct CreateCategoryView: View {
    var body: some View {
        CategoryEditorSheet()
    }
}
/* /* Legacy duplicate generated tail removed.
}
// duplicate tail marker {
// duplicate tail removed
t()
    }
}
*/
*/
// legacy generated tail removed
*/
// il removed

// legacy generated tail removed
// gacy generated tail removed
