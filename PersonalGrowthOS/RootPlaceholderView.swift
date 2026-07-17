import SwiftUI

struct RootPlaceholderView: View {
    let container: AppContainer

    var body: some View {
        VStack {
            Text("Personal Growth OS")
            Text("Project Bootstrap")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root-placeholder")
    }
}
