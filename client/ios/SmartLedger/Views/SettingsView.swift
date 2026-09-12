import SwiftUI
struct SettingsView: View {
 @EnvironmentObject var store: LedgerStore
 @EnvironmentObject var settings: AppSettings
 @State var enabled = false
 var body: some View { Form {
  Section("外观") { Picker("主题模式", selection: $settings.appearanceMode) { ForEach(AppAppearanceMode.allCases) { Text($0.title).tag($0) } } }
  Section("坚果云 WebDAV 同步") {
   Toggle("启用云同步", isOn: $enabled).onChange(of: enabled) { _, v in Task { await store.setCloudSyncEnabled(v) } }
   Text(store.lastSyncMessage).font(.footnote)
   Button("智能同步") { Task { await store.smartSync() } }
  }
 }.navigationTitle("设置").task { enabled = store.cloudSyncEnabled }
 }
}
