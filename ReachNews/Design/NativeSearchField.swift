import SwiftUI
import UIKit

/// System search-field chrome, shared by feed search and the brief question input.
/// The question field uses a Send return key without pretending to run a search.
struct NativeSearchField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let identifier: String
    var sendsQuestion = false
    var onSubmit: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.backgroundImage = UIImage()
        bar.delegate = context.coordinator
        bar.searchTextField.accessibilityIdentifier = identifier
        bar.searchTextField.autocorrectionType = .no
        bar.searchTextField.autocapitalizationType = .none
        return bar
    }

    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        if bar.text != text { bar.text = text }
        bar.placeholder = placeholder
        bar.returnKeyType = sendsQuestion ? .send : .search
        bar.enablesReturnKeyAutomatically = sendsQuestion
        if sendsQuestion {
            bar.setImage(UIImage(systemName: "bubble.left"), for: .search, state: .normal)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISearchBar, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: 56)
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: NativeSearchField
        init(_ parent: NativeSearchField) { self.parent = parent }
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            parent.onSubmit()
        }
    }
}
