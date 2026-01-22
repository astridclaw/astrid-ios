import SwiftUI

struct TaskListPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var listService = ListService.shared
    @Binding var selectedListIds: Set<String>

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                    .ignoresSafeArea()

                if listService.isLoading && listService.lists.isEmpty {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Theme.accent)
                } else if listService.lists.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle(NSLocalizedString("list.select_lists", comment: "Select Lists"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(colorScheme == .dark ? Theme.Dark.headerBg : Theme.headerBg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .disabled(selectedListIds.isEmpty)
                }
            }
        }
        .task {
            if listService.lists.isEmpty {
                _ = try? await listService.fetchLists()
            }
        }
    }

    private var listContent: some View {
        List {
            // Filter out virtual lists (saved filters) - only show real lists
            ForEach(listService.lists.filter { $0.isVirtual != true }) { list in
                Button {
                    toggleListSelection(list.id)
                } label: {
                    HStack {
                        ListImageView(list: list, size: 12)

                        Text(list.name)
                            .font(Theme.Typography.body())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                        Spacer()

                        if selectedListIds.contains(list.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.accent)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.border : Theme.border)
                        }
                    }
                    .padding(.vertical, Theme.spacing8)
                }
                .listRowBackground(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
                .listRowSeparator(.visible)
                .listRowSeparatorTint(colorScheme == .dark ? Theme.Dark.border : Theme.border)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
    }

    private var emptyState: some View {
        ScrollView {
            EmptyStateView(
                message: NSLocalizedString("empty_state.no_lists", comment: "")
            )
            .frame(minHeight: UIScreen.main.bounds.height - 200) // Ensure scrollable for pull-to-refresh
        }
        .refreshable {
            _ = try? await listService.fetchLists()
        }
    }

    private func toggleListSelection(_ listId: String) {
        if selectedListIds.contains(listId) {
            selectedListIds.remove(listId)
        } else {
            selectedListIds.insert(listId)
        }
    }
}
