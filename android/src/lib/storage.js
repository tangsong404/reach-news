// 唯一和「存在哪」打交道的文件。Preferences 在手机上是安卓 SharedPreferences（应用私有），
// 浏览器里退化成 localStorage。
//
// ADR 0003：不缓存任何日报、素材或运行内容。这里只有：
//   - 会话凭证（token + 到期时刻）
//   - 偏好（Base URL、界面语言）
//   - 轮询基线 lastSeenAt（单独命名、单独存放，与任何内容缓存无关）
//   - 本机收藏的日报 ID、本机频道标识色
import { Preferences } from '@capacitor/preferences';

const get = async (key) => (await Preferences.get({ key })).value;
const set = (key, value) => (value == null ? Preferences.remove({ key }) : Preferences.set({ key, value: String(value) }));

async function getJSON(key, fallback) {
  try {
    const v = await get(key);
    return v ? JSON.parse(v) : fallback;
  } catch {
    return fallback;
  }
}
const setJSON = (key, v) => set(key, JSON.stringify(v));

export const storage = {
  // 会话凭证
  async loadSession() {
    const token = await get('session.token');
    const exp = Number(await get('session.expiresAt'));
    const userName = (await get('session.userName')) || '';
    return token && exp ? { token, expiresAt: new Date(exp), userName } : null;
  },
  async saveSession(s) {
    await set('session.token', s.token);
    await set('session.expiresAt', s.expiresAt.getTime());
    await set('session.userName', s.userName || '');
  },
  async clearSession() {
    await Promise.all(['session.token', 'session.expiresAt', 'session.userName'].map((k) => set(k, null)));
  },

  // 偏好
  loadPrefs: () => getJSON('preferences', {}),
  savePrefs: (p) => setJSON('preferences', p),

  // 轮询基线
  async loadLastSeenAt() {
    const v = Number(await get('polling.baseline.lastSeenAt'));
    return v > 0 ? new Date(v) : null;
  },
  saveLastSeenAt: (d) => set('polling.baseline.lastSeenAt', d ? d.getTime() : null),

  // 本机收藏 / 频道颜色
  loadSaved: () => getJSON('saved.briefs', []),
  saveSaved: (ids) => setJSON('saved.briefs', ids),
  loadColors: () => getJSON('channels.colors', {}),
  saveColors: (m) => setJSON('channels.colors', m),
};
