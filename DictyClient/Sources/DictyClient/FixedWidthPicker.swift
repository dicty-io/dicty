import SwiftUI

struct FixedWidthPicker<SelectionValue: Hashable, LabelView: View, Content: View>: View {
    @Binding var selection: SelectionValue
    var width: CGFloat
    @ViewBuilder var label: () -> LabelView
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } label: {
            label()
                .frame(width: width - 32, alignment: .leading)
        }
        .frame(width: width)
    }
}
