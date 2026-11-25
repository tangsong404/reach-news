// 与可及清单相同的 UI 基础设施：触感、提示条、安卓返回键栈、页面栈、键盘高度。
import { reactive, watchEffect } from 'vue';
import { Capacitor } from '@capacitor/core';
import { Haptics, ImpactStyle } from '@capacitor/haptics';

const native = Capacitor.isNativePlatform();
export const haptic = {
  light: () => native && Haptics.impact({ style: ImpactStyle.Light }).catch(() => {}),
  select: () => native && Haptics.selectionChanged().catch(() => {}),
};

// ---- 提示条 ----
export const toastState = reactive({ id: 0, text: '' });
let timer;
export function toast(text, duration = 2400) {
  Object.assign(toastState, { id: toastState.id + 1, text });
  clearTimeout(timer);
  timer = setTimeout(() => (toastState.text = ''), duration);
}

// ---- 安卓返回键：弹窗按打开顺序入栈，返回键先关最上面的 ----
const backStack = [];
export const pushBack = (fn) => {
  backStack.push(fn);
  return () => {
    const i = backStack.lastIndexOf(fn);
    if (i >= 0) backStack.splice(i, 1);
  };
};
export function handleBack() {
  const fn = backStack.at(-1);
  if (!fn) return false;
  fn();
  return true;
}

// ---- 页面栈：每个标签各自一条栈（对应 iOS 每个标签各自的 NavigationStack） ----
export const nav = reactive({ tab: 'feed', stacks: { feed: [], channels: [], me: [] } });
let seq = 0;
export function push(name, props = {}) {
  nav.stacks[nav.tab].push({ key: ++seq, name, props });
}
export function pop() {
  const s = nav.stacks[nav.tab];
  if (s.length) s.pop();
}
/** 替换栈顶（例如 fork 后从订阅详情直接进入编辑页）。 */
export function replaceTop(name, props = {}) {
  const s = nav.stacks[nav.tab];
  s.pop();
  s.push({ key: ++seq, name, props });
}
export const canPop = () => nav.stacks[nav.tab].length > 0;

// ---- 键盘高度：手机上由 MainActivity 逐帧推送（window.__ime），浏览器里用 visualViewport 估算 ----
// 老 WebView 可能已经因键盘缩小了页面，那部分不能再让一遍（同可及清单的 lift 计算）。
export const keyboard = reactive({ height: 0, lift: 0, snap: false });
const root = document.documentElement;
watchEffect(
  () => {
    root.style.setProperty('--kb', keyboard.lift + 'px');
    root.classList.toggle('kb-snap', keyboard.snap);
  },
  { flush: 'sync' },
);
let baseH = window.innerHeight;
function recalc() {
  if (!keyboard.height) baseH = Math.max(baseH, window.innerHeight);
  keyboard.lift = Math.max(0, keyboard.height - Math.max(0, baseH - window.innerHeight));
}
window.addEventListener('resize', recalc);
if (native) {
  window.__ime = (h, animating) => {
    keyboard.height = h;
    keyboard.snap = animating;
    recalc();
  };
} else if (window.visualViewport) {
  const vv = window.visualViewport;
  vv.addEventListener('resize', () => {
    keyboard.height = Math.max(0, Math.round(window.innerHeight - vv.height - vv.offsetTop));
    recalc();
  });
}
