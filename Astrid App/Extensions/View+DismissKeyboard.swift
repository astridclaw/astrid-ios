import SwiftUI

/// A tap-to-dismiss-keyboard gesture modifier
/// Dismisses the keyboard when tapping outside of interactive elements
struct DismissKeyboardOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                // Use UIApplication to dismiss keyboard
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
    }
}

extension View {
    /// Adds a tap gesture to dismiss the keyboard when tapping outside of interactive elements
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTapModifier())
    }
}
