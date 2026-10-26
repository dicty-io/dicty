import SwiftUI

public struct PageTabItem<Selection: Hashable>: Identifiable {
    public var id: Selection
    public let label: String
    public let icon: String
    
    public init(id: Selection, label: String, icon: String) {
        self.id = id
        self.label = label
        self.icon = icon
    }
}

public struct PageTabBar<Selection: Hashable>: View {
    @Binding public var selection: Selection
    public let tabs: [PageTabItem<Selection>]
    public var minItemWidth: CGFloat
    public var spacing: CGFloat

    public init(
        selection: Binding<Selection>,
        tabs: [PageTabItem<Selection>],
        minItemWidth: CGFloat = 68,
        spacing: CGFloat = 6
    ) {
        self._selection = selection
        self.tabs = tabs
        self.minItemWidth = minItemWidth
        self.spacing = spacing
    }

    public var body: some View {
        HStack(spacing: spacing) {
            ForEach(tabs) { tab in
                let isSelected = selection == tab.id
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = tab.id
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                            .frame(height: 18)
                        
                        Text(tab.label)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundColor(isSelected ? .appAccent : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minWidth: minItemWidth)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.appAccent.opacity(0.15) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}
