<script setup>
// 追问：近单色工具风。回答是服务端确定性拼接，不是 LLM —— 不流式、不逐字、不显示「正在思考」。
// 失败的那一轮以可重试样式留在会话里，输入内容不丢。
import { ref, computed, nextTick, onMounted } from 'vue';
import Icon from '../components/Icon.vue';
import { api } from '../lib/store.js';
import { pop, toast } from '../lib/ui.js';
import { startOfDay, clock, sameDay } from '../lib/time.js';
import { dayTitle, errorText } from '../lib/format.js';
import { t } from '../lib/i18n.js';

const props = defineProps({ briefId: String });

const turns = ref([]);
const loading = ref(true);
const loadingMore = ref(false);
const nextCursor = ref(null);
const error = ref(null);
const draft = ref('');
const sending = ref(false);
const failed = ref(null); // { id, message, error }
const answeredHere = ref(false);
const scroller = ref(null);

const sortTurns = (list) => [...list].sort((a, b) => a.createdAt - b.createdAt);
const scrollToEnd = () => nextTick(() => scroller.value && (scroller.value.scrollTop = scroller.value.scrollHeight));

async function loadHistory() {
  loading.value = true;
  error.value = null;
  try {
    const p = await api.askHistory(props.briefId, null);
    turns.value = sortTurns(p.items);
    nextCursor.value = p.nextCursor;
    scrollToEnd();
  } catch (e) {
    error.value = e;
  } finally {
    loading.value = false;
  }
}
onMounted(loadHistory);

async function loadEarlier() {
  if (!nextCursor.value || loadingMore.value) return;
  loadingMore.value = true;
  try {
    const p = await api.askHistory(props.briefId, nextCursor.value);
    const seen = new Set(turns.value.map((x) => x.id));
    turns.value = sortTurns([...turns.value, ...p.items.filter((x) => !seen.has(x.id))]);
    nextCursor.value = p.nextCursor;
  } catch (e) {
    toast(errorText(e));
  } finally {
    loadingMore.value = false;
  }
}

/** 按日期插入分隔标签。 */
const rows = computed(() => {
  const out = [];
  let last = null;
  for (const turn of turns.value) {
    if (!last || !sameDay(last, turn.createdAt)) out.push({ sep: true, key: 'd' + startOfDay(turn.createdAt).getTime(), day: turn.createdAt });
    out.push({ key: turn.id, turn });
    last = turn.createdAt;
  }
  return out;
});

const canSend = computed(() => draft.value.trim() && !sending.value);

async function send(text = draft.value.trim()) {
  if (!text || sending.value) return;
  sending.value = true;
  failed.value = null;
  draft.value = '';
  const userTurn = { id: `local-${Date.now()}`, role: 'user', message: text, createdAt: new Date() };
  turns.value = [...turns.value, userTurn];
  scrollToEnd();
  try {
    const r = await api.ask(props.briefId, text);
    turns.value = [...turns.value, r.turn];
    answeredHere.value = true;
  } catch (e) {
    // 失败的一轮留在会话里，可重试；已输入内容放回输入框
    turns.value = turns.value.filter((x) => x.id !== userTurn.id);
    failed.value = { message: text, error: e };
    draft.value = text;
  } finally {
    sending.value = false;
    scrollToEnd();
  }
}

const devToast = () => toast(t('功能开发中'));
</script>

<template>
  <div class="page ask">
    <header class="bar ask-bar">
      <button class="round-btn" :aria-label="$t('返回')" @click="pop()"><Icon name="back" /></button>
      <div class="ask-heading">
        <b>{{ $t('本期日报') }}</b>
        <span>{{ $t('基于归档摘要') }}</span>
      </div>
    </header>

    <div ref="scroller" class="page-body scroll ask-scroll">
      <div v-if="loading" class="center"><span class="spinner" /></div>
      <div v-else-if="error" class="empty">
        <h3>{{ errorText(error) }}</h3>
        <button class="pill-btn" @click="loadHistory">{{ $t('重试') }}</button>
      </div>
      <div v-else-if="!turns.length && !failed" class="empty">
        <h3>{{ $t('还没有追问') }}</h3>
        <p>{{ $t('就这一期日报提一个问题，服务端会基于归档摘要作答。') }}</p>
      </div>

      <div class="turns">
        <button v-if="nextCursor" class="pill-btn light earlier" :disabled="loadingMore" @click="loadEarlier">
          {{ $t('加载更早的追问') }}
        </button>
        <template v-for="r in rows" :key="r.key">
          <div v-if="r.sep" class="ask-day">{{ dayTitle(r.day) }} {{ clock(r.day) }}</div>
          <div v-else class="bubble" :class="r.turn.role">{{ r.turn.message }}</div>
        </template>

        <!-- 引用素材卡：按稿子留位；引用与归属数据待服务端支持，不填入任何素材 -->
        <div v-if="answeredHere" class="cited">
          <div class="cited-head">{{ $t('引用的素材') }}<span class="chip">{{ $t('功能开发中') }}</span></div>
          <p>{{ $t('引用与归属数据待服务端支持。') }}</p>
        </div>

        <div v-if="failed" class="failed-turn">
          <div class="bubble user failed">{{ failed.message }}</div>
          <div class="failed-note">
            {{ errorText(failed.error) }}
            <button class="retry" @click="send(failed.message)">{{ $t('重试') }}</button>
          </div>
        </div>
      </div>
    </div>

    <form class="composer" @submit.prevent="send()">
      <button type="button" class="round-btn" :aria-label="$t('更多')" @click="devToast"><Icon name="plus" /></button>
      <input v-model="draft" class="composer-input" :placeholder="$t('就这期日报提问')" enterkeyhint="send" data-testid="ask-input" @focus="scrollToEnd" />
      <button v-if="canSend" type="submit" class="round-btn dark" :aria-label="$t('发送')"><Icon name="send" /></button>
      <button v-else type="button" class="round-btn" :aria-label="$t('语音')" :disabled="sending" @click="devToast"><Icon name="mic" /></button>
    </form>
  </div>
</template>

<style>
.ask { background: var(--ask-bg); padding-bottom: var(--kb, 0px); }
.ask-bar { background: color-mix(in srgb, var(--ask-bg) 92%, transparent); gap: 10px; padding-left: 12px; }
.ask-heading { display: flex; flex-direction: column; line-height: 1.25; }
.ask-heading b { font-size: 16px; }
.ask-heading span { font-size: 12px; color: var(--ink-3); }
.round-btn { width: 40px; height: 40px; flex: none; border-radius: 50%; display: grid; place-items: center; background: var(--ask-surface); box-shadow: 0 0 0 1px var(--line); color: var(--ink); }
.round-btn .icon { width: 20px; height: 20px; }
.round-btn.dark { background: var(--ask-user); color: var(--ask-user-text); box-shadow: none; }
.round-btn:disabled { opacity: 0.4; }
.ask-scroll { padding: 8px 16px 16px; }
.turns { display: flex; flex-direction: column; gap: 10px; }
.earlier { align-self: center; }
.ask-day { align-self: center; margin: 10px 0 2px; font-size: 12px; color: var(--ink-3); }
.bubble { max-width: 82%; padding: 11px 15px; border-radius: 20px; font-size: 15.5px; line-height: 1.55; white-space: pre-wrap; word-break: break-word; user-select: text; -webkit-user-select: text; }
.bubble.user { align-self: flex-end; background: var(--ask-user); color: var(--ask-user-text); border-bottom-right-radius: 6px; }
.bubble.assistant { align-self: flex-start; background: var(--ask-bubble); color: var(--ink); border-bottom-left-radius: 6px; }
.bubble.failed { opacity: 0.55; }
.failed-turn { display: flex; flex-direction: column; gap: 6px; }
.failed-note { align-self: flex-end; display: flex; align-items: center; gap: 8px; font-size: 12.5px; color: var(--failed-fg); }
.retry { height: 28px; padding: 0 12px; border-radius: 14px; background: var(--failed-bg); color: var(--failed-fg); font-weight: 650; font-size: 12.5px; }
.cited { align-self: flex-start; width: 82%; padding: 12px 14px; border-radius: 16px; background: var(--ask-surface); box-shadow: 0 0 0 1px var(--line); }
.cited-head { display: flex; align-items: center; justify-content: space-between; font-size: 13px; font-weight: 650; }
.cited p { margin: 6px 0 0; font-size: 12.5px; color: var(--ink-3); }
.composer {
  flex: none; display: flex; align-items: center; gap: 8px; padding: 10px 12px calc(var(--sab) + 10px);
  background: var(--ask-bg); box-shadow: 0 -1px 0 var(--line);
}
.composer-input { flex: 1; min-width: 0; height: 42px; padding: 0 16px; border: 0; outline: 0; border-radius: 21px; background: var(--ask-surface); box-shadow: 0 0 0 1px var(--line); font-size: 15.5px; }
</style>
