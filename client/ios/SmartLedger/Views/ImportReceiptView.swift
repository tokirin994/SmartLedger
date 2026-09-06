import SwiftUI

/// 补丁版本的“识图”主入口。具体的选图、识别、确认入账逻辑复用 OCRImportView。
struct ImportReceiptView: View {
    var body: some View { NavigationStack { OCRImportView() } }
}
