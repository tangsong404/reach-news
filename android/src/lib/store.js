// 应用状态：会话、日报流、频道、收藏、本机颜色。行为与 iOS 的各个 Store 一一对应。
import { reactive, computed } from 'vue';
import { storage } from './storage.js';
import { createApi } from './api.js';
import {
  ApiError, DEFAULT_HOST, parseBaseURL, mergeBriefs, searchBriefs, coversLowerBound, nextBaseline,
  canSubscribe, isSubscription, canEdit, paletteIndex, paletteValue, fallbackIndex, leastUsedIndex, DEFAULT_LIMIT,
} from './model.js';
import { setTimeZone, resolveRange, matchesFilter, groupByDay, FALLBACK_TZ } from './time.js';

export const state = reactive({
  ready: false,
  session: null, // { token, expiresAt, userName }
  prefs: { baseURL: DEFAULT_HOST, lang: 'system' },
  timeZone: FALLBACK_TZ,
  saved: [], // 本机收藏的日报 ID（不同步服务端）
  savedBriefs: {}, // 本次运行中见过的收藏日报对象，仅内存
  colors: {}, // channelId → 色板索引（仅本机）
});

const baseURL = () => parseBaseURL(state.prefs.baseURL) || DEFAULT_HOST;

export const api = createApi({
  baseURL,
  token: () => state.session?.token || null,
  onUnauthorized: () => handleUnauthorized(),
});

const asError = (e) => (e instanceof ApiError ? e : new ApiError('transport', String(e?.message || e)));

// ================= 启动 =================

export async function initStore() {
  const [session, prefs, saved, colors] = await Promise.all([
    storage.loadSession(),
    storage.loadPrefs(),
    storage.loadSaved(),
    storage.loadColors(),
  ]);
  Object.assign(state.prefs, prefs);
  state.saved = saved;
  state.colors = colors;
  if (session && session.expiresAt > new Date()) state.session = session;
  else if (session) await storage.clearSession(); // 已过期：丢弃并回登录页
  state.ready = true;
  if (state.session) loadSettings();
}

/** 服务端时区；失败或非法回退 Asia/Shanghai，不阻断主流程。 */
export async function loadSettings() {
  try {
    const d = await api.settings();
    state.timeZone = setTimeZone(d?.timeZone);
  } catch {
    state.timeZone = setTimeZone(null);
  }
}

export function savePrefs(patch) {
  Object.assign(state.prefs, patch);
  storage.savePrefs({ ...state.prefs });
}

// ================= 会话 =================

export const login = reactive({ busy: false, error: null, blockedUntil: 0, now: Date.now() });

export const throttleSeconds = computed(() => Math.max(0, Math.ceil((login.blockedUntil - login.now) / 1000)));

/** 账号密码登录。成功才写入凭证；429 本地冷却 5 分钟，绝不自动重试。 */
export async function signIn(rawBase, username, password) {
  const base = parseBaseURL(rawBase);
  if (!base) return (login.error = new ApiError('configuration')), false;
  if (throttleSeconds.value > 0 || login.busy) return false;
  login.busy = true;
  login.error = null;
  try {
    const session = await api.login(base, username.trim(), password);
    if (!session.userName) session.userName = username.trim();
    await storage.saveSession(session);
    savePrefs({ baseURL: base });
    state.session = session;
    resetAll();
    loadSettings();
    return true;
  } catch (e) {
    const err = asError(e);
    if (err.kind === 'tooManyAttempts') login.blockedUntil = Date.now() + 5 * 60 * 1000;
    login.error = err;
    return false;
  } finally {
    login.busy = false;
  }
}

/** 退出：通知服务端，无论结果如何都清本地凭证。 */
export async function signOut() {
  try {
    await api.logout();
  } catch {
    /* 失败不阻碍本地清理 */
  }
  await clearSession();
}

export function handleUnauthorized() {
  if (!state.session) return;
  login.error = new ApiError('unauthorized');
  clearSession();
}

async function clearSession() {
  state.session = null;
  resetAll();
  await storage.clearSession();
}

function resetAll() {
  Object.assign(feed, freshFeed());
  Object.assign(channels, freshChannels());
}

// ================= 日报流 =================

const freshFeed = () => ({
  briefs: [],
  channelsById: {},
  loading: false,
  refreshing: false,
  loadingMore: false,
  hasMore: true,
  nextCursor: null,
  error: null,
  newIds: [],
  search: '',
  filter: { time: 'all', start: null, end: null, channelIds: [] },
});
export const feed = reactive(freshFeed());

export const feedVisible = computed(() =>
  searchBriefs(feed.briefs, feed.search).filter((b) => matchesFilter(b, feed.filter)),
);
export const feedGroups = computed(() => groupByDay(feedVisible.value));
export const feedChannels = computed(() =>
  Object.values(feed.channelsById).sort((a, b) => a.name.localeCompare(b.name)),
);

export function channelName(brief) {
  return brief.channelName || feed.channelsById[brief.channelId]?.name || channels.byId(brief.channelId)?.name || null;
}

async function loadFeedChannels() {
  try {
    const list = await api.allChannels(false);
    // 默认列表已是「我的 + 订阅的」；订阅频道的日报按原 channelId 呈现
    feed.channelsById = Object.fromEntries(list.map((c) => [c.id, c]));
  } catch {
    /* 频道表只用于着色与名称兜底，取失败不阻断日报 */
  }
}

async function fetchFeedPage() {
  const p = await api.allBriefs(feed.nextCursor, DEFAULT_LIMIT);
  feed.nextCursor = p.nextCursor;
  feed.hasMore = !!p.nextCursor;
  return p.items;
}

export async function loadFeed({ refresh = false } = {}) {
  const flag = refresh ? 'refreshing' : 'loading';
  if (feed.loading || feed.refreshing) return;
  feed[flag] = true;
  feed.error = null;
  try {
    await loadFeedChannels();
    feed.nextCursor = null;
    feed.hasMore = true;
    const items = await fetchFeedPage();
    feed.briefs = mergeBriefs(refresh ? feed.briefs : [], items);
    await pollCursor();
  } catch (e) {
    const err = asError(e);
    // 断网时不展示任何历史内容（ADR 0003）
    if (err.kind === 'offline') (feed.briefs = []), (feed.hasMore = false);
    feed.error = err;
  } finally {
    feed[flag] = false;
  }
}

export async function loadMoreFeed() {
  if (!feed.hasMore || feed.loadingMore || feed.loading) return;
  feed.loadingMore = true;
  try {
    feed.briefs = mergeBriefs(feed.briefs, await fetchFeedPage());
  } catch (e) {
    feed.error = asError(e);
  } finally {
    feed.loadingMore = false;
  }
}

/** 筛选起点早于已加载边界：继续翻页直到覆盖或到底，不只对已加载的做局部筛选。 */
export async function loadUntilCoveringFilter() {
  const range = resolveRange(feed.filter);
  if (!range) return;
  for (let i = 0; i < 20 && feed.hasMore && !coversLowerBound(feed.briefs, range[0]); i++) {
    const before = feed.briefs.length;
    await loadMoreFeed();
    if (feed.briefs.length === before) break;
  }
}

/** /cursor?since=lastSeenAt：新日报打「新」标记；channels 有变动则刷新频道表。 */
export async function pollCursor() {
  try {
    const baseline = await storage.loadLastSeenAt();
    const payload = await api.cursor(baseline);
    // 首次启动（没有基线）回落 1970 全量，那时一切都「新」，不标记
    if (baseline) feed.newIds = [...new Set([...feed.newIds, ...payload.briefs.map((b) => b.id)])];
    const next = nextBaseline(baseline, payload);
    if (next && next !== baseline) await storage.saveLastSeenAt(next);
    if (payload.channels.length) {
      await loadFeedChannels();
      if (channels.loaded) loadChannels();
    }
  } catch {
    /* 轮询失败不影响已加载内容 */
  }
}

/** 取消订阅后：该频道的日报立即从日报流与筛选里消失。 */
function forgetChannel(id) {
  delete feed.channelsById[id];
  feed.briefs = feed.briefs.filter((b) => b.channelId !== id);
  feed.filter.channelIds = feed.filter.channelIds.filter((x) => x !== id);
}

// ================= 收藏（仅本机） =================

export const isSaved = (id) => state.saved.includes(id);
export function toggleSaved(brief) {
  state.saved = isSaved(brief.id) ? state.saved.filter((x) => x !== brief.id) : [brief.id, ...state.saved];
  if (isSaved(brief.id)) state.savedBriefs[brief.id] = brief;
  storage.saveSaved(state.saved);
}

// ================= 频道标识色 =================

export const localColorIndex = (id) => (id in state.colors ? state.colors[id] : null);
export const effectiveColorIndex = (id) => localColorIndex(id) ?? fallbackIndex(id);
/** 订阅色（服务端）优先 → 本地色板 → 按 id 的稳定色。 */
export function colorIndexFor(channelOrId) {
  if (typeof channelOrId === 'string') {
    const c = channels.byId(channelOrId) || feed.channelsById[channelOrId];
    return c ? colorIndexFor(c) : effectiveColorIndex(channelOrId);
  }
  return paletteIndex(channelOrId.subscriptionColor) ?? effectiveColorIndex(channelOrId.id);
}
export const colorFor = (c) => paletteValue(colorIndexFor(c));
export function setColor(id, index) {
  state.colors = { ...state.colors, [id]: index };
  storage.saveColors(state.colors);
}
export const suggestedColor = () => leastUsedIndex(Object.values(state.colors));

// ================= 频道 =================

const freshChannels = () => ({
  mine: [],
  subscribed: [],
  discover: [],
  latestRuns: {},
  loading: false,
  loaded: false,
  error: null,
  discoverError: null,
  discoverExpanded: false,
  pending: [],
});
export const channels = reactive({
  ...freshChannels(),
  byId(id) {
    return this.mine.find((c) => c.id === id) || this.subscribed.find((c) => c.id === id) || this.discover.find((c) => c.id === id);
  },
});

const setPending = (id, on) =>
  (channels.pending = on ? [...channels.pending, id] : channels.pending.filter((x) => x !== id));
export const isPending = (id) => channels.pending.includes(id);

/** 默认列表与「发现更多」并行加载，单段失败只影响该段。 */
export async function loadChannels() {
  if (channels.loading) return;
  channels.loading = true;
  channels.error = null;
  channels.discoverError = null;
  const [mine, disc] = await Promise.allSettled([api.allChannels(false), api.allChannels(true)]);
  if (disc.status === 'fulfilled') channels.discover = disc.value.filter(canSubscribe);
  else channels.discoverError = asError(disc.reason);
  if (mine.status === 'fulfilled') {
    channels.mine = mine.value.filter(canEdit);
    channels.subscribed = mine.value.filter(isSubscription);
  } else channels.error = asError(mine.reason);
  channels.loading = false;
  channels.loaded = true;
}

async function loadDiscover() {
  try {
    channels.discover = (await api.allChannels(true)).filter(canSubscribe);
  } catch (e) {
    channels.discoverError = asError(e);
  }
}

/** 运行状态只对屏幕内可见行轮询：逐个取最近一条运行。 */
export async function refreshRuns(ids) {
  for (const id of ids) {
    try {
      const p = await api.runs(id, null, 1);
      if (p.items[0]) channels.latestRuns[id] = p.items[0];
      else delete channels.latestRuns[id];
    } catch {
      /* 取不到时保留上一次结果 */
    }
  }
}

/** 用服务端返回的频道对象替换本地项；不存在时按 owner 落到对应段。 */
export function replaceChannel(c) {
  const target = canEdit(c) ? 'mine' : isSubscription(c) ? 'subscribed' : canSubscribe(c) ? 'discover' : null;
  for (const key of ['mine', 'subscribed', 'discover']) {
    const i = channels[key].findIndex((x) => x.id === c.id);
    if (i < 0) continue;
    if (key === target) {
      channels[key][i] = c; // 同一段内原位替换，开关等操作不打乱顺序
      return syncFeedChannel(c);
    }
    channels[key].splice(i, 1);
  }
  if (target) channels[target] = [c, ...channels[target]];
  syncFeedChannel(c);
}

function syncFeedChannel(c) {
  if (feed.channelsById[c.id] || canEdit(c) || isSubscription(c)) feed.channelsById[c.id] = c;
}

function removeLocally(id) {
  const drop = (list) => list.filter((x) => x.id !== id);
  channels.mine = drop(channels.mine);
  channels.subscribed = drop(channels.subscribed);
  channels.discover = drop(channels.discover);
  delete channels.latestRuns[id];
}

/** 乐观切换：先本地翻转，失败回滚并返回原因。 */
export async function setEnabled(id, enabled) {
  const c = channels.mine.find((x) => x.id === id);
  if (!c || isPending(id)) return null;
  const original = c.enabled;
  c.enabled = enabled;
  setPending(id, true);
  try {
    replaceChannel(await api.patchChannel(id, { enabled }));
    return null;
  } catch (e) {
    const cur = channels.mine.find((x) => x.id === id);
    if (cur) cur.enabled = original;
    return asError(e);
  } finally {
    setPending(id, false);
  }
}

export async function createChannel(fields, colorIndex) {
  const created = await api.createChannel(fields);
  setColor(created.id, colorIndex);
  replaceChannel(created);
  return created;
}

export async function saveChannel(id, changes) {
  const updated = await api.patchChannel(id, changes);
  replaceChannel(updated);
  return updated;
}

/** 删除：成功或 404（已删除）都移除本地项；409 等其他错误抛出，不做本地删除。 */
export async function deleteChannel(id) {
  try {
    await api.deleteChannel(id);
  } catch (e) {
    if (asError(e).kind !== 'notFound') throw asError(e);
  }
  removeLocally(id);
  forgetChannel(id);
}

/** 订阅：200 / 201 都按成功；再读一次单频道拿完整 DTO。 */
export async function subscribe(id, colorIndex) {
  if (isPending(id)) return null;
  setPending(id, true);
  channels.discoverError = null;
  try {
    await api.subscribe(id, paletteValue(colorIndex));
    const c = await api.channel(id);
    replaceChannel(c);
    loadFeed({ refresh: true });
    return c;
  } catch (e) {
    channels.discoverError = asError(e);
    return null;
  } finally {
    setPending(id, false);
  }
}

export async function updateSubscriptionColor(id, colorIndex) {
  const c = await api.updateSubscriptionColor(id, paletteValue(colorIndex));
  replaceChannel(c);
  return c;
}

/** 取消订阅：频道与历史日报在服务端保留，但对本人立即不可见。404 按已取消处理。 */
export async function unsubscribe(id) {
  try {
    await api.unsubscribe(id);
  } catch (e) {
    if (asError(e).kind !== 'notFound') throw asError(e);
  }
  removeLocally(id);
  forgetChannel(id);
  loadDiscover();
}

/** fork 成我的频道；服务端同时取消原订阅。 */
export async function forkChannel(id) {
  const created = await api.fork(id);
  removeLocally(id);
  forgetChannel(id);
  replaceChannel(created);
  return created;
}
