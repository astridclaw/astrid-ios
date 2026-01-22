import SwiftUI

/// Inline priority picker
struct InlinePriorityPicker: View {
    @Environment(\.colorScheme) var colorScheme
    let label: String
    @Binding var priority: Task.Priority
    var onSave: (() -> Void)?

    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing8) {
            Text(label)
                .font(Theme.Typography.caption1())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

            Button(action: { showingPicker = true }) {
                HStack {
                    Circle()
                        .fill(priorityColor)
                        .frame(width: 12, height: 12)
                    Text(priority.displayName)
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }
                .padding(Theme.spacing12)
                .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingPicker) {
                NavigationStack {
                    List {
                        ForEach([Task.Priority.none, .low, .medium, .high], id: \.self) { p in
                            Button(action: {
                                priority = p
                                showingPicker = false
                                onSave?()
                            }) {
                                HStack {
                                    Circle()
                                        .fill(colorForPriority(p))
                                        .frame(width: 16, height: 16)
                                    Text(p.displayName)
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Spacer()
                                    if priority == p {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .navigationTitle(label)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingPicker = false
                            }
                        }
                    }
                }
            }
        }
    }

    private var priorityColor: Color {
        colorForPriority(priority)
    }

    private func colorForPriority(_ p: Task.Priority) -> Color {
        switch p {
        case .none: return Theme.priorityNone
        case .low: return Theme.priorityLow
        case .medium: return Theme.priorityMedium
        case .high: return Theme.priorityHigh
        }
    }
}
