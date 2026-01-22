import SwiftUI

/// List Settings Modal with 3 tabs (matching mobile web app)
struct ListSettingsModal: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    let list: TaskList
    let onUpdate: (TaskList) -> Void
    let onDelete: () -> Void

    @State private var selectedTab = 0

    /// Check if current user can edit settings (is owner or admin)
    private var canEditSettings: Bool {
        guard let currentUserId = AuthManager.shared.userId else {
            return false
        }

        // Check if user is owner (check both ownerId field and owner object)
        // API may return ownerId or owner object depending on the endpoint
        if list.ownerId == currentUserId || list.owner?.id == currentUserId {
            return true
        }

        // Check if user is admin in legacy admins array
        if let admins = list.admins, admins.contains(where: { $0.id == currentUserId }) {
            return true
        }

        // Check in listMembers for admin role
        if let listMembers = list.listMembers {
            if listMembers.contains(where: { $0.user?.id == currentUserId && $0.role == "admin" }) {
                return true
            }
        }

        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker - Only show if user has edit permissions
                if canEditSettings {
                    Picker("", selection: $selectedTab) {
                        Label(NSLocalizedString("lists.filters", comment: ""), systemImage: "line.3.horizontal.decrease.circle")
                            .tag(0)
                        Label(NSLocalizedString("lists.members", comment: ""), systemImage: "person.2")
                            .tag(1)
                        Label(NSLocalizedString("lists.admin", comment: ""), systemImage: "gearshape")
                            .tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(Theme.spacing16)

                    Divider()
                }

                // Tab Content
                if canEditSettings {
                    // Show all tabs for owners/admins
                    TabView(selection: $selectedTab) {
                        ListSortFiltersTab(list: list, onUpdate: onUpdate)
                            .tag(0)

                        ListMembershipTab(list: list, onUpdate: onUpdate)
                            .tag(1)

                        ListAdminTab(list: list, onUpdate: onUpdate, onDelete: onDelete)
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                } else {
                    // Only show Filters tab for non-owners/non-admins
                    ListSortFiltersTab(list: list, onUpdate: onUpdate)
                }
            }
            .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
            .navigationTitle(NSLocalizedString("lists.list_settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
