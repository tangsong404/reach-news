// 依赖界面语言的展示格式（时刻、日期、时间表短语、错误文案）。
import { t, isEn } from './i18n.js';
import { ymd, clock, sameDay, addDays, startOfDay } from './time.js';
import { scheduleGroups, WEEKDAYS, ERROR_TEXT } from './model.js';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WD_ZH = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
const WD_EN = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

export function monthDay(date) {
  const { m, d } = ymd(date);
  return isEn() ? `${MONTHS[m - 1]} ${d}` : `${m}月${d}日`;
}
export const monthDayTime = (date) => `${monthDay(date)} ${clock(date)}`;
export function monthDayWeekday(date) {
  const { wd } = ymd(date);
  return isEn() ? `${WD_EN[wd]}, ${monthDay(date)}` : `${monthDay(date)} ${WD_ZH[wd]}`;
}
export function longDate(date) {
  const { y, m, d } = ymd(date);
  return isEn() ? `${MONTHS[m - 1]} ${d}, ${y}` : `${y}年${m}月${d}日`;
}

/** 日期分组标题：今天、昨天，更早用「M月d日」。 */
export function dayTitle(day, now = new Date()) {
  if (sameDay(day, now)) return t('今天');
  if (startOfDay(day).getTime() === addDays(now, -1).getTime()) return t('昨天');
  return monthDay(day);
}

/** 星期名：完整（周一）与短名（一）。 */
export const weekdayName = (key) => t(['周一', '周二', '周三', '周四', '周五', '周六', '周日'][WEEKDAYS.indexOf(key)]);
export const weekdayShort = (key) => t(['一', '二', '三', '四', '五', '六', '日'][WEEKDAYS.indexOf(key)]);

/** 「周一、三、五 08:00」「每天 07:30」「每周二 09:00」。 */
export function describeSchedule(schedule) {
  const groups = scheduleGroups(schedule);
  if (!groups.length) return t('未设置时间');
  return groups
    .map(({ days, times }) => {
      const time = times.join(' / ');
      if (days.length === 7) return t('每天 {time}', { time });
      if (days.length === 1) return t('每{day} {time}', { day: weekdayName(days[0]), time });
      const list = isEn()
        ? days.map(weekdayShort).join(', ')
        : weekdayName(days[0]) + '、' + days.slice(1).map(weekdayShort).join('、');
      return `${list} ${time}`;
    })
    .join('；');
}

/** 归一化错误 → 文案；服务端给的原始说明作为补充细节。 */
export const errorText = (e) => t(ERROR_TEXT[e?.kind] || ERROR_TEXT.server);
export const errorDetail = (e) => (e?.detail && e.kind !== 'offline' ? e.detail : '');
