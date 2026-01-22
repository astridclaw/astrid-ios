import SwiftUI

/// Two-column row helper for task detail fields
/// Label on the left, content on the right
/// Uses standard label width for all iPad orientations since portrait has 72% detail panel
struct TwoColumnRow<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    let label: String
    @ViewBuilder let content: () -> Content

    // Standard label width for all device types
    // iPad portrait now has 60% detail panel width, so no need for wider labels
    private var labelWidth: CGFloat {
        return 80
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacing12) {
            Text(label)
                .font(Theme.Typography.body())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                .frame(width: labelWidth, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing8)
    }
}

#Preview {
    VStack {
        TwoColumnRow(label: "Date") {
            Text("Today")
        }

        TwoColumnRow(label: "Priority") {
            Text("High")
        }
    }
}
