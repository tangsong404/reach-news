import SwiftUI

// MARK: - 账号卡片
//
// 「我的」页最上方的一张卡：圆形头像 + 用户名 / 邮箱 / 套餐标签 + 行尾箭头。
// 数据全部来自服务端真实字段，见 `ProfileStore`。
// 整卡可点，进入个人页（`AccountDetailView`）。

struct AccountHeaderView: View {
    @AppTypography private var typography

    let profile: ProfileStore
    @Environment(\.appLocale) private var locale

    /// 卡片里的头像明显大于普通列表行，让它成为这一页的视觉主体。
    private let avatarSize: CGFloat = 62

    var body: some View {
        HStack(spacing: Space.m) {
            AvatarView(url: profile.avatarURL, size: avatarSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.userName)
                    .font(typography.heading(22))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier("account-name")

                // 邮箱可能为 null：显示占位而不是空行，也不显示字面 null。
                Text(profile.email ?? L10n.string("me.account.email.empty", locale: locale))
                    .font(typography.body(15))
                    .foregroundStyle(profile.email == nil ? Palette.inkTertiary : Palette.inkSecondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("account-email")


            }

            Spacer(minLength: Space.s)
            TierBadge(tier: profile.planLabel)
        }
        .padding(.vertical, Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("me-account-header")
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        let separator = locale.identifier.lowercased().hasPrefix("zh") ? "，" : ", "
        return [profile.userName, profile.email, profile.planLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }
}
