import SwiftUI

struct ListFiltersView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var listService = ListService.shared
    @ObservedObject private var memberService = ListMemberService.shared

    let list: TaskList

    @State private var sortBy: String
    @State private var filterCompletion: String
    @State private var filterPriority: String
    @State private var filterDueDate: String
    @State private var filterAssignee: String
    @State private var filterRepeating: String
    @State private var isSaving = false
    @State private var showingSaveDialog = false

    init(list: TaskList) {
        self.list = list
        _sortBy = State(initialValue: list.sortBy ?? "auto")
        _filterCompletion = State(initialValue: list.filterCompletion ?? "default")
        _filterPriority = State(initialValue: list.filterPriority ?? "all")
        _filterDueDate = State(initialValue: list.filterDueDate ?? "all")
        _filterAssignee = State(initialValue: list.filterAssignee ?? "all")
        _filterRepeating = State(initialValue: list.filterRepeating ?? "all")
    }

    var body: some View {
        Form {
            // Sort Section
            Section(NSLocalizedString("filters.sort_by", comment: "")) {
                Picker(NSLocalizedString("filters.sort", comment: ""), selection: $sortBy) {
                    Text(NSLocalizedString("filters.auto", comment: "")).tag("auto")
                    Text(NSLocalizedString("tasks.priority", comment: "")).tag("priority")
                    Text(NSLocalizedString("lists.due_date", comment: "")).tag("due_date")
                    Text(NSLocalizedString("filters.who", comment: "")).tag("assignee")
                    Text(NSLocalizedString("tasks.completed", comment: "")).tag("completed")
                    Text(NSLocalizedString("tasks.incomplete", comment: "")).tag("incomplete")
                    Text(NSLocalizedString("filters.manual", comment: "")).tag("manual")
                }
                .onChange(of: sortBy) { saveFilters() }
            }

            // Completion Filter
            Section(NSLocalizedString("filters.completion_status", comment: "")) {
                Picker(NSLocalizedString("filters.show", comment: ""), selection: $filterCompletion) {
                    Text(NSLocalizedString("filters.default", comment: "")).tag("default")
                    Text(NSLocalizedString("filters.all_tasks", comment: "")).tag("all")
                    Text(NSLocalizedString("tasks.completed", comment: "")).tag("completed")
                    Text(NSLocalizedString("tasks.incomplete", comment: "")).tag("incomplete")
                }
                .onChange(of: filterCompletion) { saveFilters() }
            }

            // Priority Filter
            Section(NSLocalizedString("tasks.priority", comment: "")) {
                Picker(NSLocalizedString("tasks.priority", comment: ""), selection: $filterPriority) {
                    Text(NSLocalizedString("filters.all_priorities", comment: "")).tag("all")
                    Text(NSLocalizedString("filters.highest_priority", comment: "")).tag("3")
                    Text(NSLocalizedString("filters.high_priority", comment: "")).tag("2")
                    Text(NSLocalizedString("filters.medium_priority", comment: "")).tag("1")
                    Text(NSLocalizedString("filters.low_priority", comment: "")).tag("0")
                }
                .onChange(of: filterPriority) { saveFilters() }
            }

            // Due Date Filter
            Section(NSLocalizedString("tasks.due_date", comment: "")) {
                Picker(NSLocalizedString("tasks.due_date", comment: ""), selection: $filterDueDate) {
                    Text(NSLocalizedString("filters.all_dates", comment: "")).tag("all")
                    Text(NSLocalizedString("tasks.overdue", comment: "")).tag("overdue")
                    Text(NSLocalizedString("time.today", comment: "")).tag("today")
                    Text(NSLocalizedString("filters.this_week", comment: "")).tag("this_week")
                    Text(NSLocalizedString("filters.this_month", comment: "")).tag("this_month")
                    Text(NSLocalizedString("filters.no_due_date", comment: "")).tag("no_date")
                }
                .onChange(of: filterDueDate) { saveFilters() }
            }

            // Assignee Filter
            Section(NSLocalizedString("filters.who", comment: "")) {
                Picker(NSLocalizedString("filters.who", comment: ""), selection: $filterAssignee) {
                    Text(NSLocalizedString("filters.all", comment: "")).tag("all")
                    Text(NSLocalizedString("filters.me", comment: "")).tag("current_user")
                    Text(NSLocalizedString("filters.not_me", comment: "")).tag("not_current_user")
                    Text(NSLocalizedString("filters.unassigned", comment: "")).tag("unassigned")

                    if !memberService.members.isEmpty {
                        Divider()
                        ForEach(memberService.members) { member in
                            Text(member.displayName).tag(member.id)
                        }
                    }
                }
                .onChange(of: filterAssignee) { saveFilters() }
            }

            // Repeating Filter
            Section(NSLocalizedString("lists.repeating", comment: "")) {
                Picker(NSLocalizedString("lists.repeating", comment: ""), selection: $filterRepeating) {
                    Text(NSLocalizedString("filters.all", comment: "")).tag("all")
                    Text(NSLocalizedString("filters.not_repeating", comment: "")).tag("not_repeating")
                    Text(NSLocalizedString("lists.daily", comment: "")).tag("daily")
                    Text(NSLocalizedString("lists.weekly", comment: "")).tag("weekly")
                    Text(NSLocalizedString("lists.monthly", comment: "")).tag("monthly")
                    Text(NSLocalizedString("lists.yearly", comment: "")).tag("yearly")
                }
                .onChange(of: filterRepeating) { saveFilters() }
            }

            // Save as Smart List
            if hasActiveFilters {
                Section {
                    Button {
                        showingSaveDialog = true
                    } label: {
                        HStack {
                            Image(systemName: "star.circle.fill")
                                .foregroundColor(Theme.accent)
                            Text(NSLocalizedString("filters.save_as_smart_list", comment: ""))
                                .foregroundColor(Theme.accent)
                        }
                    }
                } footer: {
                    Text(NSLocalizedString("filters.save_footer", comment: ""))
                        .font(Theme.Typography.caption1())
                }
            }

            // Clear All
            if hasActiveFilters {
                Section {
                    Button(NSLocalizedString("filters.clear_all", comment: "")) {
                        clearAllFilters()
                    }
                    .foregroundColor(.red)
                }
            }

            if isSaving {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text(NSLocalizedString("filters.saving", comment: ""))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("filters.sort_and_filters", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSaveDialog) {
            SaveFilterDialog(
                currentFilters: SaveFilterDialog.FilterSettings(
                    sortBy: sortBy,
                    filterCompletion: filterCompletion,
                    filterPriority: filterPriority,
                    filterDueDate: filterDueDate,
                    filterAssignee: filterAssignee,
                    filterRepeating: filterRepeating
                ),
                onSaved: {
                    // Optionally reset filters after saving
                }
            )
        }
        .task {
            await loadMembers()
        }
    }

    private var hasActiveFilters: Bool {
        return sortBy != "auto"
            || filterCompletion != "default"
            || filterPriority != "all"
            || filterDueDate != "all"
            || filterAssignee != "all"
            || filterRepeating != "all"
    }

    private func loadMembers() async {
        do {
            try await memberService.fetchMembers(listId: list.id)
        } catch {
            print("Failed to load members: \(error)")
        }
    }

    private func saveFilters() {
        guard !isSaving else { return }

        isSaving = true

        _Concurrency.Task {
            defer { isSaving = false }

            let updates: [String: Any] = [
                "sortBy": sortBy,
                "filterCompletion": filterCompletion,
                "filterPriority": filterPriority,
                "filterDueDate": filterDueDate,
                "filterAssignee": filterAssignee,
                "filterRepeating": filterRepeating
            ]

            do {
                _ = try await listService.updateListAdvanced(
                    listId: list.id,
                    updates: updates
                )
                print("Saved filters")
            } catch {
                print("Failed to save filters: \(error)")
            }
        }
    }

    private func clearAllFilters() {
        sortBy = "auto"
        filterCompletion = "default"
        filterPriority = "all"
        filterDueDate = "all"
        filterAssignee = "all"
        filterRepeating = "all"
        saveFilters()
    }
}
