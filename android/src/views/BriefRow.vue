<script setup>
// 紧凑行：标题（两行内）、描述（非空时一到两行）、频道点 + 频道名、时刻；新内容带「新」标记。
// title / summary 一律纯文本，不解析 Markdown。
import { computed } from 'vue';
import { feed, channelName, colorFor } from '../lib/store.js';
import { clock } from '../lib/time.js';
import { t } from '../lib/i18n.js';

const props = defineProps({ brief: Object });
defineEmits(['open']);
const isNew = computed(() => feed.newIds.includes(props.brief.id));
const name = computed(() => channelName(props.brief) || t('未知频道'));
</script>

<template>
  <button class="brief-row" :data-testid="`brief-${brief.id}`" @click="$emit('open')">
    <div class="brief-title">
      <span v-if="isNew" class="chip dark new">{{ $t('新') }}</span>{{ brief.title }}
    </div>
    <div v-if="brief.summary" class="brief-summary">{{ brief.summary }}</div>
    <div class="brief-meta">
      <span class="dot" :style="{ background: colorFor(brief.channelId) }" />
      <span class="brief-channel">{{ name }}</span>
      <span>·</span>
      <span class="num">{{ clock(brief.createdAt) }}</span>
    </div>
  </button>
</template>

<style>
.brief-row { display: block; width: 100%; text-align: left; padding: 13px 2px; border-bottom: 1px solid var(--line); }
.brief-row:active { background: var(--paper); }
.brief-title { font-size: 16.5px; font-weight: 700; line-height: 1.38; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.brief-title .new { height: 19px; padding: 0 6px; margin-right: 6px; font-size: 11px; vertical-align: 2px; }
.brief-summary { margin-top: 4px; color: var(--ink-2); font-size: 14px; line-height: 1.5; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.brief-meta { display: flex; align-items: center; gap: 6px; margin-top: 7px; font-size: 12.5px; color: var(--ink-3); }
.brief-channel { color: var(--ink-2); font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 60%; }
.brief-meta .num { font-size: 14px; }
</style>
