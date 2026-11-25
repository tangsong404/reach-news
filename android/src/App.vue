<script setup>
import { computed, onMounted } from 'vue';
import { App as CapApp } from '@capacitor/app';
import Icon from './components/Icon.vue';
import Toast from './components/Toast.vue';
import LoginView from './views/LoginView.vue';
import FeedView from './views/FeedView.vue';
import ChannelsView from './views/ChannelsView.vue';
import MeView from './views/MeView.vue';
import BriefDetail from './views/BriefDetail.vue';
import AskView from './views/AskView.vue';
import ChannelForm from './views/ChannelForm.vue';
import SubscribedDetail from './views/SubscribedDetail.vue';
import { state, loadFeed, loadSettings } from './lib/store.js';
import { nav, handleBack, pop, canPop, haptic } from './lib/ui.js';

const TABS = [
  { key: 'feed', label: '日报', icon: 'news' },
  { key: 'channels', label: '频道', icon: 'channels' },
  { key: 'me', label: '我的', icon: 'user' },
];
const PAGES = { brief: BriefDetail, ask: AskView, channelForm: ChannelForm, subscribed: SubscribedDetail };

function setTab(k) {
  if (k === nav.tab) {
    // 再点当前标签：回到该标签的根页面
    nav.stacks[k] = [];
    return;
  }
  haptic.select();
  nav.tab = k;
}

const hideTabbar = computed(() => nav.stacks[nav.tab].at(-1)?.name === 'ask');

onMounted(() => {
  // 安卓返回键：先关弹窗，再退页面栈，再回日报标签，最后退到后台
  CapApp.addListener('backButton', () => {
    if (handleBack()) return;
    if (canPop()) return pop();
    if (nav.tab !== 'feed') nav.tab = 'feed';
    else CapApp.minimizeApp();
  });
  CapApp.addListener('resume', () => {
    if (!state.session) return;
    loadSettings();
    loadFeed({ refresh: true });
  });
});
</script>

<template>
  <template v-if="state.ready">
    <LoginView v-if="!state.session" />
    <div v-else class="app">
      <main class="views">
        <section v-for="tb in TABS" :key="tb.key" class="view" :class="{ active: nav.tab === tb.key }">
          <FeedView v-if="tb.key === 'feed'" />
          <ChannelsView v-else-if="tb.key === 'channels'" />
          <MeView v-else />
          <TransitionGroup name="push">
            <component
              :is="PAGES[p.name]"
              v-for="p in nav.stacks[tb.key]"
              :key="p.key"
              v-bind="p.props"
              class="pushed"
            />
          </TransitionGroup>
        </section>
      </main>
      <nav v-show="!hideTabbar" class="tabbar">
        <button
          v-for="tb in TABS"
          :key="tb.key"
          class="tab"
          :class="{ on: nav.tab === tb.key }"
          :data-testid="`tab-${tb.key}`"
          @click="setTab(tb.key)"
        >
          <Icon :name="nav.tab === tb.key ? tb.icon + '-fill' : tb.icon" />
          <span>{{ $t(tb.label) }}</span>
        </button>
      </nav>
    </div>
  </template>
  <Toast />
</template>

<style>
.app { height: 100%; display: flex; flex-direction: column; max-width: 720px; margin: 0 auto; }
.views { position: relative; flex: 1; min-height: 0; }
.view { position: absolute; inset: 0; display: none; overflow: hidden; }
.view.active { display: block; }
.pushed { z-index: 10; box-shadow: -8px 0 24px rgba(0, 0, 0, 0.06); }

.tabbar {
  flex: none; display: flex; height: calc(var(--tabbar-h) + var(--sab)); padding-bottom: var(--sab);
  background: color-mix(in srgb, var(--canvas) 94%, transparent); box-shadow: 0 -1px 0 var(--line);
}
.tab { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; color: var(--ink-3); font-size: 11px; font-weight: 550; }
.tab .icon { width: 24px; height: 24px; }
.tab.on { color: var(--ink); font-weight: 700; }
.tab:active .icon { transform: scale(0.9); }
</style>
