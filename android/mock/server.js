// 开发用模拟服务：`npm run mock` 时用仓库根目录 Fixtures/*.json 应答 /api/v1，不打真实网络。
// 只在 Vite 开发服务器里生效，不进入打包产物。
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const fx = (name) => JSON.parse(readFileSync(fileURLToPath(new URL(`../../Fixtures/${name}.json`, import.meta.url)), 'utf8'));

export function mockApi() {
  const channels = fx('channels').items;
  const briefs = fx('briefs').items;
  const materials = fx('materials').items;
  const ask = fx('ask').items.map((x) => ({ ...x }));
  const runs = fx('runs').items;
  // 让样例日报落在「今天 / 昨天」，便于看日期分组
  const shift = Date.now() - Date.parse(briefs[0].createdAt) - 3600e3;
  for (const b of briefs) b.createdAt = new Date(Date.parse(b.createdAt) + shift).toISOString();
  const connectors = [
    { id: 'cnn_homepage', name: 'HN 首页', kind: 'hn' },
    { id: 'cnn_github_trending', name: 'GitHub Trending', kind: 'github' },
  ];
  const named = (c) => ({ ...c, connectors: (c.connectorIds || []).map((id) => connectors.find((x) => x.id === id) || { id, name: null }) });

  const routes = [
    ['GET', /^\/health$/, () => ({ ok: true })],
    ['POST', /^\/api\/v1\/login$/, () => ({ token: 'mock', expiresAt: new Date(Date.now() + 7 * 864e5).toISOString(), user: { id: 'u1', name: 'demo' } })],
    ['POST', /^\/api\/v1\/logout$/, () => ({ ok: true })],
    ['GET', /^\/api\/v1\/settings$/, () => ({ timeZone: 'Asia/Shanghai' })],
    ['GET', /^\/api\/v1\/connectors$/, () => ({ items: connectors, nextCursor: null })],
    ['GET', /^\/api\/v1\/cursor$/, () => fx('cursor')],
    ['GET', /^\/api\/v1\/briefs$/, () => ({ items: briefs, nextCursor: null })],
    ['GET', /^\/api\/v1\/briefs\/([^/]+)$/, (m) => briefs.find((b) => b.id === m[1]) || [404, { error: { code: 'not_found', message: 'Brief not found' } }]],
    ['GET', /^\/api\/v1\/briefs\/[^/]+\/items\/([^/]+)$/, (m) => materials.find((x) => x.id === m[1]) || [404, { error: { code: 'not_found', message: '' } }]],
    ['GET', /^\/api\/v1\/briefs\/[^/]+\/ask$/, () => ({ items: ask, nextCursor: null })],
    ['POST', /^\/api\/v1\/briefs\/[^/]+\/ask$/, (m, body) => ({ message: body.message, answer: `已基于归档摘要记录问题：${body.message}`, citedItemIds: [], deterministic: true })],
    ['GET', /^\/api\/v1\/channels$/, (m, b, q) =>
      ({ items: channels.filter((c) => (q.get('discover') ? c.published && c.owner !== 'creator' && !c.subscribed : c.owner === 'creator' || c.subscribed)).map(named), nextCursor: null })],
    ['POST', /^\/api\/v1\/channels$/, (m, body) => {
      const c = { ...body, id: 'chn_' + Date.now(), enabled: true, kind: 'channel', owner: 'creator', published: false, subscribed: false, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
      channels.unshift(c);
      return [201, named(c)];
    }],
    ['GET', /^\/api\/v1\/channels\/([^/]+)$/, (m) => named(channels.find((c) => c.id === m[1]))],
    ['PATCH', /^\/api\/v1\/channels\/([^/]+)$/, (m, body) => {
      const c = channels.find((x) => x.id === m[1]);
      if (body.name === 'busy') return [409, { error: { code: 'busy', message: 'Channel has a run in progress' } }];
      Object.assign(c, body);
      return named(c);
    }],
    ['DELETE', /^\/api\/v1\/channels\/([^/]+)$/, (m) => (channels.splice(channels.findIndex((c) => c.id === m[1]), 1), { id: m[1], deleted: true })],
    ['GET', /^\/api\/v1\/channels\/[^/]+\/runs$/, (m, b, q, path) => ({ items: [runs[path.length % runs.length]], nextCursor: null })],
    ['POST', /^\/api\/v1\/channels\/([^/]+)\/subscribe$/, (m, body) => {
      const c = channels.find((x) => x.id === m[1]);
      Object.assign(c, { subscribed: true, subscriptionColor: body.color, subscriptionId: 'sub_' + c.id });
      return [201, { id: c.subscriptionId, channelId: c.id, color: body.color, subscribed: true }];
    }],
    ['PATCH', /^\/api\/v1\/channels\/([^/]+)\/subscribe$/, (m, body) => named(Object.assign(channels.find((x) => x.id === m[1]), { subscriptionColor: body.color }))],
    ['DELETE', /^\/api\/v1\/channels\/([^/]+)\/subscribe$/, (m) => (Object.assign(channels.find((x) => x.id === m[1]), { subscribed: false, subscriptionColor: null }), { channelId: m[1], subscribed: false })],
    ['POST', /^\/api\/v1\/channels\/([^/]+)\/fork$/, (m) => {
      const src = channels.find((x) => x.id === m[1]);
      Object.assign(src, { subscribed: false, subscriptionColor: null });
      const c = { ...src, id: 'chn_fork_' + Date.now(), owner: 'creator', published: false, subscribed: false };
      channels.unshift(c);
      return [201, named(c)];
    }],
  ];

  return {
    name: 'reach-news-mock',
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        const url = new URL(req.url, 'http://x');
        const route = routes.find(([method, re]) => method === req.method && re.test(url.pathname));
        if (!route) return next();
        let raw = '';
        for await (const chunk of req) raw += chunk;
        const out = route[2](url.pathname.match(route[1]), raw ? JSON.parse(raw) : {}, url.searchParams, url.pathname);
        const [status, body] = Array.isArray(out) ? out : [200, out];
        res.statusCode = status;
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify(body));
      });
    },
  };
}
