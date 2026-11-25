<script setup>
// 线性图标（24 网格，描边）。名字带 -fill 的是实心版本。
defineProps({ name: { type: String, required: true } });
const P = {
  back: '<path d="M15 5l-7 7 7 7"/>',
  chevron: '<path d="M9 5l7 7-7 7"/>',
  down: '<path d="M5 9l7 7 7-7"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4 4"/>',
  filter: '<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/>',
  more: '<circle cx="5.5" cy="12" r="1.2" fill="currentColor"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/><circle cx="18.5" cy="12" r="1.2" fill="currentColor"/>',
  bubble: '<path d="M5 18.5V7a3 3 0 0 1 3-3h8a3 3 0 0 1 3 3v6a3 3 0 0 1-3 3H8.5z"/>',
  mic: '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/>',
  send: '<path d="M12 19V5M6 11l6-6 6 6"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  bookmark: '<path d="M7 4h10v16l-5-3.5L7 20z"/>',
  'bookmark-fill': '<path d="M7 4h10v16l-5-3.5L7 20z" fill="currentColor"/>',
  news: '<rect x="4" y="4.5" width="16" height="15" rx="2.5"/><path d="M8 9h8M8 12.5h8M8 16h5"/>',
  'news-fill': '<rect x="4" y="4.5" width="16" height="15" rx="2.5" fill="currentColor"/><path d="M8 9h8M8 12.5h8M8 16h5" stroke="var(--canvas)"/>',
  channels: '<circle cx="12" cy="12" r="2"/><path d="M8 8a5.5 5.5 0 0 0 0 8M16 8a5.5 5.5 0 0 1 0 8M5.2 5.2a9.5 9.5 0 0 0 0 13.6M18.8 5.2a9.5 9.5 0 0 1 0 13.6"/>',
  'channels-fill': '<circle cx="12" cy="12" r="2.6" fill="currentColor"/><path d="M8 8a5.5 5.5 0 0 0 0 8M16 8a5.5 5.5 0 0 1 0 8M5.2 5.2a9.5 9.5 0 0 0 0 13.6M18.8 5.2a9.5 9.5 0 0 1 0 13.6" stroke-width="2.2"/>',
  user: '<circle cx="12" cy="8.5" r="3.5"/><path d="M5 19.5c1.2-3.3 3.8-5 7-5s5.8 1.7 7 5"/>',
  'user-fill': '<circle cx="12" cy="8.5" r="3.8" fill="currentColor"/><path d="M5 19.5c1.2-3.3 3.8-5 7-5s5.8 1.7 7 5z" fill="currentColor"/>',
  trash: '<path d="M5 7h14M10 7V5h4v2M7 7l1 12h8l1-12"/>',
};
</script>

<template>
  <svg class="icon" viewBox="0 0 24 24" aria-hidden="true" v-html="P[name] || ''" />
</template>
