// 界面语言：与可及清单相同的写法——界面文字直接写中文并包一层 $t()，
// 如 $t('今天')、$t('共 {n} 期', { n })；英文在 i18n-en.js，以中文原文为键。
// 偏好 'system' 跟随系统（系统是中文就用中文，否则英文），缺失译文回落中文。
import { reactive } from 'vue';
import EN from './i18n-en.js';

export const i18n = reactive({ lang: 'zh' });

const systemLang = () => (/^zh\b/i.test(navigator.language || 'zh') ? 'zh' : 'en');

export function applyLang(pref) {
  i18n.lang = pref === 'zh' || pref === 'en' ? pref : systemLang();
  document.documentElement.lang = i18n.lang === 'en' ? 'en' : 'zh-CN';
}

export const isEn = () => i18n.lang === 'en';

const fill = (s, p) => (p ? s.replace(/\{(\w+)\}/g, (m, k) => (k in p ? p[k] : m)) : s);

export function t(zh, p) {
  if (i18n.lang !== 'en') return fill(zh, p);
  const e = EN[zh];
  if (e === undefined) {
    if (import.meta.env?.DEV) console.warn('[i18n] missing:', zh);
    return fill(zh, p);
  }
  return fill(typeof e === 'function' ? e(p || {}) : e, p);
}

export const plural = (n, one, many = one + 's') => `${n} ${n === 1 ? one : many}`;
