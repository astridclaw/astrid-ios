import SwiftUI


struct ListsView: View {
    @StateObject private var listService = ListService.shared
    @State private var showingNewList = false
    
    var body: some View {
        NavigationStack {
            Group {
                if listService.isLoading && listService.lists.isEmpty {
                    ProgressView(NSLocalizedString("lists.loading", comment: ""))
                } else if listService.lists.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle(NSLocalizedString("navigation.lists", comment: ""))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewList = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewList) {
                ListEditView()
            }
        }
        .task {
            if listService.lists.isEmpty {
                _ = try? await listService.fetchLists()
            }
        }
        .refreshable {
            _ = try? await listService.fetchLists()
        }
    }
    
    // MARK: - Content
    
    private var listContent: some View {
        List {
            if !listService.favoriteLists.isEmpty {
                Section(NSLocalizedString("navigation.favorites", comment: "")) {
                    ForEach(listService.favoriteLists) { list in
                        NavigationLink(destination: Text(NSLocalizedString("list.details", comment: "List Details"))) {
                            HStack(spacing: 12) {
                                ListImageView(list: list, size: 12)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(list.name)
                                        .font(.body)
                                        .fontWeight(.medium)

                                    if let description = list.description, !description.isEmpty {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                if list.isFavorite == true {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundColor(.yellow)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            Section(NSLocalizedString("lists.all_lists", comment: "")) {
                ForEach(listService.lists) { list in
                    NavigationLink(destination: Text(NSLocalizedString("list.details", comment: "List Details"))) {
                        HStack(spacing: 12) {
                            ListImageView(list: list, size: 12)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.name)
                                    .font(.body)
                                    .fontWeight(.medium)

                                if let description = list.description, !description.isEmpty {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteLists)
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private var emptyState: some View {
        ScrollView {
            EmptyStateView(
                message: NSLocalizedString("lists.empty_state_message", comment: ""),
                buttonTitle: NSLocalizedString("lists.add_list", comment: ""),
                buttonAction: { showingNewList = true }
            )
            .frame(minHeight: UIScreen.main.bounds.height - 200) // Ensure scrollable for pull-to-refresh
        }
        .refreshable {
            _ = try? await listService.fetchLists()
        }
    }
    
    // MARK: - Actions
    
    private func deleteLists(at offsets: IndexSet) {
        // Capture lists before async operations to avoid index out of bounds
        let listsToDelete: [TaskList] = offsets.compactMap { index in
            guard index < listService.lists.count else { return nil }
            return listService.lists[index]
        }

        for list in listsToDelete {
            _Concurrency.Task {
                try? await listService.deleteList(listId: list.id)
            }
        }
    }
}

#Preview {
    ListsView()
}
