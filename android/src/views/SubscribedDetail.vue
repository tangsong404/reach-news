<script setup>
// 订阅频道详情：只读。fork / 取消订阅在顶栏菜单里（各需二次确认）；改颜色是页面内的普通行。
import { ref, computed } from 'vue';
import NavBar from '../components/NavBar.vue';
import Icon from '../components/Icon.vue';
import Sheet from '../components/Sheet.vue';
import Confirm from '../components/Confirm.vue';
import ColorPicker from '../components/ColorPicker.vue';
import { channels, colorFor, colorIndexFor, updateSubscriptionColor, unsubscribe, forkChannel } from '../lib/store.js';
import { PALETTE, paletteIndex } from '../lib/model.js';
import { pop, replaceTop } from '../lib/ui.js';
import { describeSchedule, monthDayTime, errorText, errorDetail } from '../lib/format.js';

const props = defineProps({ id: String });
const channel = computed(() => channels.byId(props.id));

const menuOpen = ref(false);
const colorOpen = ref(false);
const confirm = ref(null); // 'fork' | 'unsubscribe'
const busy = ref(false);
const error = ref(null);

const colorName = computed(() => {
  const i = paletteIndex(channel.value?.subscriptionColor);
  return i === null ? null : PALETTE[i].zh;
});

async function run(fn) {
  if (busy.value) return;
  busy.value = true;
  error.value = null;
  try {
    await fn();
  } catch (e) {
    error.value = e;
  } finally {
    busy.value = false;
  }
}

const pickColor = (i) =>
  run(async () => {
    colorOpen.value = false;
    await updateSubscriptionColor(props.id, i);
  });

function doConfirm() {
  const action = confirm.value;
  confirm.value = null;
  if (action === 'unsubscribe') run(async () => (await unsubscribe(props.id), pop()));
  else run(async () => {
    const created = await forkChannel(props.id);
    replaceTop('channelForm', { id: created.id });
  });
}
</script>

<template>
  <div class="page">
    <NavBar :title="$t('订阅频道')">
      <template #right>
        <button v-if="channel" class="icon-btn" :aria-label="$t('更多')" @click="menuOpen = true"><Icon name="more" /></button>
      </template>
    </NavBar>

    <div class="page-body scroll">
      <div v-if="!channel" class="empty"><h3>{{ $t('请求的内容不存在') }}</h3></div>
      <div v-else class="page-pad">
        <div v-if="error" class="banner warn">
          <div><b>{{ errorText(error) }}</b><template v-if="errorDetail(error)"><br />{{ errorDetail(error) }}</template></div>
        </div>
        <div class="sub-head">
          <span class="dot big" :style="{ background: colorFor(channel) }" />
          <h1>{{ channel.name }}</h1>
        </div>

        <div class="label">{{ $t('频道方向') }}</div>
        <div class="group"><div class="row ro">{{ channel.prompt }}</div></div>

        <div class="label">{{ $t('口吻') }}</div>
        <div class="group"><div class="row ro">{{ channel.tone || $t('未设置') }}</div></div>

        <div class="label">{{ $t('采集时间表') }}</div>
        <div class="group"><div class="row ro">{{ describeSchedule(channel.schedule) }}</div></div>

        <div class="label">{{ $t('连接器') }}</div>
        <div class="group">
          <div v-for="c in channel.connectors" :key="c.id" class="row ro">{{ c.name || c.id }}</div>
          <div v-if="!channel.connectors.length" class="row ro val">—</div>
        </div>

        <template v-if="channel.lastBriefAt">
          <div class="label">{{ $t('最近日报') }}</div>
          <div class="group"><div class="row ro num">{{ monthDayTime(channel.lastBriefAt) }}</div></div>
        </template>

        <div class="label">{{ $t('标识色') }}</div>
        <div class="group">
          <button class="row tap" :disabled="busy" @click="colorOpen = true">
            <span class="grow">{{ $t('订阅色') }}</span>
            <span class="dot" :style="{ background: colorFor(channel) }" />
            <span v-if="colorName" class="val">{{ $t(colorName) }}</span>
            <Icon name="chevron" />
          </button>
        </div>
      </div>
    </div>

    <Sheet :open="menuOpen" @close="menuOpen = false">
      <div class="menu">
        <button class="row tap" @click="(menuOpen = false), (confirm = 'fork')">{{ $t('复制成我的频道') }}</button>
        <button class="row tap danger-text" @click="(menuOpen = false), (confirm = 'unsubscribe')">{{ $t('取消订阅') }}</button>
      </div>
    </Sheet>

    <Sheet :open="colorOpen" @close="colorOpen = false">
      <div class="menu"><ColorPicker :model-value="channel ? colorIndexFor(channel) : 0" @update:model-value="pickColor" /></div>
    </Sheet>

    <Confirm
      :open="confirm === 'fork'"
      :title="$t('复制成我的频道？')"
      :message="$t('会复制名称、频道方向、口吻、时间表与连接器，并取消当前订阅。原频道不变。')"
      :action="$t('复制成我的频道')"
      @close="confirm = null"
      @confirm="doConfirm"
    />
    <Confirm
      :open="confirm === 'unsubscribe'"
      :title="$t('取消订阅这个频道？')"
      :message="$t('取消后它和它的日报会立即从你的列表消失。频道与已发布日报不会被删除。')"
      :action="$t('取消订阅')"
      danger
      @close="confirm = null"
      @confirm="doConfirm"
    />
  </div>
</template>

<style>
.sub-head { display: flex; align-items: center; gap: 10px; margin: 8px 0 4px; }
.sub-head h1 { margin: 0; font-size: 26px; font-weight: 800; line-height: 1.25; }
.dot.big { width: 12px; height: 12px; }
.row.ro { font-size: 15px; line-height: 1.55; user-select: text; -webkit-user-select: text; }
.row .icon { width: 18px; height: 18px; color: var(--ink-3); }
.menu { padding: 0 12px 12px; }
.menu .row { border-radius: 12px; font-size: 16px; }
.danger-text { color: var(--failed-fg); }
</style>
