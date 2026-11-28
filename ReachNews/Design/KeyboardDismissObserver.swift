import SwiftUI
import UIKit

/// Observes blank taps without installing a competing SwiftUI gesture on rows.
/// Never handles a control, text input, or navigable table/collection row.
struct KeyboardDismissObserver: UIViewRepresentable {
    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ uiView: ObserverView, context: Context) {}

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        private weak var observedWindow: UIWindow?
        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if observedWindow !== window {
                observedWindow?.removeGestureRecognizer(tap)
                observedWindow = window
                tap.cancelsTouchesInView = false
                tap.delaysTouchesBegan = false
                tap.delaysTouchesEnded = false
                tap.delegate = self
                window?.addGestureRecognizer(tap)
            }
        }

        @objc private func dismissKeyboard() { window?.endEditing(true) }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window, !isHidden else { return false }
            // Only observe this screen's bounds, not unrelated modal/tab contents.
            let point = touch.location(in: self)
            guard bounds.contains(point), self.window === window else { return false }
            var node = touch.view
            while let view = node {
                if view is UIControl || view is UITextView || view is UITableViewCell || view is UICollectionViewCell {
                    return false
                }
                node = view.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}
