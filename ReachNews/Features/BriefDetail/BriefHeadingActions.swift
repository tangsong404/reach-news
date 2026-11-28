import Foundation

// MARK: - 事件频道的预填内容
//
// 小标题右侧的「跟踪」按钮直接把用户带到频道创建页，并在那里预填名称与提示词。
// 这里只负责算出预填内容，不涉及跳转与界面。
//
// 事件不是新的后端实体：它仍是一个普通频道，提交走同一个创建接口，
// 用户可以在提交前改掉任何预填内容。

enum TrackedEventDraft {

    /// 预填名称：直接用小标题文字，只去掉首尾空白（不改写文字本身）。
    static func name(heading: String) -> String {
        heading.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 预填提示词的本地化键；模板正文放在 Localizable.strings，
    /// 这样两种语言都能写出通顺的句子，而不是拼一段中英混排。
    static let promptKey = "brief.heading.track.prompt"

    /// 用实际的小标题文字渲染提示词模板。
    static func prompt(heading: String, locale: Locale) -> String {
        L10n.format(promptKey, locale: locale, name(heading: heading))
    }
}
