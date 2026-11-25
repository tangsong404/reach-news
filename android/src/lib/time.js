// 时刻展示与日期分组，按服务端 /settings 返回的时区解释（缺失或非法回退 Asia/Shanghai）。
// 纯函数，只用 Intl；时区是运行时值，setTimeZone 后所有展示随之变化。

export const FALLBACK_TZ = 'Asia/Shanghai';
let tz = FALLBACK_TZ;

export function isValidTimeZone(name) {
  if (!name || typeof name !== 'string') return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: name.trim() });
    return true;
  } catch {
    return false;
  }
}

export const resolveTimeZone = (raw) => (isValidTimeZone(raw) ? raw.trim() : FALLBACK_TZ);
export const setTimeZone = (raw) => (tz = resolveTimeZone(raw));
export const timeZone = () => tz;

const fmtCache = new Map();
function partsOf(date, zone = tz) {
  let f = fmtCache.get(zone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone: zone,
      hourCycle: 'h23',
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      second: 'numeric',
      weekday: 'short',
    });
    fmtCache.set(zone, f);
  }
  const p = {};
  for (const { type, value } of f.formatToParts(date)) p[type] = value;
  const wd = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(p.weekday);
  return { y: +p.year, m: +p.month, d: +p.day, hh: +p.hour % 24, mm: +p.minute, ss: +p.second, wd };
}

/** 该时区里 y-m-d 00:00 对应的真实时刻（两遍修正 DST）。 */
export function zonedMidnight(y, m, d, zone = tz) {
  const guess = Date.UTC(y, m - 1, d);
  let t = guess;
  for (let i = 0; i < 2; i++) {
    const p = partsOf(new Date(t), zone);
    const asUTC = Date.UTC(p.y, p.m - 1, p.d, p.hh, p.mm, p.ss);
    t = guess - (asUTC - t);
  }
  return new Date(t);
}

export function startOfDay(date, zone = tz) {
  const p = partsOf(date, zone);
  return zonedMidnight(p.y, p.m, p.d, zone);
}

export const addDays = (date, n, zone = tz) => {
  const p = partsOf(date, zone);
  const u = new Date(Date.UTC(p.y, p.m - 1, p.d + n));
  return zonedMidnight(u.getUTCFullYear(), u.getUTCMonth() + 1, u.getUTCDate(), zone);
};

export const sameDay = (a, b, zone = tz) => startOfDay(a, zone).getTime() === startOfDay(b, zone).getTime();

export const pad = (n) => String(n).padStart(2, '0');

export function clock(date) {
  const p = partsOf(date);
  return `${pad(p.hh)}:${pad(p.mm)}`;
}

export const ymd = (date) => {
  const p = partsOf(date);
  return { y: p.y, m: p.m, d: p.d, wd: p.wd };
};

/** 时间筛选预设 → [start, end]；自定义按整天解释。与 iOS 一致：一周从周日起算。 */
export function resolveRange(filter, now = new Date()) {
  switch (filter.time) {
    case 'week': {
      const p = partsOf(now);
      return [addDays(startOfDay(now), -p.wd), now];
    }
    case 'month': {
      const p = partsOf(now);
      return [zonedMidnight(p.y, p.m, 1), now];
    }
    case 'quarter': {
      const p = partsOf(now);
      const u = new Date(Date.UTC(p.y, p.m - 1 - 3, p.d, p.hh, p.mm, p.ss));
      const back = zonedMidnight(u.getUTCFullYear(), u.getUTCMonth() + 1, u.getUTCDate());
      return [new Date(back.getTime() + (p.hh * 3600 + p.mm * 60 + p.ss) * 1000), now];
    }
    case 'custom': {
      if (!filter.start || !filter.end) return null;
      const [lo, hi] = filter.start <= filter.end ? [filter.start, filter.end] : [filter.end, filter.start];
      return [startOfDay(lo), new Date(addDays(hi, 1).getTime() - 1)];
    }
    default:
      return null;
  }
}

export function matchesFilter(brief, filter, now = new Date()) {
  if (filter.channelIds.length && !filter.channelIds.includes(brief.channelId)) return false;
  const r = resolveRange(filter, now);
  return !r || (brief.createdAt >= r[0] && brief.createdAt <= r[1]);
}

/** 按日期分组，保持倒序；组键为该日零点。 */
export function groupByDay(briefs) {
  const groups = [];
  const index = new Map();
  for (const b of briefs) {
    const key = startOfDay(b.createdAt).getTime();
    if (!index.has(key)) {
      const g = { day: new Date(key), briefs: [] };
      index.set(key, g);
      groups.push(g);
    }
    index.get(key).briefs.push(b);
  }
  return groups.sort((a, b) => b.day - a.day);
}

/** 自定义日期输入 <input type="date"> 的 "YYYY-MM-DD" ↔ 当前时区当天零点。 */
export const dateInputValue = (date) => {
  if (!date) return '';
  const p = partsOf(date);
  return `${p.y}-${pad(p.m)}-${pad(p.d)}`;
};
export const fromDateInput = (v) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v || '');
  return m ? zonedMidnight(+m[1], +m[2], +m[3]) : null;
};
