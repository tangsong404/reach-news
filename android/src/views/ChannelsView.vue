<script setup>
// 频道页：一条滚动列表，顺序固定为「我的频道」「订阅的频道」「发现更多」。
// 运行状态只对屏幕内可见行轮询（每 60 秒），页面不可见即停。
import { ref, computed, watch, onMounted, onBeforeUnmount, nextTick } from 'vue';
import Icon from '../components/Icon.vue';
import ChannelCard from './ChannelCard.vue';
import { channels, state, loadChannels, refreshRuns, subscribe, isPending, effectiveColorIndex, colorFor } from '../lib/store.js';
import { nav, push } from '../lib/ui.js';
import { usePullRefresh } from '../lib/pull.js';
import { errorText } from '../lib/format.js';

const scroller = ref(null);
const { pull, handlers } = usePullRefresh(scroller, loadChannels);

const total = computed(() => channels.mine.length + channels.subscribed.length);
const fullyEmpty = computed(
  () => !channels.loading && channels.loaded && !channels.error && !total.value && !channels.discover.length,
);

// ---- 可见行 ----
const visibleIds = new Set();
let io;
let timer;
const active = computed(() => nav.tab === 'channels' && nav.stacks.channels.length === 0);

function observeCards() {
  nextTick(() => {
    io?.disconnect();
    visibleIds.clear();
    scroller.value?.querySelectorAll('[data-id]').forEach((el) => io.observe(el));
  });
}
onMounted(async () => {
  io = new IntersectionObserver(
    (entries) => {
      const added = [];
      for (const e of entries) {
        const id = e.target.dataset.id;
        if (e.isIntersecting) !visibleIds.has(id) && (visibleIds.add(id), added.push(id));
        else visibleIds.delete(id);
      }
      if (added.length && active.value) refreshRuns(added);
    },
    { root: scroller.value },
  );
  if (!channels.loaded) await loadChannels();
  observeCards();
  timer = setInterval(() => active.value && refreshRuns([...visibleIds]), 60_000);
});
onBeforeUnmount(() => (io?.disconnect(), clearInterval(timer)));
watch(() => [channels.mine.length, channels.subscribed.length], observeCards);
watch(active, (v) => v && refreshRuns([...visibleIds]));

const openChannel = (c) => (c.owner === 'creator' ? push('channelForm', { id: c.id }) : push('subscribed', { id: c.id }));
</script>

<template>
  <div class="page">
    <header class="bar">
      <span class="bar-spacer" />
      <button class="icon-btn" :aria-label="$t('新建频道')" data-testid="channel-create" @click="push('channelForm', {})">
        <Icon name="plus" />
      </button>
    </header>

    <div ref="scroller" class="page-body scroll" @touchstart.passive="handlers.touchstart" @touchmove.passive="handlers.touchmove" @touchend="handlers.touchend">
      <div class="ptr" :style="{ height: pull + 'px' }"><span v-if="pull" class="spinner" /></div>
      <div class="page-pad">
        <h1 class="large-title">{{ $t('频道') }}</h1>
        <div class="sub">{{ $t('{n} 个频道', { n: total }) }} · {{ $t('按 {tz} 触发', { tz: state.timeZone }) }}</div>

        <div v-if="channels.loading && !channels.loaded" class="center"><span class="spinner" />{{ $t('加载中…') }}</div>

        <div v-else-if="fullyEmpty" class="empty">
          <h3>{{ $t('还没有频道') }}</h3>
          <p>{{ $t('频道由管理员开通，或先订阅一个公开频道。') }}</p>
        </div>

        <div v-if="channels.error" class="banner warn ch-error">
          <span class="grow">{{ errorText(channels.error) }}</span>
          <button class="retry" @click="loadChannels">{{ $t('重试') }}</button>
        </div>

        <template v-if="channels.mine.length">
          <div class="rule">{{ $t('我的频道') }}</div>
          <ChannelCard v-for="c in channels.mine" :key="c.id" :channel="c" @open="openChannel(c)" />
        </template>

        <template v-if="channels.subscribed.length">
          <div class="rule">{{ $t('订阅的频道') }}</div>
          <ChannelCard v-for="c in channels.subscribed" :key="c.id" :channel="c" @open="openChannel(c)" />
        </template>

        <!-- 发现更多：默认折叠，折叠时也显示数量与错误 -->
        <button v-if="channels.loaded" class="rule discover-head" data-testid="discover-toggle" @click="channels.discoverExpanded = !channels.discoverExpanded">
          {{ $t('发现更多') }}
          <span class="num disc-count">{{ channels.discover.length }}</span>
          <Icon :name="channels.discoverExpanded ? 'down' : 'chevron'" />
        </button>
        <div v-if="channels.discoverError" class="banner warn">{{ errorText(channels.discoverError) }}</div>
        <template v-if="channels.discoverExpanded">
          <p v-if="!channels.discover.length && !channels.discoverError" class="sub">{{ $t('暂时没有可订阅的公开频道。') }}</p>
          <div v-for="c in channels.discover" :key="c.id" class="disc-row card" :data-testid="`discover-${c.id}`">
            <span class="dot" :style="{ background: colorFor(c) }" />
            <div class="grow">
              <b>{{ c.name }}</b>
              <p v-if="c.prompt">{{ c.prompt }}</p>
            </div>
            <button class="pill-btn" :disabled="isPending(c.id)" @click="subscribe(c.id, effectiveColorIndex(c.id))">
              {{ $t('订阅') }}
            </button>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>

<style>
.ch-error { margin-top: 14px; align-items: center; }
.ch-error .grow { flex: 1; }
.discover-head { width: 100%; text-align: left; }
.discover-head .icon { width: 16px; height: 16px; order: 3; }
.disc-count { font-size: 15px; color: var(--ink-2); }
.disc-row { display: flex; align-items: center; gap: 12px; padding: 12px 14px; margin-bottom: 8px; }
.disc-row .grow { flex: 1; min-width: 0; }
.disc-row b { font-size: 15.5px; }
.disc-row p { margin: 2px 0 0; font-size: 13px; color: var(--ink-3); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
</style>
