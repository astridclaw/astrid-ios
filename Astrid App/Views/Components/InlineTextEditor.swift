import SwiftUI

/// Inline text editor that appears as text until tapped, then becomes editable
struct InlineTextEditor: View {
    @Environment(\.colorScheme) var colorScheme
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var onSave: (() -> Void)?

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            Text(label)
                .font(Theme.Typography.caption1())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

            if isEditing {
                TextField(placeholder, text: $text)
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    .textFieldStyle(.plain)
                    .padding(Theme.spacing12)
                    .background(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .focused($isFocused)
                    .onChange(of: isFocused) { _, focused in
                        if !focused && isEditing {
                            isEditing = false
                            onSave?()
                        }
                    }
                    .onSubmit {
                        isEditing = false
                        onSave?()
                    }
            } else {
                Text(text.isEmpty ? placeholder : text)
                    .font(Theme.Typography.body())
                    .foregroundColor(text.isEmpty
                        ? (colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        : (colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.spacing12)
                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .onTapGesture {
                        isEditing = true
                        isFocused = true
                    }
            }
        }
    }
}

/// Inline multiline text editor (for descriptions)
/// Supports markdown rendering when not editing
struct InlineTextAreaEditor: View {
    @Environment(\.colorScheme) var colorScheme
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var onSave: (() -> Void)?

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            Text(label)
                .font(Theme.Typography.caption1())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

            if isEditing {
                TextEditor(text: $text)
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    .scrollContentBackground(.hidden)  // Match QuickAddTaskView for consistent keyboard
                    .frame(minHeight: 100)
                    .padding(Theme.spacing12)
                    .background(colorScheme == .dark ? Theme.Dark.bgTertiary : Theme.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .focused($isFocused)
                    .onChange(of: isFocused) { _, focused in
                        if !focused && isEditing {
                            isEditing = false
                            onSave?()
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                isFocused = false
                            }
                        }
                    }
            } else {
                // Render markdown when not editing
                if text.isEmpty {
                    Text(placeholder)
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.spacing12)
                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        .onTapGesture {
                            isEditing = true
                            isFocused = true
                        }
                } else {
                    Text(text.attributedMarkdown())
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.spacing12)
                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        .onTapGesture {
                            isEditing = true
                            isFocused = true
                        }
                }
            }
        }
    }
}
