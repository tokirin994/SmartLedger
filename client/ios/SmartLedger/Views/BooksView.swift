import SwiftUI
import UIKit

struct BooksView: View {
  @EnvironmentObject private var store: LedgerStore
  @State private var showCreateSheet = false
  @State private var navPath = NavigationPath()
  @State private var searchText = ""
  @State private var pendingDeleteBook: LedgerBook?

  var body: some View {
    NavigationStack(path: $navPath) {
      List {
        Section {
          summaryRow
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)

          HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(.secondary)

            TextField("搜索账本标题", text: $searchText)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()

            if !searchText.isEmpty {
              Button {
                searchText = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.tertiary)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 12)
          .glassCard(cornerRadius: 18, strokeOpacity: 0.22)
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
          .listRowBackground(Color.clear)

          if filteredBooks.isEmpty {
            Section {
              ContentUnavailableView(
                searchText.isEmpty ? "暂无主题账本" : "没有匹配的账本",
                systemImage: "books.vertical"
              )
              .frame(maxWidth: .infinity)
              .padding(.vertical, 36)
              .listRowBackground(Color.clear)
            }
          } else {
            Section {
              ForEach(filteredBooks) { book in
                NavigationLink {
                  BookDetailView(book: book)
                    .environmentObject(store)
                } label: {
                  bookCard(book)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                  Button {
                    Task { await store.setBookPinned(book.id, pinned: !book.isPinned) }
                  } label: {
                    Label(book.isPinned ? "取消置顶" : "置顶", systemImage: book.isPinned ? "pin.slash" : "pin")
                  }
                  .tint(.orange)

                  Button(role: .destructive) {
                    pendingDeleteBook = book
                  } label: {
                    Label("删除", systemImage: "trash")
                  }
                }
              }
            }
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("账本")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              Task { await store.loadBooks() }
            } label: {
              Image(systemName: "arrow.clockwise")
            }
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
          CreateBookView()
            .environmentObject(store)
        }
        .refreshable {
          if store.books.isEmpty {
            await store.loadBooks()
          }
        }
        .alert(
          pendingDeleteBook == nil ? "" : "删除账本？",
          isPresented: Binding(
            get: { pendingDeleteBook != nil },
            set: { _ in pendingDeleteBook = nil }
          ),
          presenting: pendingDeleteBook
        ) {
          Button("取消", role: .cancel) {
            pendingDeleteBook = nil
          }
          Button("删除", role: .destructive) {
            Task {
              await store.deleteBook(book.id)
              pendingDeleteBook = nil
            }
          }
        } message: { _ in
          Text("账本不会被删除，但流水本身不会删除，只会移除与这个账本的关联。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartLedgerNewTabRoot)) { note in
          guard let tab = note.object as? RootTab, tab == .books else { return }
          navPath = NavigationPath()
        }

      private var summaryRow: some View {
        HStack(spacing: 12) {
          stat(title: "账本数", value: "\(filteredBooks.count)", tint: .blue)
          stat(title: "主题支出", value: totalExpense.cnText, tint: .orange)
          stat(title: "主题收入", value: totalIncome.cnText, tint: .green)
        }
      }

      private var filteredBooks: [LedgerBook] {
        let key = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return store.books
          .filter { book in
            guard !key.isEmpty else { return true }
            return book.name.localizedCaseInsensitiveContains(key) ||
              (book.note?.localizedCaseInsensitiveContains(key) ?? false)
          }
          .sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
              return lhs.isPinned && !rhs.isPinned
            }
            if lhs.startDate != rhs.startDate {
              return (lhs.startDate ?? .distantPast) > (rhs.startDate ?? .distantPast)
            }
            return lhs.id > rhs.id
          }
      }

      private func stat(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
          Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(value)
            .font(.headline.weight(.bold))
            .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 18, strokeOpacity: 0.22)
      }

      private func bookCard(_ book: LedgerBook) -> some View {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Circle()
              .fill(Color.accentColor.opacity(0.12))
              .frame(width: 44, height: 44)
            Image(systemName: book.icon ?? "book.vertical.fill")
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
              Text(book.name)
                .font(.headline)
                .foregroundStyle(.primary)

              if book.isPinned {
                Image(systemName: "pin.fill")
                  .font(.caption)
                  .foregroundStyle(.orange)
              }
              if let note = book.note, !note.isEmpty {
                Text(note)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }

            Spacer()

            Image(systemName: "chevron.right")
              .font(.callout)
              .foregroundStyle(.tertiary)
          }

          HStack(spacing: 10) {
            pill("\(book.transactionCount) 笔", systemImage: "list.bullet", tint: .orange)
            pill("支出 \(book.expenseAmount.cnText)", systemImage: "arrow.up.right.circle", tint: .orange)
            if book.incomeAmount > 0 {
              pill("收入 \(book.incomeAmount.cnText)", systemImage: "arrow.down.left.circle", tint: .green)
            }
          }

          HStack {
            Text("余额 \(book.balance.cnText)")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(book.balance >= 0 ? .green : .primary)
            Spacer()
            if let start = book.startDate {
              Text(dateRangeText(start: start, end: book.endDate))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        .padding(16)
        .glassCard(cornerRadius: 24, strokeOpacity: 0.24)
      }

      private func pill(_ text: String, systemImage: String, tint: Color = .blue) -> some View {
        Label(text, systemImage: systemImage)
          .font(.caption.weight(.medium))
          .foregroundStyle(tint)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(tint.opacity(0.08), in: Capsule())
      }

      private func dateRangeText(start: Date, end: Date?) -> String {
        let startText = start.formatted(date: .abbreviated, time: .omitted)
        if let end {
          return "\(startText) - \(end.formatted(date: .abbreviated, time: .omitted))"
        }
        return "始于 \(startText)"
      }

      private var totalExpense: Double { filteredBooks.reduce(0) { $0 + $1.expenseAmount } }
      private var totalIncome: Double { filteredBooks.reduce(0) { $0 + $1.incomeAmount } }
    }
  }
}

private struct CreateBookView: View {
  @EnvironmentObject private var store: LedgerStore
  @EnvironmentObject private var settings: AppSettings
  @Environment(\.dismiss) private var dismiss

  @State private var name = ""
  @State private var icon = "books.vertical.fill"
  @State private var color = "#0882F6"
  @State private var note = ""
  @State private var startDate = Date()
  @State private var hasEndDate = false
  @State private var endDate = Date()
  @State private var autoCollectEnabled = false
  @State private var autoCollectCurrency = false
  @State private var collectExistingNow = false
  @State private var bookLimitEnabled = false
  @State private var budgetLimitAmount = ""
  @State private var iconPickerExpanded = false
  @State private var splitEnabled = false
  @State private var participants: [String] = ["我"]
  @State private var newParticipantName = ""
  @State private var selectedAutoCollectCategoryIds: Set<Int> = []
  @State private var showUnsavedChangesDialog = false
init(editingBook: LedgerBook? = nil) {
   self.editingBook = editingBook
   self.initialSnapshot = BookEditorStateSnapshot(book: editingBook)

   if let editingBook {
     _name = State(initialValue: editingBook.name)
     _icon = State(initialValue: editingBook.icon ?? "books.vertical.fill")
     _color = State(initialValue: editingBook.color ?? "#0882F6")
     _note = State(initialValue: editingBook.note ?? "")
     _startDate = State(initialValue: editingBook.startDate ?? Date())
     _endDate = State(initialValue: editingBook.endDate ?? Date())
     _hasEndDate = State(initialValue: editingBook.endDate != nil)
     _autoCollectEnabled = State(initialValue: editingBook.autoCollectEnabled)
     _budgetLimitEnabled = State(initialValue: editingBook.budgetLimitEnabled)
     _budgetLimitAmount = State(initialValue: editingBook.budgetLimitAmount.map { String(format: "%.0f", $0) } ?? "")
     _splitEnabled = State(initialValue: editingBook.splitEnabled)
     _participants = State(initialValue: editingBook.participantNames.isEmpty ? ["我"] : editingBook.participantNames)
     _selectedAutoCollectCategoryIds = State(initialValue: Set(editingBook.autoCollectCategoryIds))
   }
 }

 var body: some View {
   NavigationStack {
     Form {
       Section("基础信息") {
         TextField("账本名称", text: $name)

         VStack(alignment: .leading, spacing: 10) {
           Button {
             withAnimation(.easeOut(duration: 0.2)) {
               iconPickerExpanded.toggle()
             }
           } label: {
             HStack(spacing: 12) {
               Circle()
                 .fill(previewColor.opacity(0.12))
                 .frame(width: 34, height: 34)
                 .overlay {
                   Image(systemName: icon.isEmpty ? "books.vertical.fill" : icon)
                     .foregroundStyle(previewColor)
                 }

               VStack(alignment: .leading, spacing: 4) {
                 Text("图标")
                   .font(.caption)
                   .foregroundStyle(.secondary)
                 Text(icon.isEmpty ? "选择一个图标" : icon)
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
               IconPickerGrid(options: DisplayPalette.icons, selected: $icon, previewColor: previewColor)
                 .padding(.top, 2)
             }
             .frame(maxHeight: 220)
           }
         }

         VStack(alignment: .leading, spacing: 10) {
           VStack(spacing: 12) {
             RoundedRectangle(cornerRadius: 8, style: .continuous)
               .fill(previewColor)
               .frame(height: 34)
           }

           VStack(alignment: .leading, spacing: 4) {
             Text("主题颜色")
               .font(.caption)
               .foregroundStyle(.secondary)
             Text("直接点选一个颜色")
               .font(.caption)
               .foregroundStyle(.secondary)
           }

           ColorPickerGrid(options: DisplayPalette.colors, selected: $color)

           Text("上述两个分别是：账本显示图标和主题颜色。只影响界面展示，不影响记账逻辑。")
             .font(.caption)
             .foregroundStyle(.secondary)
         }
       }

       Section("时间范围") {
         DatePicker("开始时间", selection: $startDate, displayedComponents: .date)
         Toggle("设置结束时间", isOn: $hasEndDate)

         if hasEndDate {
           DatePicker("结束时间", selection: $endDate, displayedComponents: .date)
         }

         Toggle("自动归集时间范围内流水", isOn: $autoCollectEnabled)

         if enabled && !autoCollectEnabled {
           collectExistingNow = false
           showAutoCollectConfirm = true
         } else {
           autoCollectEnabled = enabled
         }
       }

       if autoCollectEnabled {
         Text("*新添加流水保存时，范围内流水会自动归集到该账本。")
           .font(.footnote)
           .foregroundStyle(.secondary)

         NavigationLink {
           BookAutoCollectCategoryPickerView(selectedCategoryIds: $selectedAutoCollectCategoryIds)
             .environmentObject(store)
         } label: {
           HStack {
             Text("自动归集分类")
             Spacer()
             Text(autoCollectCategorySummary)
               .foregroundStyle(selectedAutoCollectCategoryIds.isEmpty ? .secondary : .primary)
               .multilineTextAlignment(.trailing)
           }
         }
       }

       Section("账本预算") {
         Toggle("启用账本预算", isOn: $budgetLimitEnabled)

         if budgetLimitEnabled {
           TextField("预算金额", text: $budgetLimitAmount)
             .keyboardType(.decimalPad)
           Text("*预算周期自动与账本时间一致：预算从开始到结束，结束时间跟随账本")
             .font(.footnote)
             .foregroundStyle(.secondary)
         }
       }

       Section("多人分摊") {
         Toggle("启用多人分摊", isOn: $splitEnabled)

         if splitEnabled {
           HStack(spacing: 10) {
             TextField("新增成员，例如：小王", text: $newParticipantName)
             Button {
               appendParticipant()
             } label: {
               Image(systemName: "plus.circle.fill")
             }
             .disabled(newParticipantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
           }

           if participants.isEmpty {
             ContentUnavailableView("暂无成员", systemImage: "person.2")
               .foregroundStyle(.blue)
           } else {
             ForEach(Array(participants.indices), id: \.self) { index in
               HStack(spacing: 10) {
                 Image(systemName: "person.circle.fill")
                   .foregroundStyle(.blue)

                 TextField("成员名称", text: Binding(
                   get: { participants[index] },
                   set: { participants[$0] = $1 }
                 ))

                 Button(role: .destructive) {
                   participants.remove(at: index)
                 } label: {
                   Image(systemName: "trash")
                 }
               }
             }
           }

           Button("恢复默认成员（我）") {
             participants = ["我"]
           }
           .font(.caption)
         }
       }
     }
     .navigationTitle(editingBook == nil ? "新建账本" : "账本设置")
     .toolbar {
       ToolbarItem(placement: .topBarLeading) {
         Button("取消") { attemptDismiss() }
       }
       ToolbarItem(placement: .topBarTrailing) {
         Button("保存") {
           Task {
             let draft = BookDraft(
               name: name,
               icon: icon.isEmpty ? nil : icon,
               color: color.isEmpty ? nil : color,
               note: note.isEmpty ? nil : note,
               startDate: startDate,
               endDate: hasEndDate ? endDate : nil,
               autoCollectEnabled: autoCollectEnabled,
               budgetLimitEnabled: budgetLimitEnabled,
               budgetLimitAmount: budgetLimitEnabled ? Double(budgetLimitAmount) : nil,
               budgetStartDate: budgetLimitEnabled && hasEndDate ? startDate : nil,
               budgetEndDate: budgetLimitEnabled && hasEndDate ? endDate : nil,
               participantNames: splitEnabled ? normalizedParticipants : [],
               isPinned: editingBook?.isPinned ?? false,
               autoCollectCategoryIds: Array(selectedAutoCollectCategoryIds)
             )

             if let editingBook {
               await store.updateBook(editingBook.id, with: draft)
               targetBookId = editingBook.id
             } else {
               targetBookId = await store.createBook(draft)
             }

             if collectExistingNow {
               await store.collectTransactionsIntoBook(targetBookId)
             }
             dismiss()
           }
           .disabled(
             name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
             (splitEnabled && normalizedParticipants.isEmpty) ||
             (budgetLimitEnabled && Double(budgetLimitAmount) == nil)
           )
         }
       }
     }
     .background {
       Color.clear
         .onDisappear {
           showUnsavedChangesDialog = true
         }
     }
     .sheet(isPresented: $showAutoCollectConfirm) {
       AutoCollectInfoSheet(
         promptText: settings.booksAutoCollectPromptEnabled
           ? "开启后符合时间与分类条件的新流水会自动归入该账本。"
           : "当前您已关闭归集提示。开启后符合时间与分类条件的新流水会自动归入该账本。",
         onCancel: {
           collectExistingNow = false
           autoCollectEnabled = false
           showAutoCollectConfirm = false
         },
         onConfirm: {
           collectExistingNow = true
           autoCollectEnabled = true
           showAutoCollectConfirm = false
         }
       )
     }
     .confirmationDialog("改动还没保存", isPresented: $showUnsavedChangesDialog, titleVisibility: .visible) {
       Button("保存") {
         Task {
           let draft = BookDraft(
             name: name,
             icon: icon.isEmpty ? nil : icon,
             color: color.isEmpty ? nil : color,
             note: note.isEmpty ? nil : note,
             startDate: startDate,
             endDate: hasEndDate ? endDate : nil,
             autoCollectEnabled: autoCollectEnabled,
             budgetLimitEnabled: budgetLimitEnabled,
             budgetLimitAmount: budgetLimitEnabled ? Double(budgetLimitAmount) : nil,
             budgetStartDate: budgetLimitEnabled && hasEndDate ? startDate : nil,
             budgetEndDate: budgetLimitEnabled && hasEndDate ? endDate : nil,
             participantNames: splitEnabled ? normalizedParticipants : [],
             isPinned: editingBook?.isPinned ?? false,
             autoCollectCategoryIds: Array(selectedAutoCollectCategoryIds)
           )

           if let editingBook {
             await store.updateBook(editingBook.id, with: draft)
             targetBookId = editingBook.id
           } else {
             targetBookId = await store.createBook(draft)
           }

           if collectExistingNow {
             await store.collectTransactionsIntoBook(targetBookId)
           }
           dismiss()
         }
       }
       Button("丢弃改动", role: .destructive) {
         dismiss()
       }
       Button("继续编辑", role: .cancel) {}
     } message: { _

	Text("退出前可以选择先保存，或者直接丢弃这次改动。")
   }
}

private var normalizedParticipants: [String] {
   var seen = Set<String>()
   return participants
       .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
       .filter { !$0.isEmpty }
       .filter { seen.insert($0).inserted }
}

private var previewColor: Color {
   if color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
       return .accentColor
   }
   return Color(hex: color)
}

private var autoCollectCategorySummary: String {
   guard !selectedAutoCollectCategoryIds.isEmpty else { return "全部分类" }
   let names = store.flattenedCategories
       .filter { selectedAutoCollectCategoryIds.contains($0.id) }
       .map(\.name)
   return names.isEmpty ? "已选分类" : names.joined(separator: ", ")
}

private var hasUnsavedChanges: Bool {
   BookDraft(
       name: name,
       icon: icon,
       color: color,
       note: note,
       startDate: startDate,
       endDate: hasEndDate ? endDate : nil,
       autoCollectEnabled: autoCollectEnabled,
       budgetEnabled: budgetLimitEnabled,
       budgetLimitAmount: budgetLimitEnabled ? Double(budgetLimitAmount) : nil,
       collectExistingNow: collectExistingNow,
       splitEnabled: splitEnabled,
       participantNames: normalizedParticipants,
       autoCollectCategoryIds: Array(selectedAutoCollectCategoryIds).sorted()
   ) != initialSnapshot
}

private func attemptDismiss() {
   if hasUnsavedChanges {
       showUnsavedChangesDialog = true
   } else {
       dismiss()
   }
}

private func appendParticipant() {
   let trimmed = newParticipantName.trimmingCharacters(in: .whitespacesAndNewlines)
   guard !trimmed.isEmpty else { return }
   newParticipantName = ""
   participants.append(trimmed)
}

@ViewBuilder
private func iconPickerGrid(options: [String], selected: Binding<String>, previewColor: Color) -> some View {
   let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
   LazyVGrid(columns: columns, spacing: 10) {
       ForEach(options, id: \.self) { option in
           Button {
               selected.wrappedValue = option
           } label: {
               ZStack {
                   RoundedRectangle(cornerRadius: 14, style: .continuous)
                       .fill(selected.wrappedValue == option ? previewColor.opacity(0.16) : Color.secondarySystemBackground)
                   Image(systemName: option)
                       .font(.system(size: 18, weight: .semibold))
                       .foregroundStyle(selected.wrappedValue == option ? previewColor : .primary)
               }
               .frame(height: 52)
               .overlay(
                   RoundedRectangle(cornerRadius: 14, style: .continuous)
                       .stroke(selected.wrappedValue == option ? previewColor : Color.clear, lineWidth: 2.5)
               )
           }
           .buttonStyle(.plain)
       }
   }
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
                   )
           }
           .buttonStyle(.plain)
       }
   }
}

private extension Color {
   init(hex: String) {
       let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
       var int: UInt64 = 0
       Scanner(string: hex).scanHexInt64(&int)
       let r, g, b: UInt64
       switch hex.count {
       case 3:
           (r, g, b) = ((int >> 8) & 0xF, (int >> 4) & 0xF, int & 0xF)
           self.init(
               red: Double(r) / 255,
               green: Double(g) / 255,
               blue: Double(b) / 255
           )
       case 6:
           (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
           self.init(
               red: Double(r) / 255,
               green: Double(g) / 255,
               blue: Double(b) / 255
           )
       default:
           (r, g, b) = (255, 24, 144)
           self.init(
               red: Double(r) / 255,
               green: Double(g) / 255,
               blue: Double(b) / 255
           )
       }
   }
}

private struct BookDetailsView: View {
   @EnvironmentObject private var store: LedgerStore
   @State private var showSettingsSheet = false
   @State private var showDeleteAlert = false
   @State private var showDetailsURL: URL?

   let book: LedgerBook

   var body: some View {
       List {
           Section {
               VStack(alignment: .leading, spacing: 12) {
                   Text(book.name)
                       .font(.title.weight(.bold))
                   if let note = book.note {
                       Text(note)
                           .font(.subheadline)
                           .foregroundStyle(.secondary)
                   }
               }

               HStack(spacing: 12) {
                   metric(title: "支出", value: book.expenseAmount.cnText, tint: .orange)
                   metric(title: "收入", value: book.incomeAmount.cnText, tint: .green)
                   metric(title: "余额", value: book.balance.cnText, tint: book.balance >= 0 ? .blue : .red)
               }
           }

           if !book.participants.isEmpty {
               Section("分账成员") {
                   VStack(alignment: .leading, spacing: 8) {
                       Text("分账成员")
                           .font(.caption)
                           .foregroundStyle(.secondary)

                       ScrollView(.horizontal, showsIndicators: false) {
                           HStack(spacing: 8) {
                               ForEach(book.participants) { participant in
                                   Text(participant.name)
                                       .font(.caption.weight(.medium))
                                       .padding(.horizontal, 10)
                                       .padding(.vertical, 6)
                                       .background(Color(.tertiarySystemBackground), in: Capsule())
                               }
                           }
                       }
                   }
                   .padding(.vertical, 8)
               }
           }

           if let budgetLimit = book.budgetLimitAmount, budgetLimit > 0 {
               Section("账本预算") {
                   let spent = book.expenseAmount
                   let remaining = max(budgetLimit - spent, 0)
                   let ratio = min(spent / budgetLimit, 1.0)

                   VStack(alignment: .leading, spacing: 12) {
                       HStack(spacing: 12) {
                           metric(title: "已用", value: spent.cnText, tint: .orange)
                           metric(title: "剩余", value: remaining.cnText, tint: .green)
                       }

                       ProgressView(value: ratio)
                           .tint(ratio >= 1 ? .red : .blue)

                       if let budgetStart = book.budgetStartDate {
                           Text(bookBudgetRangeText(start: budgetStart, end: book.budgetEndDate))
                               .font(.caption)
                               .foregroundStyle(.secondary)
                       }
                   }
                   .padding(.vertical, 4)
               }
           }

           if hasSplitData {
               Section("分账分组") {
                   ForEach(splitSummaries) { item in
                       VStack(alignment: .leading, spacing: 8) {
                           HStack {
                               Text(item.participant.name)
                                   .font(.headline)
                               Spacer()
                               Text(netText(for: item))
                                   .font(.subheadline.weight(.semibold))
                                   .foregroundStyle(netColor(for: item))
                           }

                           HStack {
                               metric(title: "已付", value: item.paid.cnText, tint: .blue)
                               metric(title: "应承担", value: item.owed.cnText, tint: .purple)
                           }
                       }
                       .padding(.vertical, 4)
                   }
               }
           }

           Section("记账流水") {
               if store.transactions.filter({ $0.bookIds.contains(book.id) || $0.bookId == book.id }).isEmpty {
                   ContentUnavailableView("暂无账本流水", systemImage: "tray")
               } else {
                   ForEach(items) { tx in
                       VStack(alignment: .leading, spacing: 6) {
                           HStack {
                               Label(tx.categoryName ?? "未分类", systemImage: categoryIcon(for: tx))
                               Spacer()
                               Text(tx.kind == .expense ? "-\(tx.amount)" : "+\(tx.amount)")
                                   .foregroundStyle(tx.kind == .expense ? .red : .green)
                                   .font(.headline)
                           }

                           Text(tx.title)
                               .font(.subheadline.weight(.medium))

                           Text(tx.happenedAt.formatted(date: .abbreviated, time: .shortened))
                               .font(.caption)
                               .foregroundStyle(.secondary)

                           if tx.paidByParticipantName != nil || !tx.splitParticipantNames.isEmpty {
                               VStack(alignment: .leading, spacing: 4) {
                                   if let payer = tx.paidByParticipantName {
                                       Label("付款人 \(payer)", systemImage: "person.fill.checkmark")
                                   }
                                   if !tx.splitParticipantNames.isEmpty {
                                       Label("分摊成员 \(tx.splitParticipantNames.joined(separator: ", "))", systemImage: "person.2.fill")
                                   }
                               }
                               .font(.caption)
                               .foregroundStyle(.secondary)
                           }
                       }
                       .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                           Button("删除") {
                               Task { await store.removeTransaction(tx.id, from: book.id) }
                           }
                           .tint(.orange)
                       }
                   }
               }
           }
       }
       .navigationTitle(book.name)
       .toolbar {
           ToolbarItem(placement: .topBarTrailing) {
               Button {
                   showSettingsSheet = true
               } label: {
                   Label("设置", systemImage: "gearshape")
               }
           }

           ToolbarItem(placement: .topBarTrailing) {
               Button {
                   Task { await store.setBookPinned(book.id, pinned: !book.isPinned) }
               } label: {
                   Label(book.isPinned ? "取消置顶" : "置顶账本", systemImage: book.isPinned ? "pin.slash" : "pin")
               }


Menu("导出分享") {
             Button("导出 HTML") {
               shareItem = exportBookSummary(as: .html)
             }
             Button("导出 Markdown") {
               shareItem = exportBookSummary(as: .markdown)
             }
             Button("导出 PDF") {
               shareItem = exportBookSummary(as: .pdf)
             }
           }

           Button(role: .destructive) {
             showDeleteAlert = true
           } label: {
             Label("删除账本", systemImage: "trash")
           }
         } label: {
           Image(systemName: "gearshape")
         }
       }
       .task {
         await store.loadTransactions(bookId: book.id)
       }
       .sheet(isPresented: $showSettingsSheet) {
         CreateBookView(editingBook: book)
           .environmentObject(store)
       }
       .sheet(isPresented: $shareItem != nil) {
         if let url = shareItem {
           ActivityViewController(activityItems: [url])
         }
       }
       .alert("删除账本？", isPresented: $showDeleteAlert) {
         Button("取消", role: .cancel) {}
         Button("删除", role: .destructive) {
           Task { await store.deleteBook(book.id) }
         }
       } message: {
         Text("账本会被删除，但流水本身不会删除，只会移除与这个账本的关联。")
       }
 }

 private func metric(title: String, value: String, tint: Color) -> some View {
   VStack(alignment: .leading, spacing: 4) {
     Text(title)
       .font(.caption)
       .foregroundStyle(.secondary)
     Text(value)
       .font(.subheadline.weight(.bold))
       .foregroundStyle(tint)
   }
   .frame(maxWidth: .infinity, alignment: .leading)
   .padding(12)
   .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
 }

 private func categoryIcon(for tx: LedgerTransaction) -> String {
   if let categoryId = tx.categoryId,
      let category = store.flattenedCategories.first(where: { $0.id == categoryId }) {
     return category.icon ?? "square.grid.2x2"
   }
   return "square.grid.2x2"
 }

 private func bookBudgetRangeText(start: Date, end: Date?) -> String {
   let startText = start.formatted(date: .abbreviated, time: .omitted)
   if let end {
     return "预算周期：\(startText) - \(end.formatted(date: .abbreviated, time: .omitted))"
   }
   return "预算周期：自 \(startText) 起"
 }

 private var splitSummaries: [BookSplitSummary] {
   let bookTransactions = store.transactions.filter { $0.bookId == book.id && $0.kind == .expense }
   guard !bookTransactions.isEmpty else { return [] }

   var paid: [String: Double] = [:]
   var owed: [String: Double] = [:]

   for tx in bookTransactions {
     if let payerId = tx.paidByParticipantId {
       paid[payerId, default: 0] += tx.amount
     }

     guard !tx.splitParticipantIds.isEmpty else { continue }
     let share = tx.amount / Double(tx.splitParticipantIds.count)
     for participantId in tx.splitParticipantIds {
       owed[participantId, default: 0] += share
     }
   }

   return book.participants.map { participant in
     BookSplitSummary(
       participant: participant,
       paid: paid[participant.id, default: 0],
       owed: owed[participant.id, default: 0]
     )
   }
 }

 private var hasSplitData: Bool {
   store.transactions.contains { $0.bookId == book.id && ($0.paidByParticipantId != nil || !$0.splitParticipantIds.isEmpty) }
 }

 private func netText(for item: BookSplitSummary) -> String {
   if abs(item.net) < 0.01 { return "已平" }
   return item.net > 0 ? "应收 \(abs(item.net).cnText)" : "应付 \(abs(item.net).cnText)"
 }

 private func netColor(for item: BookSplitSummary) -> Color {
   if abs(item.net) < 0.01 { return .secondary }
   return item.net > 0 ? .green : .orange
 }

 private func exportBookSummary(as format: BookShareFormat) -> URL? {
   let items = store.transactions.filter { $0.bookIds.contains(book.id) || $0.bookId == book.id }
   let markdown = makeBookShareMarkdown(items: items)

   let tempDir = FileManager.default.temporaryDirectory
   switch format {
   case .markdown:
     let url = tempDir.appendingPathComponent("\(book.name)-账本.md")
     try? markdown.data(using: .utf8)?.write(to: url)
     return url

   case .html:
     let url = tempDir.appendingPathComponent("\(book.name)-账本.html")
     let html = makeBookShareHTML(markdown: markdown)
     try? html.data(using: .utf8)?.write(to: url)
     return url

   case .pdf:
     let url = tempDir.appendingPathComponent("\(book.name)-账本.pdf")
     do {
       let html = try makeBookShareHTML(markdown: markdown)
       try data.write(to: url)
       return url
     } catch {
       return nil
     }
   }
 }

 private func makeBookShareMarkdown(items: [LedgerTransaction]) -> String {
   let lines = items.map { item in
     let amountText = item.kind == .expense ? "-\(item.amount)" : "+\(item.amount)"
     let categoryText = item.categoryName ?? "未分类"
     let paymentText = item.paymentMethod?.isEmpty == false ? item.paymentMethod! : "-"
     let dateText = item.happenedAt.formatted(date: .abbreviated, time: .omitted)
     return "\(item.title) | \(amountText) | \(categoryText) | \(paymentText) | \(dateText)"
   }.joined(separator: "\n")

   return """
   # \(book.name)

   \(book.note?.isEmpty == false ? "**账本摘要**：\(book.note!)" : "")

   - 净额：\(book.balance.cnText)
   - 支出：\(book.expenseAmount.cnText)
   - 收入：\(book.incomeAmount.cnText)
   - 笔数：\(book.transactionCount)

   ## 流水
   \(lines)
   """
 }

 private func makeBookShareHTML(items: [LedgerTransaction]) -> String {
   let accent = book.color ?? "#3BB2F6"
   let noteText = book.note?.isEmpty == false ? book.note! : ""
   let participantBadges = book.participants.isEmpty
     ? ""
     : book.participants.map { "<span class=\"chip\">\($0.name.htmlEscaped)</span>" }.joined()

   let transactionRows = items.map { item in
     let amountClass = item.kind == .expense ? "expense" : "income"
     let amountText = item.kind == .expense ? "-\(item.amount.cnText)" : "+\(item.amount.cnText)"
     let categoryText = item.categoryName ?? "未分类"
     let paymentText = item.paymentMethod?.isEmpty == false ? item.paymentMethod! : "-"
     let dateText = item.happenedAt.formatted(date: .abbreviated, time: .omitted)
     let tags = """
     <td>\(categoryText)</td>
     <td>\(dateText)</td>
     <td>\(paymentText)</td>
     <td style="text-align:right;">\(amountText)</td>
     """
     return """
     <tr>
       <td class="category">\(tags)</td>
       <td class="amount \(amountClass)">\(amountText)</td>
     </tr>
     """
   }.joined(separator: "\n")

   return """
   <!DOCTYPE html>
   <html lang="zh-CN">
   <head>
   <meta charset="utf-8" />
   <meta name="viewport" content="width=device-width, initial-scale=1" />
   <title>\(book.name.htmlEscaped)</title>
   <style>
   :root { --accent: \(accent); --bg: #F7F8FA; --card: #FFFFFF; --text: #1F2A44; --secondary: #8E8E93; --expense: #FF3B30; --income: #34C759; }
   body { margin: 0; padding: 20px; background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif; }
   .wrap { max-width: 980px; margin: 0 auto; }
   .hero { margin: 0 0 16px; padding: 20px; background: linear-gradient(135deg, var(--accent), #111827); color: white; border-radius: 28px; }
   .hero h1 { margin: 0 0 8px; font-size: 30px; line-height: 1.15; }
   .hero p { margin: 0; font-size: 14px; opacity: 0.8; }
   .chip { display: inline-flex; align-items: center; padding: 6px 10px; border-radius: 999px; background: rgba(255,255,255,0.14); margin-right: 6px; font-size: 12px; }
   .mini-tag { display: inline-flex; align-items: center; padding: 4px 8px; border-radius: 12px; background: var(--accent); color: white; font-size: 12px; margin-right: 6px; }
   .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; margin-top: 12px; }
   .card { background: var(--card); border: 1px solid rgba(255,255,255,0.6); padding: 14px; border-radius: 22px; box-shadow: 0 12px 24px rgba(0,0,0,0.04); }
   .stat-label { color: var(--secondary); font-size: 13px; margin-bottom: 6px; }
   .stat-value { font-size: 20px; font-weight: 700; }
   .section { margin-top: 30px; }
   .section h2 { margin: 0 0 10px; font-size: 20px; }
   .section p { margin-top: 0; padding: 20px; }
   table { width: 100%; border-collapse: collapse; margin-top: 14px; }
   th, td { padding: 14px 10px; text-align: left; border-bottom: 1px solid var(--line); vertical-align: top; }
   .title-row { margin-top: 4px; color: var(--text); font-weight: 600; }
   .sub-row { margin-top: 4px; color: var(--secondary); font-size: 12px; flex-wrap: wrap; }
   .amount { text-align: right; color: var(--text); font-weight: 600; }
   .amount.income { color: var(--income); }
   .amount.expense { color: var(--expense); }
   @media (max-width: 760px) { .grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } .hero h1 { font-size: 24px; } }
   </style>
   </head>
   <body>
   <div class="wrap">
     <div class="hero">
       <h1>\(book.name.htmlEscaped)</h1>
       \(noteText.isEmpty ? "" : "<p>\(noteText.htmlEscaped)</p>")
       \(participantBadges.isEmpty ? "" : "<div class=\"chips\">\(participantBadges)</div>")
     </div>

     <div class="grid">
       <div class="card stat"><div class="label">净额</div><div class="value">\(book.balance.cnText.htmlEscaped)</div></div>
       <div class="card stat"><div class="label">主题支出</div><div class="value">\(book.expenseAmount.cnText.htmlEscaped)</div></div>
       <div class="card stat"><div class="label">主题收入</div><div class="value">\(book.incomeAmount.cnText.htmlEscaped)</div></div>
       <div class="card stat"><div class="label">流水笔数</div><div class="value">\(String(book.transactionCount).htmlEscaped)</div></div>
     </div>

     <div class="card section">
       <h2>流水明细</h2>
       <p>当前版本暂不支持导出，可直接转发查看。</p>
       <table>
         <thead>
           <tr>
             <th>标题</th>
             <th>日期</th>
             <th>分类</th>
             <th>支付渠道</th>
             <th style="text-align:right;">金额</th>
           </tr>
         </thead>
         <tbody>
           \(transactionRows)
         </tbody>
       </table>
     </div>
   </div>
   </body>
   </html>
   """
 }

 private enum BookShareFormat {
   case html
   case markdown
   case pdf
 }
private struct ActivityViewController: UIViewControllerRepresentable {
 let context: Context
 let activityItems: [Any]
 let applicationActivities: [UIActivity]?

 func makeUIViewController(context: Context) -> UIActivityViewController {
   let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
   return controller
 }

 func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct AutoCollectSetupSheet: View {
 let promptText: String
 @Binding var collectExistingNow: Bool
 let onCancel: () -> Void
 let onConfirm: () -> Void

 var body: some View {
   VStack(alignment: .leading, spacing: 18) {
     VStack(alignment: .leading, spacing: 4) {
       Capsule()
         .fill(Color.secondary.opacity(0.25))
         .frame(width: 40, height: 5)
         .frame(maxWidth: .infinity)

       Text("开启自动归集")
         .font(.title.weight(.bold))

       Text(promptText)
         .font(.subheadline)
         .foregroundStyle(.secondary)
         .fixedSize(horizontal: false, vertical: true)

       Toggle("保存后自动归集一次已有流水", isOn: $collectExistingNow)
         .toggleStyle(.switch)
     }

     HStack(spacing: 12) {
       Button(action: onCancel) {
         Text("取消")
           .font(.headline)
           .frame(maxWidth: .infinity)
           .frame(height: 48)
           .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
       }
       .buttonStyle(.plain)

       Button(action: onConfirm) {
         Text("保存")
           .font(.headline)
           .frame(maxWidth: .infinity)
           .frame(height: 48)
           .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
           .foregroundStyle(.white)
       }
       .buttonStyle(.plain)
     }
     .padding(22)
     .padding(.top, 4)
   }
   .presentationDetents([.height(268)])
   .presentationDragIndicator(.visible)
 }
}

private enum RenderPDFRenderer {
 static func render(html: String) throws -> Data {
   let formatter = UIMarkupTextPrintFormatter(markupText: html)
   let renderer = UIPrintPageRenderer()
   renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

   let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
   let printableRect = pageRect.insetBy(dx: 24, dy: 24)
   renderer.setValue(pageRect, forKey: "paperRect")
   renderer.setValue(printableRect, forKey: "printableRect")

   let data = NSMutableData()
   UIGraphicsBeginPDFContextToData(data, pageRect, nil)
   renderer.prepare(forDrawingPages: NSMakeRange(0, 1))

   let bounds = UIGraphicsGetPDFContextBounds()
   for pageIndex in 0..<renderer.numberOfPages {
     UIGraphicsBeginPDFPage()
     renderer.drawPage(at: pageIndex, in: bounds)
   }
   UIGraphicsEndPDFContext()

   return data as Data
 }
}

private extension String {
 var htmlEscaped: String {
   self
     .replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
     .replacingOccurrences(of: "\"", with: "&quot;")
     .replacingOccurrences(of: "'", with: "&#39;")
 }
}

private struct BookAutoCollectCategoryPickerView: View {
 @EnvironmentObject private var store: LedgerStore
 @Binding var selectedCategoryIds: Set<Int>

 var body: some View {
   List {
     Section {
       Button {
         selectedCategoryIds.removeAll()
       } label: {
         HStack {
           Text("全部分类")
           Spacer()
           if selectedCategoryIds.isEmpty {
             Image(systemName: "checkmark")
               .foregroundStyle(.blue)
           }
         }
         .contentShape(Rectangle())
       }
       .buttonStyle(.plain)
     }

     Section("支出分类") {
       ForEach(visibleExpenseCategories) { category in
         Button {
           toggleSelection(for: category)
         } label: {
           HStack {
             Text(category.name)
             Spacer()
             if selectedCategoryIds.contains(category.id) {
               Image(systemName: "checkmark")
                 .foregroundStyle(.blue)
             }
           }
           .contentShape(Rectangle())
         }
         .buttonStyle(.plain)
       }
     }
   }
   .navigationTitle("自动归集分类")
 }

 private var visibleExpenseCategories: [LedgerCategory] {
   let categories = store.selectableCategories(for: .expense)
   return categories.filter { category in
     !selectedCategoryIds.contains(where: { selectedId in
       guard selectedId != category.id else { return true }
       let selected = categories.first(where: { $0.id == selectedId })
       return selected?.pathComponents.starts(with: category.pathComponents) ?? false
     })
   }
 }

 private func toggleSelection(for category: LedgerCategory) {
   if selectedCategoryIds.contains(category.id) {
     selectedCategoryIds.remove(category.id)
     return
   }

   let allCategories = store.selectableCategories(for: .expense)
   let descendants = allCategories.filter {
     $0.id != category.id && $0.pathComponents.starts(with: category.pathComponents)
   }
   descendants.forEach { selectedCategoryIds.remove($0.id) }

   let ancestors = allCategories.filter {
     $0.id != category.id && category.pathComponents.starts(with: $0.pathComponents)
   }
   ancestors.forEach { selectedCategoryIds.remove($0.id) }

   selectedCategoryIds.insert(category.id)
 }
}

private struct BookEditorStateSnapshot: Equatable {
 let name: String
 let icon: String
 let color: String
 let note: String
 let startDate: Date
 let endDate: Date?
 let autoCollectEnabled: Bool
 let collectExistingNow: Bool
 let budgetEnabled: Bool
 let budgetLimitAmount: String
 let splitEnabled: Bool
 let participants: [String]
 let autoCollectCategoryIds: [Int]

 init(book: LedgerBook) {
   self.name = book.name
   self.icon = book.icon ?? "books.vertical.fill"
   self.color = book.color ?? "#0882F6"
   self.note = book.note ?? ""
   self.startDate = book.startDate ?? Date()
   self.endDate = book.endDate

   self.autoCollectEnabled = book.autoCollectEnabled ?? false
   self.collectExistingNow = false
   self.budgetEnabled = book.budgetEnabled ?? false
   self.budgetLimitAmount = book.budgetLimitAmount.map { String(format: "%.0f", $0) } ?? ""
   self.participants = book.splitEnabled ? (book.participantNames ?? ["我"]) : ["我"]
   self.splitEnabled = book.splitEnabled ?? false
   self.autoCollectCategoryIds = book.autoCollectCategoryIds ?? [].sorted()
 }

 init(
   name: String,
   icon: String,
   color: String,
   note: String,
   startDate: Date,
   endDate: Date?,
   autoCollectEnabled: Bool,
   collectExistingNow: Bool,
   budgetEnabled: Bool,
   budgetLimitAmount: String,
   splitEnabled: Bool,
   participants: [String],
   autoCollectCategoryIds: [Int]
 ) {
   self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
   self.icon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
   self.color = color.trimmingCharacters(in: .whitespacesAndNewlines)
   self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
   self.startDate = startDate
   self.endDate = endDate
   self.autoCollectEnabled = autoCollectEnabled
   self.collectExistingNow = collectExistingNow
   self.budgetEnabled = budgetEnabled
   self.budgetLimitAmount = budgetLimitAmount.trimmingCharacters(in: .whitespacesAndNewlines)
   self.splitEnabled = splitEnabled
   self.participants = participants.sorted()
   self.autoCollectCategoryIds = autoCollectCategoryIds.sorted()
 }
}

private struct SheetDismissal: UIViewControllerRepresentable {
 let isDisabled: Bool
 let onAttempt: () -> Void

 func makeUIViewController(context: Context) -> UIViewController {
   let controller = UIViewController()
   controller.view.backgroundColor = .clear
   return controller
 }

 func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
   DispatchQueue.main.async {
     uiViewController.parent?.presentationController?.delegate = context.coordinator
     context.coordinator.isDisabled = isDisabled
     context.coordinator.onAttempt = onAttempt
   }
 }

 func makeCoordinator() -> Coordinator {
   Coordinator(isDisabled: isDisabled, onAttempt: onAttempt)
 }

 final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
   var isDisabled: Bool
   var onAttempt: () -> Void

   init(isDisabled: Bool, onAttempt: @escaping () -> Void) {
     self.isDisabled = isDisabled
     self.onAttempt = onAttempt
   }

   func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
     !isDisabled
   }

   func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
     if isDisabled {
       onAttempt()
     }
   }
 }
}
