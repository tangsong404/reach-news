// /api/v1 客户端。CapacitorHttp 在手机上接管 fetch（走原生网络栈，不受 CORS 限制）。
// 所有响应在这里一次性归一化成领域对象，视图与 store 只见归一化后的形状。
import {
  ApiError, normalizeError, pageQuery, sanitizedCursor, sinceString, schedulePayload,
  toChannel, toBrief, toRun, toMaterial, toAskTurn, toCursor, toSession, MAX_LIMIT,
} from './model.js';

const TIMEOUT_MS = 20000;

/**
 * @param {() => string} baseURL   当前服务地址（origin）
 * @param {() => string|null} token 当前会话凭证
 * @param {() => void} onUnauthorized 任何请求 401：清凭证回登录页，不自动重试
 */
export function createApi({ baseURL, token, onUnauthorized }) {
  async function request(method, path, { query, body, auth = true, base } = {}) {
    // 浏览器开发模式走 Vite 代理 / 模拟数据（同源），手机上用填写的地址
    const devBrowser = import.meta.env?.DEV && !globalThis.Capacitor?.isNativePlatform();
    const origin = devBrowser ? '' : (base ?? baseURL());
    const qs = query ? '?' + new URLSearchParams(query) : '';
    const headers = { Accept: 'application/json' };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (auth) {
      const tk = token();
      if (!tk) throw new ApiError('unauthorized');
      headers.Authorization = `Bearer ${tk}`;
    }
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
    let res;
    try {
      res = await fetch(origin + path + qs, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: ctrl.signal,
      });
    } catch (e) {
      // 断网、超时、连不上主机都按「当前无网络」处理
      throw new ApiError('offline', String(e?.message || ''));
    } finally {
      clearTimeout(timer);
    }
    let data = null;
    const text = await res.text();
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        if (res.ok) throw new ApiError('decoding');
      }
    }
    if (!res.ok) {
      const err = normalizeError(res.status, data);
      if (err.kind === 'unauthorized' && auth) onUnauthorized?.();
      throw err;
    }
    return data;
  }

  const page = (data, map) => ({
    items: (data?.items || []).map(map).filter(Boolean),
    nextCursor: sanitizedCursor(data?.nextCursor),
  });

  /** 按游标翻完全部页；上限防止游标异常时死循环。 */
  async function all(fetchPage) {
    let cursor = null;
    const out = [];
    for (let i = 0; i < 20; i++) {
      const p = await fetchPage(cursor);
      out.push(...p.items);
      cursor = p.nextCursor;
      if (!cursor) break;
    }
    return out;
  }

  const api = {
    health: (base) => request('GET', '/health', { auth: false, base }),
    login: async (base, username, password) =>
      toSession(await request('POST', '/api/v1/login', { auth: false, base, body: { username, password } })),
    logout: () => request('POST', '/api/v1/logout'),
    settings: () => request('GET', '/api/v1/settings'),

    channels: async ({ cursor, limit = MAX_LIMIT, discover = false } = {}) => {
      const query = pageQuery(cursor, limit);
      if (discover) query.discover = '1';
      return page(await request('GET', '/api/v1/channels', { query }), toChannel);
    },
    allChannels: (discover = false) => all((cursor) => api.channels({ cursor, discover })),
    channel: async (id) => toChannel(await request('GET', `/api/v1/channels/${id}`)),
    createChannel: async ({ name, prompt, tone, schedule, connectorIds }) =>
      toChannel(
        await request('POST', '/api/v1/channels', {
          body: { name, prompt, tone, schedule: schedulePayload(schedule), connectorIds },
        }),
      ),
    /** changes 已是提交形状（只含改动字段）。 */
    patchChannel: async (id, changes) => toChannel(await request('PATCH', `/api/v1/channels/${id}`, { body: changes })),
    deleteChannel: (id) => request('DELETE', `/api/v1/channels/${id}`),
    connectors: async () =>
      (await request('GET', '/api/v1/connectors'))?.items?.map((c) => ({ id: c.id, name: c.name, kind: c.kind || '' })) || [],

    subscribe: (id, color) => request('POST', `/api/v1/channels/${id}/subscribe`, { body: { color } }),
    updateSubscriptionColor: async (id, color) =>
      toChannel(await request('PATCH', `/api/v1/channels/${id}/subscribe`, { body: { color } })),
    unsubscribe: (id) => request('DELETE', `/api/v1/channels/${id}/subscribe`),
    fork: async (id) => toChannel(await request('POST', `/api/v1/channels/${id}/fork`, { body: {} })),

    allBriefs: async (cursor, limit) =>
      page(await request('GET', '/api/v1/briefs', { query: pageQuery(cursor, limit) }), toBrief),
    brief: async (id) => toBrief(await request('GET', `/api/v1/briefs/${id}`)),
    material: async (briefId, materialId) => {
      const m = toMaterial(await request('GET', `/api/v1/briefs/${briefId}/items/${materialId}`));
      if (!m) throw new ApiError('decoding');
      return m;
    },
    runs: async (channelId, cursor, limit) =>
      page(await request('GET', `/api/v1/channels/${channelId}/runs`, { query: pageQuery(cursor, limit) }), toRun),

    askHistory: async (briefId, cursor) =>
      page(await request('GET', `/api/v1/briefs/${briefId}/ask`, { query: pageQuery(cursor) }), toAskTurn),
    ask: async (briefId, message) => {
      const d = await request('POST', `/api/v1/briefs/${briefId}/ask`, { body: { message } });
      return {
        turn: { id: `answer-${Date.now()}`, role: 'assistant', message: d?.answer || '', createdAt: new Date() },
        citedItemIds: d?.citedItemIds || [],
      };
    },

    cursor: async (since) => toCursor(await request('GET', '/api/v1/cursor', { query: { since: sinceString(since) } })),
  };
  return api;
}
