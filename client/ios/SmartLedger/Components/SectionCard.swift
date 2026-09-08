 import SwiftUI

 struct SectionCard<Content: View, HeaderTrailing: View>: View {
     let title: String
     let subtitle: String?
     let showSubtitle: Bool
     let headerTrailing: HeaderTrailing
     @ViewBuilder let content: Content

     init(title: String, subtitle: String? = nil, showSubtitle: Bool = false, @ViewBuilder content: () -> Content) where HeaderTrailing == EmptyView {
         self.title = title
         self.subtitle = subtitle
         self.showSubtitle = showSubtitle
         self.headerTrailing = EmptyView()
         self.content = content()
     }

     init(
         title: String,
         subtitle: String? = nil,
         showSubtitle: Bool = false,
         @ViewBuilder headerTrailing: () -> HeaderTrailing,
         @ViewBuilder content: () -> Content
     ) {
         self.title = title
         self.subtitle = subtitle
         self.showSubtitle = showSubtitle
         self.headerTrailing = headerTrailing()
         self.content = content()
     }

     var body: some View {
         VStack(alignment: .leading, spacing: 16) {
             HStack(alignment: .top, spacing: 12) {
                 VStack(alignment: .leading, spacing: 4) {
                     Text(title)
                         .font(.headline.weight(.semibold))
                     if showSubtitle, let subtitle {
                         Text(subtitle)
                             .font(.footnote)
                             .foregroundStyle(.secondary)
                     }
                 }
                 Spacer(minLength: 0)
                 headerTrailing
             }

             content
         }
         .padding(18)
         .glassCard(cornerRadius: 24, strokeOpacity: 0.30)
         .shadow(color: .black.opacity(0.035), radius: 14, x: 0, y: 8)
     }
 }
