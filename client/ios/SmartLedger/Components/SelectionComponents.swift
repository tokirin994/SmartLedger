import SwiftUI

struct CategoryPicker: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var selection: UUID?
    let kind: FlowType
    var body: some View {
        Picker("分类", selection: $selection) {
            Text("未分类").tag(UUID?.none)
            ForEach(store.categories.filter { $0.kind == kind }) { category in
                Text(category.parentID == nil ? category.name : "  └ \(category.name)").tag(Optional(category.id))
            }
        }
    }
}

struct BookPicker: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var selections: Set<UUID>
    var body: some View {
        List(store.books) { book in
            Button { selections.formSymmetricDifference([book.id]) } label: {
                HStack { Label(book.name, systemImage: book.icon); Spacer(); if selections.contains(book.id) { Image(systemName: "checkmark") } }
            }.foregroundStyle(.primary)
        }.navigationTitle("账本归属")
    }
}

struct PaymentMethodPicker: View {
    @EnvironmentObject private var store: LedgerStore
    @Binding var selection: String
    var body: some View { Picker("支付渠道", selection: $selection) { ForEach(store.paymentMethods, id: \.self) { Text($0).tag($0) } } }
}

struct InstallmentSettingView: View {
    @Binding var enabled: Bool
    @Binding var months: Int
    var body: some View { Toggle("启用分期", isOn: $enabled); if enabled { Stepper("分期月数：\(months)", value: $months, in: 2...36) } }
}

struct SplitSettingView: View {
    let participants: [String]
    @Binding var paidBy: String
    @Binding var selected: [String]
    var body: some View { Picker("付款人", selection: $paidBy) { Text("请选择").tag(""); ForEach(participants, id: \.self) { Text($0).tag($0) } }; ForEach(participants, id: \.self) { name in Toggle("分给 \(name)", isOn: Binding(get: { selected.contains(name) }, set: { value in if value { selected.append(name) } else { selected.removeAll { $0 == name } } })) } }
}
