// 正文 Markdown：用成熟的 CommonMark 实现（markdown-it），不自研正则。
// html: false —— 正文里的 HTML 按文字转义，不渲染；渲染范围严格限定 body。
import MarkdownIt from 'markdown-it';
import { bodyMarkdown } from './model.js';

const md = new MarkdownIt('commonmark', { html: false, linkify: false });

// 链接一律交给系统浏览器：Capacitor 拦截外部导航并用 ACTION_VIEW 打开
const defaultLink = md.renderer.rules.link_open || ((tokens, idx, opts, env, self) => self.renderToken(tokens, idx, opts));
md.renderer.rules.link_open = (tokens, idx, opts, env, self) => {
  tokens[idx].attrSet('target', '_blank');
  tokens[idx].attrSet('rel', 'noopener noreferrer');
  return defaultLink(tokens, idx, opts, env, self);
};

export const renderBody = (body) => md.render(bodyMarkdown(body));
