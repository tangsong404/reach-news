import SwiftUI

/// Read-only bound source list. Configuration failure never hides historical briefs.
struct CollectorSourcesView: View {
    let skills: [CollectorSkill]
    let selectedIDs: [String]
    var collectionStatus: CollectionStatus?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale
    @AppTypography private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(skills) { skill in
                HStack(alignment: .center, spacing: 8) {
                    CollectorIconView(iconURLPath: skill.iconURLPath, origin: env.session.resolvedBaseURL)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name).font(typography.body(13)).foregroundStyle(Palette.inkSecondary)
                        if !skill.available {
                            Text(skill.message ?? L10n.string("collector.unavailable", locale: locale))
                                .font(typography.body(12)).foregroundStyle(Palette.failedForeground)
                        }
                    }
                }
            }
            ForEach(selectedIDs.filter { id in !skills.contains { $0.id == id } }, id: \.self) { id in
                Text(id).font(typography.body(12)).foregroundStyle(Palette.failedForeground)
            }
            if collectionStatus?.available == false || selectedIDs.isEmpty {
                Text(pausedMessage)
                    .font(typography.body(12)).foregroundStyle(Palette.failedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pausedMessage: String {
        switch collectionStatus?.pausedReason {
        case "invalid_collector_skill": return L10n.string("collector.unavailable", locale: locale)
        default: return L10n.string("collector.bindingRequired", locale: locale)
        }
    }
}
