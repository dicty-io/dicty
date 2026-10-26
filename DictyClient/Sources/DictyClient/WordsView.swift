import SwiftUI

// MARK: - Words (Vocabulary + Snippets)
//
// The sidebar keeps one entry for both dictionaries. Each tab is the existing
// page: it already has its own header and scroller, so the page simply adds a
// tab switcher above it.

struct WordsView: View {
    @AppStorage("wordsTabSelection") private var tab: String = "vocabulary"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PageTabBar(
                    selection: $tab,
                    tabs: [
                        PageTabItem(id: "vocabulary", label: "Vocabulary", icon: "character.book.closed"),
                        PageTabItem(id: "snippets", label: "Snippets", icon: "text.badge.plus")
                    ]
                )
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.5)

            if tab == "snippets" {
                SnippetsView()
            } else {
                VocabularyView()
            }
        }
    }
}
