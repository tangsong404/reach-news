import SwiftUI

// MARK: - 根视图
//
// 三个标签（日报 / 频道 / 我的）。标签栏与导航栏使用系统能力呈现半透明玻璃，
// 内容从其下方滚过；不手写毛玻璃材质。

struct RootTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.appLocale) private var locale
    @State private var selection: Tab = .briefs

    enum Tab: Hashable {
        case briefs
        case channels
        case me
    }

    var body: some View {
        Group {
            if env.session.isSignedIn {
                tabs
            } else {
                NavigationStack {
                    ConnectionView(session: env.session)
                }
            }
        }
        // 强调色由外观偏好决定（偏好页可切换），不再是固定墨黑。
        .tint(env.appearance.accent)
        // 风格切换后底色随之变化。
        .background(Theme.canvas(for: env.appearance.style))
        .task {
            // 启动时若已有会话，静默验证一次，不弹登录页。
            await env.session.validateStoredSession()
            // 时区失败不阻断主流程，内部回退 Asia/Shanghai。
            if env.session.isSignedIn {
                await env.settings.load()
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            BriefFeedView()
                .tabItem {
                    Label {
                        Text(L10n.string("tab.briefs", locale: locale))
                    } icon: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
                .tag(Tab.briefs)

            ChannelListView()
                .tabItem {
                    Label {
                        Text(L10n.string("tab.channels", locale: locale))
                    } icon: {
                        Image(systemName: "slider.horizontal.below.rectangle")
                    }
                }
                .tag(Tab.channels)

            MeView()
                .tabItem {
                    Label {
                        Text(L10n.string("tab.me", locale: locale))
                    } icon: {
                        Image(systemName: "person.crop.circle")
                    }
                }
                .tag(Tab.me)
        }
        .accessibilityIdentifier("root-tabs")
    }
}
