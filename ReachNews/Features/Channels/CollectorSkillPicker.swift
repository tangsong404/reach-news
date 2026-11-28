import SwiftUI

/// The public directory contains only available skills; selected historical bindings
/// are merged in so removed/unapproved sources never disappear silently.
struct CollectorSkillPicker: View {
    let skills: [CollectorSkill]
    var retainedSkills: [CollectorSkill] = []
    @Binding var selection: [String]
    @Binding var isPresented: Bool
    @Environment(\.appLocale) private var locale
    @Environment(AppEnvironment.self) private var env
    @AppTypography private var typography

    private var rows: [CollectorSkill] {
        var values = skills
        for skill in retainedSkills where !values.contains(where: { $0.id == skill.id }) {
            values.append(skill)
        }
        return values
    }

    private var unknownSelectedIDs: [String] {
        selection.filter { id in !rows.contains { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            List {
                if rows.isEmpty && selection.isEmpty {
                    Text(L10n.string("collector.empty", locale: locale))
                        .font(typography.body(15))
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(rows) { skill in
                    Button { toggle(skill.id, available: skill.available) } label: {
                        HStack(spacing: 12) {
                            CollectorIconView(iconURLPath: skill.iconURLPath, origin: env.session.resolvedBaseURL)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(skill.name).font(typography.body(15)).foregroundStyle(Palette.ink)
                                if !skill.available {
                                    Text(skill.message ?? L10n.string("collector.unavailable", locale: locale))
                                        .font(typography.body(13)).foregroundStyle(Palette.failedForeground)
                                }
                            }
                            Spacer(minLength: 8)
                            if selection.contains(skill.id) { Image(systemName: "checkmark").foregroundStyle(env.appearance.accent) }
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .disabled(!skill.available && !selection.contains(skill.id))
                    .accessibilityIdentifier("collector-picker-\(skill.id)")
                    .listRowBackground(Theme.surface(for: env.appearance.style))
                }
                ForEach(unknownSelectedIDs, id: \.self) { id in
                    Button { selection.removeAll { $0 == id } } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(id).font(typography.body(15))
                                Text(L10n.string("collector.unavailable", locale: locale))
                                    .font(typography.body(13)).foregroundStyle(Palette.failedForeground)
                            }
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                    .buttonStyle(.pressable)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas(for: env.appearance.style))
            .navigationTitle(L10n.string("collector.sources", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("common.done", locale: locale)) { isPresented = false }
                        .accessibilityIdentifier("collector-picker-done")
                }
            }
        }
        .accessibilityIdentifier("collector-picker")
    }

    private func toggle(_ id: String, available: Bool) {
        if selection.contains(id) { selection.removeAll { $0 == id } }
        else if available { selection.append(id) }
    }
}
