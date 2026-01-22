import SwiftUI

// MARK: - PreferenceKey for tracking scroll offset

/// PreferenceKey to track scroll offset within a ScrollView
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - ScrollToTop ViewModifier

/// A ViewModifier that adds a floating scroll-to-top button
/// The button appears when scrolled beyond a threshold (default 100 points)
struct ScrollToTopModifier: ViewModifier {
    let threshold: CGFloat
    let scrollToId: String

    @State private var scrollOffset: CGFloat = 0
    @State private var showButton = false

    func body(content: Content) -> some View {
        ZStack(alignment: .bottomTrailing) {
            content
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY
                        )
                    }
                )
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showButton = scrollOffset < -threshold
                    }
                }

            // Floating scroll-to-top button
            if showButton {
                ScrollToTopButton {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        scrollOffset = 0
                    }
                }
                .padding(.trailing, Theme.spacing16)
                .padding(.bottom, Theme.spacing16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds a scroll-to-top button that appears when scrolling down
    ///
    /// Usage:
    /// ```swift
    /// ScrollViewReader { proxy in
    ///     ScrollView {
    ///         VStack {
    ///             Text("Top").id("top")
    ///             // ... content ...
    ///         }
    ///         .scrollToTopButton(proxy: proxy, topId: "top")
    ///     }
    ///     .coordinateSpace(name: "scroll")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - proxy: The ScrollViewProxy to use for scrolling
    ///   - topId: The ID of the element to scroll to (should be at the top of the ScrollView)
    ///   - threshold: The scroll distance threshold before the button appears (default: 100)
    /// - Returns: A view with the scroll-to-top button modifier applied
    func scrollToTopButton(
        proxy: ScrollViewProxy,
        topId: String = "top",
        threshold: CGFloat = 100
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            self
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY
                        )
                    }
                )
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    // Track scroll offset, button visibility is managed internally
                }

            // Floating scroll-to-top button with internal state management
            ScrollToTopButtonWithState(
                proxy: proxy,
                topId: topId,
                threshold: threshold
            )
        }
    }
}

// MARK: - Internal Button with State

/// Internal view that manages scroll-to-top button visibility and action
private struct ScrollToTopButtonWithState: View {
    let proxy: ScrollViewProxy
    let topId: String
    let threshold: CGFloat

    @State private var scrollOffset: CGFloat = 0
    @State private var showButton = false

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: geometry.frame(in: .named("scroll")).minY
                )
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
            withAnimation(.easeInOut(duration: 0.3)) {
                showButton = scrollOffset < -threshold
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showButton {
                ScrollToTopButton {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo(topId, anchor: .top)
                    }
                }
                .padding(.trailing, Theme.spacing16)
                .padding(.bottom, Theme.spacing16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
