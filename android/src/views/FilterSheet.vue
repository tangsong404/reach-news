<script setup>
// 筛选面板：时间单选（含自定义范围）、频道多选；页脚「重置」与「显示 N 期」，N 随选择实时更新。
// 应用后若范围起点早于已加载边界，继续翻页直到覆盖再呈现。
import { reactive, computed, watch } from 'vue';
import Sheet from '../components/Sheet.vue';
import Icon from '../components/Icon.vue';
import { feed, feedChannels, colorFor, loadUntilCoveringFilter } from '../lib/store.js';
import { searchBriefs } from '../lib/model.js';
import { matchesFilter, dateInputValue, fromDateInput } from '../lib/time.js';

const props = defineProps({ open: Boolean });
const emit = defineEmits(['close']);

const draft = reactive({ time: 'all', start: null, end: null, channelIds: [] });
watch(
  () => props.open,
  (v) => v && Object.assign(draft, { ...feed.filter, channelIds: [...feed.filter.channelIds] }),
);

const TIMES = [
  ['all', '全部时间'],
  ['week', '本周'],
  ['month', '本月'],
  ['quarter', '近三个月'],
  ['custom', '自定义范围'],
];

const count = computed(() => searchBriefs(feed.briefs, feed.search).filter((b) => matchesFilter(b, draft)).length);

function pickTime(k) {
  draft.time = k;
  if (k === 'custom' && !draft.start) {
    draft.end = new Date();
    draft.start = new Date(Date.now() - 14 * 864e5);
  }
}
function toggleChannel(id) {
  draft.channelIds = draft.channelIds.includes(id) ? draft.channelIds.filter((x) => x !== id) : [...draft.channelIds, id];
}
const reset = () => Object.assign(draft, { time: 'all', start: null, end: null, channelIds: [] });

async function apply() {
  Object.assign(feed.filter, { ...draft, channelIds: [...draft.channelIds] });
  emit('close');
  await loadUntilCoveringFilter();
}
</script>

<template>
  <Sheet :open="open" @close="emit('close')">
    <div class="filter scroll">
      <div class="label">{{ $t('时间') }}</div>
      <div class="group">
        <button v-for="[k, label] in TIMES" :key="k" class="row tap" @click="pickTime(k)">
          <span class="grow">{{ $t(label) }}</span>
          <span class="radio" :class="{ on: draft.time === k }"><Icon v-if="draft.time === k" name="check" /></span>
        </button>
      </div>
      <div v-if="draft.time === 'custom'" class="range">
        <label>
          <span>{{ $t('开始') }}</span>
          <input type="date" :value="dateInputValue(draft.start)" @change="draft.start = fromDateInput($event.target.value)" />
        </label>
        <label>
          <span>{{ $t('结束') }}</span>
          <input type="date" :value="dateInputValue(draft.end)" @change="draft.end = fromDateInput($event.target.value)" />
        </label>
      </div>

      <div class="label">{{ $t('频道') }}</div>
      <div v-if="feedChannels.length" class="group">
        <button v-for="c in feedChannels" :key="c.id" class="row tap" @click="toggleChannel(c.id)">
          <span class="dot" :style="{ background: colorFor(c) }" />
          <span class="grow">{{ c.name }}</span>
          <span class="radio" :class="{ on: draft.channelIds.includes(c.id) }"><Icon v-if="draft.channelIds.includes(c.id)" name="check" /></span>
        </button>
      </div>
      <p v-else class="sub">{{ $t('还没有可筛选的频道') }}</p>
    </div>
    <div class="filter-foot">
      <button class="foot-btn light press" @click="reset">{{ $t('重置') }}</button>
      <button class="foot-btn press" data-testid="filter-apply" @click="apply">{{ $t('显示 {n} 期', { n: count }) }}</button>
    </div>
  </Sheet>
</template>

<style>
.filter { flex: 1; min-height: 0; padding: 0 var(--gutter) 8px; }
.filter .label:first-child { margin-top: 4px; }
.radio { width: 22px; height: 22px; border-radius: 50%; box-shadow: inset 0 0 0 1.5px var(--line-strong); display: grid; place-items: center; }
.radio.on { background: var(--ink); color: var(--canvas); box-shadow: none; }
.radio .icon { width: 15px; height: 15px; stroke-width: 2.6; }
.range { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 10px; }
.range label { display: flex; flex-direction: column; gap: 4px; padding: 10px 12px; border-radius: var(--r-md); background: var(--paper); font-size: 12px; color: var(--ink-3); }
.range input { border: 0; background: none; outline: 0; font-size: 16px; font-weight: 650; color: var(--ink); padding: 0; }
.filter-foot { flex: none; display: grid; grid-template-columns: 1fr 2fr; gap: 10px; padding: 12px var(--gutter) 10px; box-shadow: 0 -1px 0 var(--line); }
.foot-btn { height: 48px; border-radius: 14px; background: var(--ink); color: var(--canvas); font-weight: 700; font-size: 16px; }
.foot-btn.light { background: var(--chip); color: var(--ink); }
</style>
