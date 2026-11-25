// 领域层单元测试：样本取自仓库根目录 Fixtures/，覆盖 docs/client-contract.md 的客户端约束。
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as M from '../src/lib/model.js';
import * as T from '../src/lib/time.js';

const fx = (name) => JSON.parse(readFileSync(new URL(`../../Fixtures/${name}.json`, import.meta.url), 'utf8'));

test('/cursor：snake_case 与整数 enabled 归一化', () => {
  const c = M.toCursor(fx('cursor'));
  assert.equal(c.briefs[0].channelId, 'chn_c7e81f00-3a2f-4f7b-9a1e-0d5c2b7e4a11');
  assert.ok(c.briefs[0].createdAt instanceof Date);
  assert.deepEqual(c.channels.map((x) => x.enabled), [true, false]);
  // 同时兼容 camelCase + 布尔
  const camel = M.toCursor({ briefs: [{ id: 'b', channelId: 'c', title: 't', createdAt: '2026-01-01T00:00:00.000Z' }], channels: [{ id: 'c', name: 'n', enabled: true, updatedAt: '2026-01-01T00:00:00Z' }] });
  assert.equal(camel.briefs[0].channelId, 'c');
  assert.equal(camel.channels[0].enabled, true);
});

test('时间戳带毫秒与不带毫秒都能解析', () => {
  assert.equal(M.parseDate('2026-11-20T02:01:50.774Z').toISOString(), '2026-11-20T02:01:50.774Z');
  assert.equal(M.parseDate('2026-11-20T02:01:50Z').toISOString(), '2026-11-20T02:01:50.000Z');
  assert.equal(M.parseDate(''), null);
  assert.equal(M.parseDate(null), null);
});

test('missedReason 与 error.code：未知值保留原文', () => {
  assert.deepEqual(M.parseMissedReason('no-material'), { kind: 'noMaterial', raw: 'no-material' });
  assert.deepEqual(M.parseMissedReason('overall-timeout'), { kind: 'unknown', raw: 'overall-timeout' });
  assert.equal(M.parseMissedReason(null), null);
  const e = M.normalizeError(500, { error: { code: 'brand_new', message: 'why' } });
  assert.equal(e.kind, 'server');
  assert.equal(e.code, 'brand_new');
  assert.equal(e.detail, 'why');
});

test('订阅相关错误码归一化，presets_removed 与 not_found 区分', () => {
  const kind = (code, status = 400) => M.normalizeError(status, { error: { code, message: '' } }).kind;
  assert.equal(kind('not_published', 403), 'notPublished');
  assert.equal(kind('own_channel', 409), 'ownChannel');
  assert.equal(kind('subscriber_read_only', 403), 'subscriberReadOnly');
  assert.equal(kind('presets_removed', 404), 'removed');
  assert.equal(kind('not_found', 404), 'notFound');
  assert.equal(kind('busy', 409), 'busy');
  assert.equal(kind('too_many_attempts', 429), 'tooManyAttempts');
  // 没有错误信封时按状态码
  assert.equal(M.normalizeError(401, null).kind, 'unauthorized');
  assert.equal(M.normalizeError(404, 'x').kind, 'notFound');
});

test('分页：从不传负值、0 或越界', () => {
  assert.equal(M.sanitizedLimit(0), 20);
  assert.equal(M.sanitizedLimit(-3), 20);
  assert.equal(M.sanitizedLimit(500), 100);
  assert.equal(M.sanitizedLimit(7), 7);
  assert.equal(M.sanitizedCursor('-5'), null);
  assert.equal(M.sanitizedCursor('abc'), null);
  assert.equal(M.sanitizedCursor('40'), '40');
  assert.deepEqual(M.pageQuery('-5', 20), { limit: '20' });
  assert.deepEqual(M.pageQuery('0', 20), { limit: '20' });
  assert.deepEqual(M.pageQuery('20', 1000), { limit: '100', cursor: '20' });
});

test('lastSeenAt 取响应中最大的 createdAt；空响应不推进；总是带 since', () => {
  const payload = M.toCursor(fx('cursor'));
  const base = new Date('2026-11-01T00:00:00Z');
  assert.equal(M.nextBaseline(base, payload).toISOString(), '2026-11-20T00:00:12.774Z');
  assert.equal(M.nextBaseline(null, payload).toISOString(), '2026-11-20T00:00:12.774Z');
  const later = new Date('2026-12-01T00:00:00Z');
  assert.equal(M.nextBaseline(later, payload), later);
  assert.equal(M.nextBaseline(base, { briefs: [], channels: [] }), base);
  assert.equal(M.sinceString(null), '1970-01-01T00:00:00.000Z');
});

test('频道：五个订阅字段、kind 降级、可写性三判定', () => {
  const list = fx('channels').items.map(M.toChannel);
  for (const c of list) {
    assert.equal(M.canEdit(c), c.owner === 'creator');
    assert.equal(M.canSubscribe(c), c.published && c.owner !== 'creator' && !c.subscribed);
    assert.equal(M.canUnsubscribe(c), c.subscribed);
  }
  assert.ok(list.some((c) => c.owner === 'subscriber'), 'fixture 应包含订阅项');
  assert.ok(list.some((c) => c.lastBriefAt === null), 'fixture 应包含 lastBriefAt: null');
  assert.equal(M.toChannel({ id: 'x', name: 'n', kind: 'preset' }).kind, 'channel');
  assert.equal(M.toChannel({ id: 'x', name: 'n', kind: 'follow' }).kind, 'follow');
  // 空字符串订阅色按「未设置」：不命中色板
  assert.equal(M.paletteIndex(''), null);
  assert.equal(M.paletteIndex(null), null);
  assert.equal(M.paletteIndex('#2f6f9e'), 0);
  assert.equal(M.paletteIndex('red'), null);
  // 订阅频道不提示缺连接器
  const sub = M.toChannel({ id: 's', name: 'n', enabled: true, connectorIds: [], owner: 'subscriber', subscribed: true });
  assert.equal(M.warnsNoConnectors(sub), false);
  const mine = M.toChannel({ id: 'm', name: 'n', enabled: true, connectorIds: [] });
  assert.equal(M.warnsNoConnectors(mine), true);
});

test('稳定色与 iOS 的哈希一致（acc*31 + scalar，UInt32）', () => {
  // iOS: "chn_a" → 按 UInt32 溢出累乘
  let acc = 0n;
  for (const ch of 'chn_c7e81f00-3a2f') acc = (acc * 31n + BigInt(ch.codePointAt(0))) % 2n ** 32n;
  assert.equal(M.fallbackIndex('chn_c7e81f00-3a2f'), Number(acc % 12n));
  assert.equal(M.leastUsedIndex([0, 0, 1, 2]), 3);
});

test('日报正文：有正文 / null / 字段缺失 / 空数组 / 只有空白', () => {
  const briefs = fx('briefs').items;
  const withBody = briefs.map(M.toBrief).find((b) => b.body);
  assert.ok(withBody, 'fixture 应包含带 body 的日报');
  assert.equal(M.toBrief({ ...briefs[0], body: null }).body, null);
  const { body, ...noBody } = briefs[0];
  assert.equal(M.toBrief(noBody).body, null);
  assert.equal(M.normalizeBody({ paragraphs: [] }), null);
  assert.equal(M.normalizeBody({ paragraphs: [{ segments: [{ type: 'text', text: '   \n' }] }] }), null);
});

test('正文片段：link 缺 url 降级为文字，未知 type 按文字', () => {
  assert.deepEqual(M.normalizeSegment({ type: 'link', text: 'a' }), { type: 'text', text: 'a' });
  assert.deepEqual(M.normalizeSegment({ type: 'link', text: 'a', url: 'not a url' }), { type: 'text', text: 'a' });
  assert.deepEqual(M.normalizeSegment({ type: 'image', text: 'b' }), { type: 'text', text: 'b' });
  assert.equal(M.normalizeSegment({ type: 'text', text: '' }), null);
  const link = M.normalizeSegment({ type: 'link', text: 'x', url: 'https://e.test/a', itemId: 'itm' });
  assert.deepEqual(link, { type: 'link', text: 'x', url: 'https://e.test/a', itemId: 'itm' });
});

test('正文拼回 Markdown：link 写成 [文字](url)，段落空行分隔', () => {
  const md = M.bodyMarkdown({
    paragraphs: [
      { segments: [{ type: 'text', text: '## 标题' }] },
      { segments: [{ type: 'text', text: '看 ' }, { type: 'link', text: 'a]b', url: 'https://e.test/x' }] },
    ],
  });
  assert.equal(md, '## 标题\n\n看 [a\\]b](https://e.test/x)');
});

test('summary：null、缺失、空字符串都归一化为 null；sections 照常解析', () => {
  const b = fx('briefs').items[0];
  assert.equal(M.toBrief({ ...b, summary: '' }).summary, null);
  assert.equal(M.toBrief({ ...b, summary: null }).summary, null);
  assert.equal(M.toBrief({ ...b, summary: '  ' }).summary, null);
  assert.ok(M.toBrief(b).sections.length > 1);
});

test('频道编辑只提交改动字段', () => {
  const c = M.toChannel(fx('channels').items[0]);
  const d = M.draftFrom(c);
  assert.deepEqual(M.draftChanges(d, c), {});
  d.tone = '新口吻';
  d.schedule = M.addTime(d.schedule, 'tue', '09:30');
  assert.deepEqual(Object.keys(M.draftChanges(d, c)).sort(), ['schedule', 'tone']);
  assert.deepEqual(M.draftChanges(d, c).schedule.tue, ['09:30']);
  // 连接器按集合比较，顺序无关
  const d2 = M.draftFrom(c);
  d2.connectorIds = [...c.connectorIds].reverse();
  assert.deepEqual(M.draftChanges(d2, c), {});
});

test('时间表：校验、去重排序、每天最多 5 个、短语分组', () => {
  let s = M.normalizeSchedule({ mon: ['08:00', '07:00', '08:00', '25:00'], zzz: ['01:00'] });
  assert.deepEqual(s.mon, ['07:00', '08:00']);
  assert.deepEqual(M.schedulePayload(s), { mon: ['07:00', '08:00'] });
  for (const tm of ['01:00', '02:00', '03:00', '04:00']) s = M.addTime(s, 'tue', tm);
  s = M.addTime(s, 'tue', '05:00');
  s = M.addTime(s, 'tue', '06:00');
  assert.equal(s.tue.length, 5);
  const every = M.normalizeSchedule(Object.fromEntries(M.WEEKDAYS.map((d) => [d, ['07:30']])));
  assert.deepEqual(M.scheduleGroups(every), [{ days: M.WEEKDAYS, times: ['07:30'] }]);
  const mwf = M.normalizeSchedule({ mon: ['08:00'], wed: ['08:00'], fri: ['08:00'] });
  assert.deepEqual(M.scheduleGroups(mwf), [{ days: ['mon', 'wed', 'fri'], times: ['08:00'] }]);
});

test('日报流：按 ID 去重、倒序；搜索按标题', () => {
  const a = { id: 'a', title: 'Alpha', createdAt: new Date('2026-11-01') };
  const b = { id: 'b', title: 'Beta', createdAt: new Date('2026-11-03') };
  const merged = M.mergeBriefs([a], [b, a]);
  assert.deepEqual(merged.map((x) => x.id), ['b', 'a']);
  assert.deepEqual(M.searchBriefs(merged, ' alp ').map((x) => x.id), ['a']);
  assert.ok(M.coversLowerBound(merged, new Date('2026-11-02')));
  assert.ok(!M.coversLowerBound(merged, new Date('2026-10-01')));
});

test('时区：非法回退 Asia/Shanghai；按时区分组与时刻', () => {
  assert.equal(T.resolveTimeZone('Mars/Base'), 'Asia/Shanghai');
  assert.equal(T.resolveTimeZone(''), 'Asia/Shanghai');
  assert.equal(T.setTimeZone('Asia/Tokyo'), 'Asia/Tokyo');
  const d = new Date('2026-11-19T16:30:00Z'); // 东京 11-20 01:30
  assert.equal(T.clock(d), '01:30');
  assert.equal(T.startOfDay(d).toISOString(), '2026-11-19T15:00:00.000Z');
  T.setTimeZone(null);
  assert.equal(T.clock(d), '00:30'); // 上海 11-20 00:30
  const groups = T.groupByDay([
    { id: '1', createdAt: new Date('2026-11-19T16:30:00Z') },
    { id: '2', createdAt: new Date('2026-11-19T15:00:00Z') },
    { id: '3', createdAt: new Date('2026-11-19T10:00:00Z') },
  ]);
  assert.deepEqual(groups.map((g) => g.briefs.map((b) => b.id)), [['1'], ['2', '3']]);
});

test('筛选：本周区间相对现在构造，不写死日期', () => {
  const now = new Date();
  const [lo, hi] = T.resolveRange({ time: 'week' }, now);
  assert.ok(lo <= now && hi.getTime() === now.getTime());
  const mid = new Date((lo.getTime() + now.getTime()) / 2);
  const before = new Date(lo.getTime() - 864e5);
  const f = { time: 'week', channelIds: [] };
  assert.ok(T.matchesFilter({ channelId: 'c', createdAt: mid }, f, now));
  assert.ok(!T.matchesFilter({ channelId: 'c', createdAt: before }, f, now));
  assert.ok(!T.matchesFilter({ channelId: 'c', createdAt: mid }, { ...f, channelIds: ['x'] }, now));
  // 自定义范围按整天解释，起止颠倒也成立
  const start = T.fromDateInput('2026-11-10');
  const end = T.fromDateInput('2026-11-01');
  const [a, b] = T.resolveRange({ time: 'custom', start, end });
  assert.equal(a.toISOString(), '2026-10-31T16:00:00.000Z');
  assert.equal(b.toISOString(), '2026-11-10T15:59:59.999Z');
});

test('Base URL：补齐 scheme、只接受 http(s)', () => {
  assert.equal(M.parseBaseURL('reachapi.niuma.art'), 'https://reachapi.niuma.art');
  assert.equal(M.parseBaseURL(' http://localhost:8787/ '), 'http://localhost:8787');
  assert.equal(M.parseBaseURL('ftp://x'), null);
  assert.equal(M.parseBaseURL(''), null);
});
