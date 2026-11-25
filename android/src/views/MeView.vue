<script setup>
// 我的：收藏（仅本机）、偏好（界面语言、服务地址）、连接信息与退出登录。
import { ref, computed, watch } from 'vue';
import Icon from '../components/Icon.vue';
import Confirm from '../components/Confirm.vue';
import { state, feed, api, savePrefs, signOut, toggleSaved, channelName, colorFor } from '../lib/store.js';
import { parseBaseURL } from '../lib/model.js';
import { push, toast } from '../lib/ui.js';
import { monthDayTime, longDate } from '../lib/format.js';
import { t } from '../lib/i18n.js';

// 收藏只存 ID；对象从已加载的日报流里取，缺的按需取一次（不落盘）
const savedBriefs = computed(() =>
  state.saved.map((id) => feed.briefs.find((b) => b.id === id) || state.savedBriefs[id] || { id, missing: true }),
);
watch(
  () => state.saved.slice(),
  async (ids) => {
    for (const id of ids) {
      if (feed.briefs.some((b) => b.id === id) || state.savedBriefs[id]) continue;
      try {
        state.savedBriefs[id] = await api.brief(id);
      } catch {
        /* 取不到时显示占位行，仍可移除 */
      }
    }
  },
  { immediate: true },
);

const LANGS = [
  ['system', '跟随系统'],
  ['zh', '中文'],
  ['en', 'English'],
];

const baseInput = ref(state.prefs.baseURL.replace(/^https:\/\//, ''));
const baseChanged = computed(() => parseBaseURL(baseInput.value) !== state.prefs.baseURL);
function saveBase() {
  const url = parseBaseURL(baseInput.value);
  if (!url) return toast(t('服务地址无效'));
  savePrefs({ baseURL: url });
  toast(t('已保存'));
}

const confirmOut = ref(false);
</script>

<template>
  <div class="page">
    <header class="bar" />
    <div class="page-body scroll">
      <div class="page-pad">
        <h1 class="large-title">{{ $t('我的') }}</h1>

        <div class="label">{{ $t('收藏') }}</div>
        <div v-if="!state.saved.length" class="group">
          <div class="saved-empty">
            <b>{{ $t('还没有收藏') }}</b>
            <span>{{ $t('在日报详情里收藏后，会出现在这里。') }}</span>
          </div>
        </div>
        <div v-else class="group">
          <div v-for="b in savedBriefs" :key="b.id" class="row tap saved-row" role="button" @click="push('brief', { id: b.id })">
            <span v-if="!b.missing" class="dot" :style="{ background: colorFor(b.channelId) }" />
            <div class="grow">
              <div class="saved-title">{{ b.title || $t('加载中…') }}</div>
              <div v-if="!b.missing" class="saved-meta">{{ channelName(b) }} · <span class="num">{{ monthDayTime(b.createdAt) }}</span></div>
            </div>
            <button class="icon-btn" :aria-label="$t('移除收藏')" @click.stop="toggleSaved(b)"><Icon name="bookmark-fill" /></button>
          </div>
        </div>

        <div class="label">{{ $t('界面语言') }}</div>
        <div class="seg">
          <button v-for="[k, label] in LANGS" :key="k" :class="{ on: state.prefs.lang === k }" @click="savePrefs({ lang: k })">
            {{ k === 'system' ? $t(label) : label }}
          </button>
        </div>

        <div class="label">{{ $t('服务地址') }}</div>
        <div class="base-row">
          <input v-model="baseInput" class="field" inputmode="url" autocapitalize="off" spellcheck="false" />
          <button class="pill-btn" :disabled="!baseChanged" @click="saveBase">{{ $t('保存') }}</button>
        </div>

        <div class="label">{{ $t('连接信息') }}</div>
        <div class="group">
          <div class="row"><span class="grow">{{ $t('当前地址') }}</span><span class="val">{{ state.prefs.baseURL.replace(/^https?:\/\//, '') }}</span></div>
          <div v-if="state.session?.userName" class="row"><span class="grow">{{ $t('账号') }}</span><span class="val">{{ state.session.userName }}</span></div>
          <div class="row"><span class="grow">{{ $t('凭证') }}</span><span class="val">{{ state.session ? $t('已保存') : $t('未保存') }}</span></div>
          <div v-if="state.session" class="row"><span class="grow">{{ $t('凭证到期') }}</span><span class="val">{{ longDate(state.session.expiresAt) }}</span></div>
          <button class="row tap danger" @click="confirmOut = true">{{ $t('退出登录') }}</button>
        </div>
      </div>
    </div>

    <Confirm
      :open="confirmOut"
      :title="$t('退出登录？')"
      :message="$t('本机凭证会被清除，需要重新输入账号和密码。')"
      :action="$t('退出登录')"
      danger
      @close="confirmOut = false"
      @confirm="(confirmOut = false), signOut()"
    />
  </div>
</template>

<style>
.saved-empty { display: flex; flex-direction: column; gap: 4px; padding: 16px; font-size: 14px; color: var(--ink-3); }
.saved-empty b { color: var(--ink); font-size: 15px; }
.saved-row { padding-right: 4px; }
.saved-title { font-size: 15px; font-weight: 650; line-height: 1.4; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.saved-meta { margin-top: 2px; font-size: 12.5px; color: var(--ink-3); }
.seg { display: flex; gap: 4px; padding: 4px; border-radius: var(--r-md); background: var(--paper); }
.seg button { flex: 1; height: 36px; border-radius: 9px; font-size: 14px; color: var(--ink-2); font-weight: 600; }
.seg button.on { background: var(--surface); color: var(--ink); box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08); }
.base-row { display: flex; gap: 8px; align-items: center; }
.base-row .field { flex: 1; }
</style>
