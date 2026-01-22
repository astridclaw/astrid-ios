import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean

    var body: some View {
        ZStack {
            // Theme background
            Color.clear.themedBackgroundPrimary()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Floating header
                FloatingTextHeader(NSLocalizedString("appearance", comment: ""), icon: "paintbrush", showBackButton: true)
                    .padding(.top, Theme.spacing8)

                // Content
                Form {
                    Section(header: Text(NSLocalizedString("settings.appearance.theme", comment: ""))) {
                Picker(NSLocalizedString("appearance", comment: ""), selection: $themeMode) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(header: Text(NSLocalizedString("settings.appearance.email_to_task", comment: "")), footer: Text(NSLocalizedString("settings.appearance.email_to_task_footer", comment: ""))) {
                VStack(alignment: .leading, spacing: Theme.spacing12) {
                    HStack(spacing: Theme.spacing8) {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(Theme.accent)
                        Text("remindme@astrid.cc")
                            .font(Theme.Typography.body())
                            .fontWeight(.medium)
                    }

                    VStack(alignment: .leading, spacing: Theme.spacing8) {
                        HStack(alignment: .top, spacing: Theme.spacing8) {
                            Text("•")
                                .foregroundColor(Theme.accent)
                            Text(NSLocalizedString("settings.appearance.email_to_task_self", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }

                        HStack(alignment: .top, spacing: Theme.spacing8) {
                            Text("•")
                                .foregroundColor(Theme.accent)
                            Text(NSLocalizedString("settings.appearance.email_to_task_assigned", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }

                        HStack(alignment: .top, spacing: Theme.spacing8) {
                            Text("•")
                                .foregroundColor(Theme.accent)
                            Text(NSLocalizedString("settings.appearance.email_to_task_group", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }

                        Divider()
                            .padding(.vertical, Theme.spacing4)

                        HStack(alignment: .top, spacing: Theme.spacing8) {
                            Text("•")
                                .foregroundColor(.purple)
                            Text(NSLocalizedString("settings.appearance.email_to_task_subject", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }

                        HStack(alignment: .top, spacing: Theme.spacing8) {
                            Text("•")
                                .foregroundColor(.purple)
                            Text(NSLocalizedString("settings.appearance.email_to_task_body", comment: ""))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        }
                    }
                }
                .padding(.vertical, Theme.spacing8)
            }
                }

                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .navigationBarHidden(true)
        .swipeToDismiss()
    }
}

enum ThemeMode: String, CaseIterable, Codable {
    case ocean, light, dark, auto

    var displayName: String {
        switch self {
        case .ocean: return NSLocalizedString("theme.ocean", comment: "")
        case .light: return NSLocalizedString("theme.light", comment: "")
        case .dark: return NSLocalizedString("theme.dark", comment: "")
        case .auto: return NSLocalizedString("theme.auto", comment: "")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .ocean: return .light  // Ocean uses light theme with cyan background
        case .light: return .light  // Light always uses light appearance
        case .dark: return .dark    // Dark always uses dark appearance
        case .auto: return nil      // Auto follows system (sunrise/sunset)
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
