<script setup>
// 日报详情：标题 → 描述（非空时）→ 正文。不渲染 sections，不显示分组数与素材数。
// 右下角「追问」胶囊：滚动时收起为圆形，停止后恢复。
import { ref, computed, onMounted } from 'vue';
import NavBar from '../components/NavBar.vue';
import Icon from '../components/Icon.vue';
import { api, feed, state, channelName, colorFor, isSaved, toggleSaved } from '../lib/store.js';
import { push } from '../lib/ui.js';
import { renderBody } from '../lib/markdown.js';
import { monthDayTime, errorText } from '../lib/format.js';
import { t } from '../lib/i18n.js';

const props = defineProps({ id: String });
const brief = ref(feed.briefs.find((b) => b.id === props.id) || state.savedBriefs[props.id] || null);
const error = ref(null);

async function load() {
  error.value = null;
  try {
    brief.value = await api.brief(props.id);
  } catch (e) {
    error.value = e;
  }
}
onMounted(() => !brief.value && load());

const html = computed(() => (brief.value?.body ? renderBody(brief.value.body) : ''));
const name = computed(() => (brief.value && channelName(brief.value)) || t('日报'));

// 胶囊收起
const collapsed = ref(false);
let idle;
function onScroll() {
  collapsed.value = true;
  clearTimeout(idle);
  idle = setTimeout(() => (collapsed.value = false), 450);
}
</script>

<template>
  <div class="page">
    <NavBar>
      <template #title>
        <span v-if="brief" class="dot" :style="{ background: colorFor(brief.channelId) }" />
        <span>{{ name }}</span>
      </template>
      <template #right>
        <button
          v-if="brief"
          class="icon-btn"
          :aria-label="isSaved(brief.id) ? $t('移除收藏') : $t('收藏')"
          data-testid="brief-save"
          @click="toggleSaved(brief)"
        >
          <Icon :name="isSaved(brief.id) ? 'bookmark-fill' : 'bookmark'" />
        </button>
      </template>
    </NavBar>

    <div class="page-body scroll" @scroll.passive="onScroll">
      <div v-if="!brief && !error" class="center"><span class="spinner" />{{ $t('加载中…') }}</div>
      <div v-else-if="!brief" class="empty">
        <h3>{{ errorText(error) }}</h3>
        <button class="pill-btn" @click="load">{{ $t('重试') }}</button>
      </div>
      <article v-else class="detail page-pad">
        <h1 class="detail-title">{{ brief.title }}</h1>
        <div class="detail-time num">{{ monthDayTime(brief.createdAt) }}</div>
        <p v-if="brief.summary" class="detail-summary">{{ brief.summary }}</p>
        <div v-if="html" class="md" data-testid="brief-body" v-html="html" />
        <p v-else class="detail-nobody" data-testid="brief-body-empty">{{ $t('本期无可读正文') }}</p>
      </article>
    </div>

    <button
      v-if="brief"
      class="ask-pill"
      :class="{ collapsed }"
      :aria-label="$t('追问')"
      data-testid="ask-pill"
      @click="push('ask', { briefId: brief.id })"
    >
      <Icon name="bubble" /><span>{{ $t('追问') }}</span>
    </button>
  </div>
</template>

<style>
.detail { padding-bottom: 96px; }
.detail-title { margin: 8px 0 8px; font-size: 26px; line-height: 1.3; font-weight: 800; }
.detail-time { color: var(--ink-3); font-size: 15px; }
.detail-summary { margin: 14px 0 0; padding: 12px 14px; border-radius: var(--r-md); background: var(--paper); color: var(--ink-2); font-size: 15px; line-height: 1.6; }
.detail-nobody { margin-top: 22px; color: var(--ink-3); font-size: 14px; }

/* 长文排版 */
.md { margin-top: 20px; font-size: 17px; line-height: 1.78; color: var(--ink); user-select: text; -webkit-user-select: text; word-break: break-word; }
.md > :first-child { margin-top: 0; }
.md p { margin: 0 0 1.05em; }
.md h1, .md h2, .md h3, .md h4, .md h5, .md h6 { margin: 1.5em 0 0.55em; line-height: 1.35; font-weight: 800; }
.md h1 { font-size: 23px; } .md h2 { font-size: 21px; } .md h3 { font-size: 19px; }
.md h4, .md h5, .md h6 { font-size: 17px; }
.md ul, .md ol { margin: 0 0 1.05em; padding-left: 1.4em; }
.md li { margin: 0.25em 0; }
.md li > p { margin: 0; }
.md blockquote { margin: 0 0 1.05em; padding: 2px 0 2px 14px; border-left: 3px solid var(--line-strong); color: var(--ink-2); }
.md code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.86em; padding: 1px 5px; border-radius: 5px; background: var(--chip); }
.md pre { margin: 0 0 1.05em; padding: 12px 14px; border-radius: var(--r-md); background: var(--paper); overflow-x: auto; line-height: 1.55; }
.md pre code { padding: 0; background: none; font-size: 13.5px; white-space: pre; }
.md hr { border: 0; height: 1px; background: var(--line); margin: 1.6em 0; }
.md a { color: var(--ink); text-decoration: underline; text-decoration-color: var(--line-strong); text-underline-offset: 3px; text-decoration-thickness: 1.5px; }
.md strong { font-weight: 750; }

.ask-pill {
  position: absolute; right: 18px; bottom: 20px; z-index: 6;
  display: flex; align-items: center; gap: 6px; height: 46px; padding: 0 18px 0 15px; border-radius: 23px;
  background: var(--ink); color: var(--canvas); font-weight: 700; font-size: 15px;
  box-shadow: 0 10px 24px rgba(20, 20, 15, 0.28);
  transition: padding 0.25s var(--ease), gap 0.25s var(--ease);
}
.ask-pill .icon { width: 20px; height: 20px; }
.ask-pill span { max-width: 60px; overflow: hidden; white-space: nowrap; transition: max-width 0.25s var(--ease), opacity 0.2s; }
.ask-pill.collapsed { padding: 0 13px; gap: 0; }
.ask-pill.collapsed span { max-width: 0; opacity: 0; }
</style>
