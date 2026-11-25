// 领域层：与服务端边界的归一化、分页、轮询基线、时间表、筛选与频道判定。
// 纯函数，不依赖 Vue / Capacitor，`node --test` 可直接覆盖。
// 规则来源：docs/client-contract.md 与 docs/comet/specs/ios-client/spec.md，与 iOS 端保持一致。

// ---------------- 时间 ----------------

/** 服务端时间一律 UTC ISO 8601（可带毫秒）；解析失败返回 null。 */
export function parseDate(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const ms = Date.parse(raw);
  return Number.isNaN(ms) ? null : new Date(ms);
}

const EPOCH = new Date(0);

// ---------------- 宽松布尔 ----------------
// `/cursor` 的 enabled 曾是整数 1/0，其余端点是 JSON 布尔。

export function flexBool(v) {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v !== 0;
  if (typeof v === 'string') return ['1', 'true', 'yes'].includes(v.toLowerCase());
  return false;
}

// ---------------- 错误 ----------------
// 归一化错误种类；未知 code 保留原文，不丢原因。
// not_found 的两义不参与判断：资源是否存在由调用点按路径决定。

const CODE_TO_KIND = {
  unauthorized: 'unauthorized',
  too_many_attempts: 'tooManyAttempts',
  invalid_connector: 'invalidConnector',
  not_found: 'notFound',
  invalid_input: 'invalidInput',
  busy: 'busy',
  bad_request: 'badRequest',
  internal_error: 'server',
  presets_removed: 'removed',
  not_published: 'notPublished',
  own_channel: 'ownChannel',
  subscriber_read_only: 'subscriberReadOnly',
};

export class ApiError extends Error {
  constructor(kind, detail = '', code = null) {
    super(detail || kind);
    this.kind = kind;
    this.detail = detail;
    this.code = code;
  }
}

/** 把服务端 `{ error: { code, message } }` 与 HTTP 状态归一化成 ApiError。 */
export function normalizeError(status, body) {
  const err = body && typeof body === 'object' ? body.error : null;
  if (err && typeof err.code === 'string') {
    const kind = CODE_TO_KIND[err.code] || 'server';
    return new ApiError(kind, err.message || '', err.code);
  }
  if (status === 401) return new ApiError('unauthorized');
  if (status === 404) return new ApiError('notFound');
  return new ApiError('server', `HTTP ${status}`);
}

/** 错误种类 → 中文文案（同时是 i18n 键）。视图不散落 switch。 */
export const ERROR_TEXT = {
  offline: '当前无网络',
  transport: '无法连接服务',
  unauthorized: '凭证无效或已失效',
  tooManyAttempts: '尝试次数过多，请稍后再试',
  invalidConnector: '连接器不可用',
  notFound: '请求的内容不存在',
  invalidInput: '请求参数不被接受',
  busy: '频道正在运行，暂时无法保存',
  badRequest: '服务端拒绝了这次请求',
  server: '服务端出错了',
  decoding: '服务端返回了无法解析的内容',
  configuration: '服务地址无效',
  removed: '旧接口已停用',
  notPublished: '该频道尚未公开',
  ownChannel: '这是你自己的频道',
  subscriberReadOnly: '订阅频道只读，可 fork 后修改',
};

// ---------------- 枚举 ----------------

export const RUNNING_STATES = ['queued', 'collecting', 'writing'];
const RUN_STATES = [...RUNNING_STATES, 'published', 'failed', 'missed', 'cancelled'];

/** missedReason：已知值归一化，未知值保留原文。 */
export function parseMissedReason(raw) {
  if (!raw) return null;
  const known = { 'no-material': 'noMaterial', 'queue-timeout': 'queueTimeout', 'resume-writing': 'resumeWriting' };
  return known[raw] ? { kind: known[raw], raw } : { kind: 'unknown', raw };
}

// ---------------- 分页 ----------------
// 实测：limit 缺失/0/非数字 → 20，负数 → 1，>100 → 100。客户端从不传负值或 0。

export const DEFAULT_LIMIT = 20;
export const MAX_LIMIT = 100;

export function sanitizedLimit(n) {
  return Number.isInteger(n) && n > 0 ? Math.min(n, MAX_LIMIT) : DEFAULT_LIMIT;
}

/** 服务端游标：负值与非整数一律丢弃（cursor=-5 会返回非空 nextCursor，是服务端缺陷）。 */
export function sanitizedCursor(raw) {
  if (raw === null || raw === undefined) return null;
  const s = String(raw).trim();
  if (!/^\d+$/.test(s)) return null;
  return String(Number(s));
}

export function pageQuery(cursor, limit) {
  const q = { limit: String(sanitizedLimit(limit)) };
  const c = sanitizedCursor(cursor);
  if (c && c !== '0') q.cursor = c;
  return q;
}

// ---------------- 轮询基线（ADR 0003） ----------------

/** 推进 lastSeenAt：取响应中最大的 createdAt，不用本地时间。 */
export function nextBaseline(baseline, cursorPayload) {
  const times = cursorPayload.briefs.map((b) => b.createdAt?.getTime()).filter((t) => Number.isFinite(t));
  if (!times.length) return baseline;
  const newest = new Date(Math.max(...times));
  if (!baseline) return newest;
  return newest > baseline ? newest : baseline;
}

/** 必须总是带 since；无基线时回落 1970。 */
export function sinceString(baseline) {
  return (baseline || EPOCH).toISOString();
}

// ---------------- 采集时间表 ----------------

export const WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
export const MAX_TIMES_PER_DAY = 5;

export function isValidTime(v) {
  const m = /^(\d{2}):(\d{2})$/.exec(v || '');
  return !!m && +m[1] <= 23 && +m[2] <= 59;
}

const normTimes = (times) => [...new Set((times || []).filter(isValidTime))].sort();

/** `{ mon: ["08:00"], … }` → 每个星期都有键的规范形状。 */
export function normalizeSchedule(raw) {
  const out = {};
  for (const d of WEEKDAYS) out[d] = normTimes(raw && Array.isArray(raw[d]) ? raw[d] : []);
  return out;
}

/** 提交给服务端：省略空星期。 */
export function schedulePayload(schedule) {
  const out = {};
  for (const d of WEEKDAYS) if (schedule[d]?.length) out[d] = [...schedule[d]];
  return out;
}

export const scheduleEquals = (a, b) => WEEKDAYS.every((d) => (a[d] || []).join() === (b[d] || []).join());

export function addTime(schedule, day, time) {
  const cur = schedule[day] || [];
  if (!isValidTime(time) || cur.includes(time) || cur.length >= MAX_TIMES_PER_DAY) return schedule;
  return { ...schedule, [day]: normTimes([...cur, time]) };
}

export function removeTime(schedule, day, time) {
  return { ...schedule, [day]: (schedule[day] || []).filter((t) => t !== time) };
}

/** 星期开关：已有时刻则清空，否则用当前常用时刻（或 08:00）。 */
export function toggleDay(schedule, day) {
  if (schedule[day]?.length) return { ...schedule, [day]: [] };
  const all = normTimes(WEEKDAYS.flatMap((d) => schedule[d] || []));
  return { ...schedule, [day]: [all[0] || '08:00'] };
}

/**
 * 人读短语的结构：按「同一组时刻」把星期归组。
 * 返回 [{ days: ['mon','wed'], times: ['08:00'] }]，由视图层按语言拼成「周一、三 08:00」「每天 07:30」。
 */
export function scheduleGroups(schedule) {
  const groups = [];
  for (const d of WEEKDAYS) {
    const times = schedule[d] || [];
    if (!times.length) continue;
    const key = times.join(',');
    const g = groups.find((x) => x.key === key);
    if (g) g.days.push(d);
    else groups.push({ key, days: [d], times });
  }
  return groups.map(({ days, times }) => ({ days, times }));
}

// ---------------- 日报正文 ----------------

/** segment → { type:'text', text } | { type:'link', text, url, itemId }；url 非法降级为纯文字，未知 type 按文字。 */
export function normalizeSegment(s) {
  const text = typeof s?.text === 'string' ? s.text : '';
  if (!text) return null;
  if ((s.type || 'text') === 'link' && typeof s.url === 'string' && /^[a-z][a-z0-9+.-]*:/i.test(s.url)) {
    try {
      new URL(s.url);
      return { type: 'link', text, url: s.url, itemId: s.itemId || null };
    } catch {
      /* 落到纯文字 */
    }
  }
  return { type: 'text', text };
}

/** null、字段缺失、空数组、全空白都归一化为 null，走同一条「无可读正文」路径。 */
export function normalizeBody(raw) {
  if (!raw || !Array.isArray(raw.paragraphs)) return null;
  const paragraphs = raw.paragraphs
    .map((p) => ({ segments: (Array.isArray(p?.segments) ? p.segments : []).map(normalizeSegment).filter(Boolean) }))
    .filter((p) => p.segments.length);
  const readable = paragraphs.some((p) => p.segments.some((s) => s.text.trim()));
  return readable ? { paragraphs } : null;
}

/** 片段拼回 Markdown：text 原样（本身是 Markdown），link 写成 [文字](url)；段落用空行分隔。 */
export function bodyMarkdown(body) {
  if (!body) return '';
  return body.paragraphs
    .map((p) =>
      p.segments
        .map((s) => (s.type === 'link' ? `[${s.text.replace(/]/g, '\\]')}](${s.url.replace(/\)/g, '%29')})` : s.text))
        .join(''),
    )
    .join('\n\n');
}

export function displaySummary(summary) {
  const s = typeof summary === 'string' ? summary.trim() : '';
  return s || null;
}

// ---------------- DTO → 领域对象 ----------------

export function toChannel(d) {
  return {
    id: d.id,
    name: d.name || '',
    prompt: d.prompt || '',
    tone: d.tone || '',
    schedule: normalizeSchedule(d.schedule),
    enabled: flexBool(d.enabled),
    connectorIds: Array.isArray(d.connectorIds) ? d.connectorIds : [],
    connectors: (d.connectors || []).map((c) => ({
      id: c.id,
      name: c.name ?? null,
      kind: c.kind ?? null,
      removed: !!c.removed,
    })),
    lastBriefAt: parseDate(d.lastBriefAt),
    // 服务端已无 preset；未知值降级为普通频道
    kind: d.kind === 'follow' ? 'follow' : 'channel',
    published: flexBool(d.published),
    owner: d.owner === 'subscriber' ? 'subscriber' : 'creator',
    subscribed: flexBool(d.subscribed),
    subscriptionColor: d.subscriptionColor ?? null,
    subscriptionId: d.subscriptionId ?? null,
    createdAt: parseDate(d.createdAt) || EPOCH,
    updatedAt: parseDate(d.updatedAt) || EPOCH,
  };
}

// 可写性判定的唯一正确写法：一律看 owner，不看 kind。
export const canEdit = (c) => c.owner === 'creator';
export const canSubscribe = (c) => c.published && c.owner !== 'creator' && !c.subscribed;
export const canUnsubscribe = (c) => c.subscribed;
export const isSubscription = (c) => c.owner === 'subscriber' && c.subscribed;
/** 订阅频道不提示：连接器由创建者决定。 */
export const warnsNoConnectors = (c) => c.enabled && !c.connectorIds.length && c.owner === 'creator';

export function toBrief(d) {
  return {
    id: d.id,
    channelId: d.channelId,
    title: d.title || '',
    summary: displaySummary(d.summary),
    body: normalizeBody(d.body),
    // sections 只解析保留，不进入任何读者界面
    sections: (d.sections || []).map((s) => ({
      title: s.title,
      entries: (s.items || []).map((e) => ({ title: e.title, summary: e.summary || '', materialIds: e.itemIds || [] })),
    })),
    // memorySummary 不在任何界面展示
    memorySummary: d.memorySummary || '',
    createdAt: parseDate(d.createdAt) || EPOCH,
    channelName: d.channelName || null,
    channelKind: d.channelKind ? (d.channelKind === 'follow' ? 'follow' : 'channel') : null,
  };
}

export function toRun(d) {
  return {
    id: d.id,
    channelId: d.channelId || null,
    state: RUN_STATES.includes(d.state) ? d.state : 'cancelled',
    trigger: d.trigger || 'unknown',
    startedAt: parseDate(d.startedAt),
    finishedAt: parseDate(d.finishedAt),
    missedReason: parseMissedReason(d.missedReason),
    createdAt: parseDate(d.createdAt) || EPOCH,
  };
}

/** 素材：content 只解析不展示；url 不合法时丢弃。 */
export function toMaterial(d) {
  let host;
  try {
    host = new URL(d.url).host.replace(/^www\./, '');
  } catch {
    return null;
  }
  return {
    id: d.id,
    title: d.title || '',
    url: d.url,
    host,
    publishedAt: parseDate(d.publishedAt),
    source: d.metadata?.source || null,
  };
}

/** 追问历史兼容 snake_case。 */
export function toAskTurn(d) {
  return {
    id: d.id,
    role: d.role === 'user' ? 'user' : 'assistant',
    message: d.message || '',
    createdAt: parseDate(d.createdAt ?? d.created_at) || EPOCH,
  };
}

/** `/cursor` 兼容 snake_case 与整数 enabled。 */
export function toCursor(d) {
  return {
    briefs: (d?.briefs || []).map((b) => ({
      id: b.id,
      channelId: b.channelId ?? b.channel_id,
      title: b.title,
      createdAt: parseDate(b.createdAt ?? b.created_at) || EPOCH,
    })),
    channels: (d?.channels || []).map((c) => ({
      id: c.id,
      name: c.name,
      enabled: flexBool(c.enabled),
      updatedAt: parseDate(c.updatedAt ?? c.updated_at) || EPOCH,
    })),
  };
}

export function toSession(d) {
  const expiresAt = parseDate(d?.expiresAt);
  if (!d?.token || !expiresAt) throw new ApiError('decoding');
  return { token: d.token, expiresAt, userName: d.user?.name || '' };
}

// ---------------- 频道编辑草稿：只提交改动字段 ----------------

export function draftFrom(channel) {
  return {
    name: channel.name,
    prompt: channel.prompt,
    tone: channel.tone,
    schedule: { ...channel.schedule },
    enabled: channel.enabled,
    connectorIds: [...channel.connectorIds],
  };
}

export function draftChanges(draft, channel) {
  const out = {};
  if (draft.name !== channel.name) out.name = draft.name;
  if (draft.prompt !== channel.prompt) out.prompt = draft.prompt;
  if (draft.tone !== channel.tone) out.tone = draft.tone;
  if (!scheduleEquals(draft.schedule, channel.schedule)) out.schedule = schedulePayload(draft.schedule);
  if (draft.enabled !== channel.enabled) out.enabled = draft.enabled;
  const a = [...draft.connectorIds].sort().join();
  const b = [...channel.connectorIds].sort().join();
  if (a !== b) out.connectorIds = [...draft.connectorIds];
  return out;
}

// ---------------- 日报流 ----------------

/** 按 ID 去重并按 createdAt 倒序。 */
export function mergeBriefs(existing, incoming) {
  if (!incoming.length) return existing;
  const seen = new Set(existing.map((b) => b.id));
  const merged = [...existing];
  for (const b of incoming) if (!seen.has(b.id)) (seen.add(b.id), merged.push(b));
  return merged.sort((x, y) => y.createdAt - x.createdAt);
}

export function searchBriefs(briefs, query) {
  const term = (query || '').trim().toLowerCase();
  if (!term) return briefs;
  return briefs.filter((b) => b.title.toLowerCase().includes(term));
}

export function coversLowerBound(briefs, bound) {
  if (!bound || !briefs.length) return true;
  return Math.min(...briefs.map((b) => b.createdAt.getTime())) <= bound.getTime();
}

// ---------------- 频道标识色 ----------------
// 12 色色板；订阅色复用它：提交色值字符串，读取时比对，未命中按「未设置」回退。

export const PALETTE = [
  ['#2F6F9E', 'azure', '天蓝'],
  ['#2E7D5B', 'emerald', '翠绿'],
  ['#B05A2A', 'ember', '赭橙'],
  ['#8C3B63', 'magenta', '品红'],
  ['#6A4FA0', 'violet', '紫罗兰'],
  ['#B08615', 'amber', '琥珀'],
  ['#1F7A76', 'teal', '青绿'],
  ['#9C2F2F', 'brick', '砖红'],
  ['#4A5D23', 'olive', '橄榄'],
  ['#2E4E8F', 'indigo', '靛蓝'],
  ['#7A5C3E', 'walnut', '胡桃'],
  ['#4A4A55', 'graphite', '石墨'],
].map(([hex, key, zh]) => ({ hex, key, zh }));

export const paletteValue = (i) => PALETTE[Math.max(0, Math.min(i, PALETTE.length - 1))].hex;

export function paletteIndex(color) {
  const c = typeof color === 'string' ? color.trim().toLowerCase() : '';
  if (!c) return null;
  const i = PALETTE.findIndex((p) => p.hex.toLowerCase() === c);
  return i >= 0 ? i : null;
}

/** 与 iOS 相同的稳定哈希：acc = acc*31 + code（UInt32 溢出）。 */
export function fallbackIndex(channelId) {
  let acc = 0;
  for (const ch of String(channelId)) acc = (Math.imul(acc, 31) + ch.codePointAt(0)) >>> 0;
  return acc % PALETTE.length;
}

export function leastUsedIndex(used) {
  const counts = PALETTE.map(() => 0);
  for (const i of used) if (i >= 0 && i < counts.length) counts[i]++;
  return counts.indexOf(Math.min(...counts));
}

// ---------------- 地址 ----------------

export const DEFAULT_HOST = 'https://reachapi.niuma.art';

/** 补齐 scheme、去尾斜杠；只接受 http(s)。 */
export function parseBaseURL(raw) {
  const t = (raw || '').trim();
  if (!t) return null;
  const withScheme = t.includes('://') ? t : `https://${t}`;
  try {
    const u = new URL(withScheme);
    if (!['http:', 'https:'].includes(u.protocol) || !u.host) return null;
    return u.origin;
  } catch {
    return null;
  }
}
