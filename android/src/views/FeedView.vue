<script setup>
// 日报流：日报页即完整历史。搜索常驻、筛选从底部升起、按日期分组、触底翻页、下拉刷新、
// 进入页面拉一次 /cursor，停留期间每 60 秒一次，离开即停。
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import Icon from '../components/Icon.vue';
import FilterSheet from './FilterSheet.vue';
import BriefRow from './BriefRow.vue';
import { feed, feedVisible, feedGroups, feedChannels, loadFeed, loadMoreFeed, pollCursor, colorFor } from '../lib/store.js';
import { nav, push } from '../lib/ui.js';
import { t } from '../lib/i18n.js';
import { monthDayWeekday, dayTitle, errorText, monthDay } from '../lib/format.js';

const filterOpen = ref(false);
const scroller = ref(null);
const sentinel = ref(null);

const activeDims = computed(() => (feed.filter.time !== 'all' ? 1 : 0) + (feed.filter.channelIds.length ? 1 : 0));

const TIME_LABEL = { week: '本周', month: '本月', quarter: '近三个月', custom: '自定义范围' };
const appliedChips = computed(() => {
  const chips = [];
  const f = feed.filter;
  if (f.time !== 'all') {
    const label =
      f.time === 'custom' && f.start && f.end ? `${monthDay(f.start)} – ${monthDay(f.end)}` : t(TIME_LABEL[f.time]);
    chips.push({ key: 'time', label, remove: () => Object.assign(f, { time: 'all', start: null, end: null }) });
  }
  for (const id of f.channelIds) {
    const c = feed.channelsById[id];
    chips.push({
      key: id,
      label: c?.name || t('未知频道'),
      color: colorFor(c || id),
      remove: () => (f.channelIds = f.channelIds.filter((x) => x !== id)),
    });
  }
  return chips;
});

// ---- 轮询：日报标签可见时每 60 秒一次 ----
let pollTimer = null;
const visible = computed(() => nav.tab === 'feed' && nav.stacks.feed.length === 0);
function startPolling() {
  stopPolling();
  pollTimer = setInterval(pollCursor, 60_000);
}
function stopPolling() {
  clearInterval(pollTimer);
  pollTimer = null;
}
watch(visible, (v) => (v ? (pollCursor(), startPolling()) : stopPolling()));

// ---- 触底翻页 ----
let io;
onMounted(() => {
  if (!feed.briefs.length) loadFeed();
  startPolling();
  io = new IntersectionObserver((es) => es.some((e) => e.isIntersecting) && loadMoreFeed(), {
    root: scroller.value,
    rootMargin: '400px',
  });
  watch(sentinel, (el, old) => (old && io.unobserve(old), el && io.observe(el)), { immediate: true });
});
onBeforeUnmount(() => (stopPolling(), io?.disconnect()));

// ---- 下拉刷新 ----
const pull = ref(0);
let startY = null;
function touchStart(e) {
  startY = scroller.value.scrollTop <= 0 ? e.touches[0].clientY : null;
}
function touchMove(e) {
  if (startY === null) return;
  const d = e.touches[0].clientY - startY;
  pull.value = d > 0 ? Math.min(90, d * 0.5) : 0;
}
async function touchEnd() {
  if (startY === null) return;
  startY = null;
  if (pull.value >= 60) {
    pull.value = 48;
    await loadFeed({ refresh: true });
  }
  pull.value = 0;
}

const open = (b) => push('brief', { id: b.id });
const now = ref(new Date());
</script>

<template>
  <div class="page feed">
    <header class="bar">
      <div class="bar-title brand">
        <img src="/logo-mark.png" alt="" />
        <span>Reach News</span>
      </div>
    </header>

    <div
      ref="scroller"
      class="page-body scroll"
      @touchstart.passive="touchStart"
      @touchmove.passive="touchMove"
      @touchend="touchEnd"
    >
      <div class="ptr" :style="{ height: pull + 'px' }">
        <span v-if="pull > 0 || feed.refreshing" class="spinner" :style="{ opacity: Math.min(1, pull / 60) }" />
      </div>
      <div class="page-pad">
        <div class="feed-meta">
          <span>
            {{ monthDayWeekday(now) }} · {{ $t('{n} 个频道', { n: feedChannels.length }) }} ·
            {{ $t('共 {n} 期', { n: feed.briefs.length }) }}
          </span>
          <span>{{ $t('最新优先') }}</span>
        </div>

        <div class="feed-tools">
          <label class="search">
            <Icon name="search" />
            <input v-model="feed.search" type="search" :placeholder="$t('搜索日报标题')" data-testid="feed-search" />
            <button v-if="feed.search" class="clear" :aria-label="$t('清除搜索')" @click="feed.search = ''">
              <Icon name="close" />
            </button>
          </label>
          <button class="filter-btn press" :class="{ on: activeDims }" data-testid="feed-filter" @click="filterOpen = true">
            <Icon name="filter" />
            {{ $t('筛选') }}
            <span v-if="activeDims" class="badge num">{{ activeDims }}</span>
          </button>
        </div>

        <div v-if="appliedChips.length" class="applied">
          <button v-for="c in appliedChips" :key="c.key" class="chip applied-chip" :aria-label="$t('移除该筛选')" @click="c.remove">
            <span v-if="c.color" class="dot" :style="{ background: c.color }" />
            {{ c.label }}
            <Icon name="close" />
          </button>
        </div>

        <!-- 状态 -->
        <div v-if="feed.loading && !feed.briefs.length" class="center"><span class="spinner" />{{ $t('正在加载日报…') }}</div>
        <div v-else-if="feed.error && !feed.briefs.length" class="empty">
          <h3>{{ errorText(feed.error) }}</h3>
          <p v-if="feed.error.kind === 'offline'">{{ $t('恢复网络后再试。客户端不缓存内容，因此这里不会显示历史日报。') }}</p>
          <button class="pill-btn" @click="loadFeed()">{{ $t('重试') }}</button>
        </div>
        <div v-else-if="!feed.briefs.length && !feed.loading" class="empty">
          <h3>{{ $t('还没有日报') }}</h3>
          <p>{{ $t('频道产出的第一期日报会出现在这里。') }}</p>
        </div>
        <div v-else-if="!feedVisible.length" class="empty">
          <h3>{{ $t('没有匹配的日报') }}</h3>
          <p>{{ $t('换个关键词，或调整筛选条件。') }}</p>
        </div>

        <!-- 列表 -->
        <section v-for="g in feedGroups" :key="g.day.getTime()">
          <div class="rule">{{ dayTitle(g.day, now) }}</div>
          <BriefRow v-for="b in g.briefs" :key="b.id" :brief="b" @open="open(b)" />
        </section>

        <div v-if="feed.briefs.length" ref="sentinel" class="center">
          <template v-if="feed.loadingMore"><span class="spinner" />{{ $t('正在加载更早的日报…') }}</template>
          <template v-else-if="feed.error">
            {{ errorText(feed.error) }}
            <button class="pill-btn light" @click="loadMoreFeed()">{{ $t('重试') }}</button>
          </template>
          <template v-else-if="!feed.hasMore">{{ $t('没有更早的日报了') }}</template>
        </div>
      </div>
    </div>

    <FilterSheet :open="filterOpen" @close="filterOpen = false" />
  </div>
</template>

<style>
.brand img { width: 24px; height: 24px; border-radius: 6px; }
.brand span { font-weight: 800; letter-spacing: 0.2px; }
.ptr { display: flex; align-items: flex-end; justify-content: center; overflow: hidden; transition: height 0.2s; }
.ptr .spinner { margin-bottom: 12px; }
.feed-meta { display: flex; justify-content: space-between; gap: 12px; margin: 6px 2px 12px; font-size: 12.5px; color: var(--ink-3); }
.feed-meta span:last-child { flex: none; font-weight: 600; color: var(--ink-2); }
.feed-tools { display: flex; gap: 10px; }
.search { flex: 1; min-width: 0; display: flex; align-items: center; gap: 8px; height: 42px; padding: 0 6px 0 12px; border-radius: var(--r-md); background: var(--surface); box-shadow: 0 0 0 1px var(--line); color: var(--ink-3); }
.search .icon { width: 18px; height: 18px; }
.search input { flex: 1; min-width: 0; border: 0; outline: 0; background: none; font-size: 15px; color: var(--ink); }
.search input::-webkit-search-cancel-button { display: none; }
.search .clear { width: 30px; height: 30px; display: grid; place-items: center; }
.filter-btn { flex: none; display: flex; align-items: center; gap: 6px; height: 42px; padding: 0 14px; border-radius: var(--r-md); background: var(--surface); box-shadow: 0 0 0 1px var(--line); font-size: 14px; font-weight: 600; }
.filter-btn .icon { width: 18px; height: 18px; }
.filter-btn.on { background: var(--ink); color: var(--canvas); box-shadow: none; }
.filter-btn .badge { min-width: 18px; height: 18px; padding: 0 5px; border-radius: 9px; background: var(--canvas); color: var(--ink); font-size: 13px; display: grid; place-items: center; }
.applied { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
.applied-chip { height: 28px; font-size: 13px; }
.applied-chip .icon { width: 14px; height: 14px; stroke-width: 2.2; }
</style>
