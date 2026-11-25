<script setup>
// 频道卡。我的频道：开关、提示词、状态 chip、时间表、连接器；订阅频道：只读，带「订阅」标记。
import { computed } from 'vue';
import Toggle from '../components/Toggle.vue';
import { channels, colorFor, setEnabled, isPending } from '../lib/store.js';
import { isSubscription, warnsNoConnectors, RUNNING_STATES } from '../lib/model.js';
import { describeSchedule, monthDayTime, errorText } from '../lib/format.js';
import { toast } from '../lib/ui.js';
import { t } from '../lib/i18n.js';

const props = defineProps({ channel: Object });
defineEmits(['open']);

const sub = computed(() => isSubscription(props.channel));
const run = computed(() => channels.latestRuns[props.channel.id]);

/** 三分法状态 chip：运行中绿、missed 中性灰、failed 警示色；关闭时显示「未启用」。 */
const status = computed(() => {
  if (!sub.value && !props.channel.enabled) return { cls: '', text: t('未启用') };
  const s = run.value?.state;
  if (RUNNING_STATES.includes(s)) return { cls: 'running', text: t('写作中') };
  if (s === 'missed') return { cls: 'missed', text: t('本次未产出日报') };
  if (s === 'failed') return { cls: 'failed', text: t('运行失败，素材已保留') };
  return null;
});

const connectorText = computed(() =>
  props.channel.connectors.length
    ? props.channel.connectors.map((c) => c.name || c.id).join('、')
    : props.channel.connectorIds.join('、'),
);

async function toggle(v) {
  const err = await setEnabled(props.channel.id, v);
  if (err) toast(errorText(err));
}
</script>

<template>
  <div class="ch-card card press" :data-id="channel.id" :data-testid="`channel-${channel.id}`" role="button" @click="$emit('open')">
    <div class="ch-head">
      <span class="dot" :style="{ background: colorFor(channel) }" />
      <b class="ch-name">{{ channel.name }}</b>
      <span v-if="channel.kind === 'follow'" class="chip">{{ $t('跟踪') }}</span>
      <span v-if="sub" class="chip">{{ $t('已订阅') }}</span>
      <span class="bar-spacer" />
      <Toggle
        v-if="!sub"
        :model-value="channel.enabled"
        :disabled="isPending(channel.id)"
        :label="$t('启用该频道')"
        @update:model-value="toggle"
      />
    </div>
    <p v-if="channel.prompt" class="ch-prompt">{{ channel.prompt }}</p>
    <div class="ch-meta">
      <span v-if="status" class="chip" :class="status.cls">{{ status.text }}</span>
      <span>{{ describeSchedule(channel.schedule) }}</span>
    </div>
    <div v-if="connectorText" class="ch-conn">{{ connectorText }}</div>
    <div v-if="sub && channel.lastBriefAt" class="ch-conn">{{ $t('最近日报') }} <span class="num">{{ monthDayTime(channel.lastBriefAt) }}</span></div>
    <div v-if="warnsNoConnectors(channel)" class="ch-warn">{{ $t('未配置连接器，运行将不会产出日报') }}</div>
  </div>
</template>

<style>
.ch-card { padding: 14px 16px; margin-bottom: 10px; }
.ch-card:active { transform: scale(0.985); }
.ch-head { display: flex; align-items: center; gap: 8px; min-height: 28px; }
.ch-name { font-size: 16.5px; font-weight: 750; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.ch-prompt { margin: 6px 0 0; color: var(--ink-2); font-size: 14px; line-height: 1.5; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.ch-meta { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; margin-top: 10px; font-size: 13px; color: var(--ink-2); }
.ch-conn { margin-top: 4px; font-size: 12.5px; color: var(--ink-3); }
.ch-warn { margin-top: 8px; font-size: 12.5px; color: var(--failed-fg); }
</style>
