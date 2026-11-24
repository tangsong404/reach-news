import SwiftUI

// MARK: - 账号头部
//
// 「我的」页最上方的一条只读资料行：圆形头像 + 用户名 / 邮箱 / 套餐标识 + 行尾箭头。
// 本轮没有后端资料字段，也没有个人资料页，因此整行不可点：
// 箭头只保留参考图的观感，点击不触发任何导航、请求或状态变化。

struct AccountHeaderView: View {
    let profile: ProfileStore
    @Environment(\.appLocale) private var locale

    private let avatarSize: CGFloat = 46

    var body: some View {
        HStack(spacing: Space.m) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.userName)
                    .font(TypeFace.heading(15))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(profile.email)
                    .font(TypeFace.body(12))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                Text(L10n.string(profile.plan.labelKey, locale: locale))
                    .font(TypeFace.label(11))
                    .foregroundStyle(Palette.inkTertiary)
            }
            Spacer(minLength: Space.s)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.inkTertiary)
        }
        .padding(.vertical, Space.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("me-account-header")
        .accessibilityLabel(Text(accessibilitySummary))
    }

    /// 没有真实图片时用缺省头像：中性底 + 人形轮廓，
    /// 不会出现空白圆或破图占位。
    private var avatar: some View {
        ZStack {
            Circle().fill(Palette.paper)
            if let name = profile.avatarImageName {
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .overlay {
            Circle().strokeBorder(Palette.line, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        let separator = locale.identifier.lowercased().hasPrefix("zh") ? "，" : ", "
        return [
            profile.userName,
            profile.email,
            L10n.string(profile.plan.labelKey, locale: locale)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: separator)
    }
}
