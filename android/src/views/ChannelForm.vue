<script setup>
// 新建 / 编辑频道（只有 owner == creator 的频道进入编辑）。整页一次保存，动作放顶栏。
// 编辑只提交改动字段；409 busy 时顶部提示，表单内容全部保留。
import { ref, reactive, computed, onMounted } from 'vue';
import NavBar from '../components/NavBar.vue';
import Icon from '../components/Icon.vue';
import ColorPicker from '../components/ColorPicker.vue';
import Confirm from '../components/Confirm.vue';
import {
  api, channels, createChannel, saveChannel, deleteChannel,
  effectiveColorIndex, setColor, suggestedColor, localColorIndex,
} from '../lib/store.js';
import { draftFrom, draftChanges, normalizeSchedule, WEEKDAYS, addTime, removeTime, toggleDay, MAX_TIMES_PER_DAY } from '../lib/model.js';
import { pop, toast } from '../lib/ui.js';
import { weekdayName, weekdayShort, errorText, errorDetail } from '../lib/format.js';
import { t } from '../lib/i18n.js';

const props = defineProps({ id: String });
const isEdit = !!props.id;
const original = isEdit ? channels.byId(props.id) : null;

const draft = reactive(
  original
    ? draftFrom(original)
    : { name: '', prompt: '', tone: '', schedule: normalizeSchedule({}), enabled: true, connectorIds: [] },
);
const initialColor = isEdit ? effectiveColorIndex(props.id) : suggestedColor();
const color = ref(initialColor);

const saving = ref(false);
const error = ref(null);
const validation = ref('');
const confirmDelete = ref(false);

// 新建流程需要连接器列表
const connectors = ref([]);
const connectorsError = ref(null);
onMounted(async () => {
  if (isEdit) return;
  try {
    connectors.value = await api.connectors();
  } catch (e) {
    connectorsError.value = e;
  }
});

const changes = computed(() => (original ? draftChanges(draft, original) : {}));
const dirty = computed(() =>
  isEdit ? Object.keys(changes.value).length > 0 || color.value !== initialColor : draft.name.trim() && draft.prompt.trim(),
);

function toggleConnector(id) {
  draft.connectorIds = draft.connectorIds.includes(id) ? draft.connectorIds.filter((x) => x !== id) : [...draft.connectorIds, id];
}
const onAddTime = (day, e) => {
  draft.schedule = addTime(draft.schedule, day, e.target.value);
  e.target.value = '';
};

async function submit() {
  if (!dirty.value || saving.value) return;
  validation.value = '';
  error.value = null;
  if (!isEdit && !draft.connectorIds.length) return (validation.value = t('请至少选择一个连接器'));
  saving.value = true;
  try {
    if (isEdit) {
      if (Object.keys(changes.value).length) await saveChannel(props.id, changes.value);
      // 颜色只存本机
      if (color.value !== initialColor || localColorIndex(props.id) === null) setColor(props.id, color.value);
    } else {
      await createChannel(
        {
          name: draft.name.trim(),
          prompt: draft.prompt.trim(),
          tone: draft.tone.trim(),
          schedule: draft.schedule,
          connectorIds: draft.connectorIds,
        },
        color.value,
      );
    }
    pop();
  } catch (e) {
    error.value = e; // 保留全部输入
  } finally {
    saving.value = false;
  }
}

async function doDelete() {
  confirmDelete.value = false;
  try {
    await deleteChannel(props.id);
    pop();
  } catch (e) {
    error.value = e.kind === 'busy' ? { kind: 'deleteBusy' } : e;
  }
}
</script>

<template>
  <div class="page">
    <NavBar :title="isEdit ? $t('编辑频道') : $t('新建频道')" lined>
      <template #left>
        <button class="text-btn" @click="pop()">{{ $t('取消') }}</button>
      </template>
      <template #right>
        <button class="text-btn strong" :disabled="!dirty || saving" data-testid="channel-save" @click="submit">
          {{ isEdit ? $t('保存') : $t('创建') }}
        </button>
      </template>
    </NavBar>

    <div class="page-body scroll">
      <div v-if="isEdit && !original" class="empty"><h3>{{ $t('请求的内容不存在') }}</h3></div>
      <div v-else class="page-pad form">
        <div v-if="error?.kind === 'busy'" class="banner warn" data-testid="busy-banner">
          <div><b>{{ $t('频道正在运行，暂时无法保存。') }}</b>{{ $t('结束后可修改，已填写的内容不会丢失。') }}</div>
        </div>
        <div v-else-if="error?.kind === 'deleteBusy'" class="banner warn">{{ $t('该频道有运行未结束，请等待结束后再删除。') }}</div>
        <div v-else-if="error" class="banner warn">
          <div><b>{{ errorText(error) }}</b><template v-if="errorDetail(error)"><br />{{ errorDetail(error) }}</template></div>
        </div>

        <div class="label">{{ $t('名称') }}</div>
        <input v-model="draft.name" class="field" maxlength="80" />

        <div class="label">{{ $t('频道方向') }}</div>
        <textarea v-model="draft.prompt" class="field" rows="4" />

        <div class="label">{{ $t('口吻') }}</div>
        <input v-model="draft.tone" class="field" />

        <div class="label">{{ $t('采集时间表') }}</div>
        <div class="days">
          <button
            v-for="d in WEEKDAYS"
            :key="d"
            class="day press"
            :class="{ on: draft.schedule[d].length }"
            :aria-label="weekdayName(d)"
            :aria-pressed="!!draft.schedule[d].length"
            @click="draft.schedule = toggleDay(draft.schedule, d)"
          >{{ weekdayShort(d) }}</button>
        </div>
        <div class="day-times">
          <template v-for="d in WEEKDAYS" :key="d">
            <div v-if="draft.schedule[d].length" class="day-line">
              <span class="day-name">{{ weekdayName(d) }}</span>
              <span v-for="tm in draft.schedule[d]" :key="tm" class="time-pill num">
                {{ tm }}
                <button :aria-label="$t('移除 {time}', { time: tm })" @click="draft.schedule = removeTime(draft.schedule, d, tm)"><Icon name="close" /></button>
              </span>
              <label v-if="draft.schedule[d].length < MAX_TIMES_PER_DAY" class="time-pill add">
                <Icon name="plus" />{{ $t('时间') }}
                <input type="time" :aria-label="$t('添加时间')" @change="onAddTime(d, $event)" />
              </label>
            </div>
          </template>
        </div>

        <div class="label">{{ $t('连接器') }}</div>
        <div v-if="isEdit" class="group">
          <div v-for="c in original.connectors" :key="c.id" class="row">
            <span class="grow" :class="{ unavailable: c.removed || !c.name }">{{ c.name || c.id }}</span>
          </div>
          <div v-if="!original.connectors.length" class="row"><span class="grow val">{{ $t('未选择连接器，启用后运行将不会产出日报。') }}</span></div>
        </div>
        <template v-else>
          <div v-if="connectorsError" class="banner warn">{{ errorText(connectorsError) }}</div>
          <div v-else-if="connectors.length" class="group">
            <button v-for="c in connectors" :key="c.id" class="row tap" @click="toggleConnector(c.id)">
              <span class="grow">{{ c.name }}</span>
              <span class="radio" :class="{ on: draft.connectorIds.includes(c.id) }"><Icon v-if="draft.connectorIds.includes(c.id)" name="check" /></span>
            </button>
          </div>
          <p v-else class="sub">{{ $t('还没有可用连接器') }}</p>
          <p v-if="validation" class="form-error">{{ validation }}</p>
        </template>

        <div class="label">{{ $t('标识色') }}</div>
        <div class="group"><ColorPicker v-model="color" /></div>

        <div v-if="isEdit" class="group delete-group">
          <button class="row tap danger" @click="confirmDelete = true">{{ $t('删除频道') }}</button>
        </div>
      </div>
    </div>

    <Confirm
      :open="confirmDelete"
      :title="$t('删除这个频道？')"
      :message="$t('频道会从列表消失，但已产出的日报与素材不会被删除。')"
      :action="$t('删除')"
      danger
      @close="confirmDelete = false"
      @confirm="doDelete"
    />
  </div>
</template>

<style>
.form .banner { margin-top: 8px; }
.days { display: grid; grid-template-columns: repeat(7, 1fr); gap: 6px; }
.day { height: 40px; border-radius: 10px; background: var(--surface); box-shadow: 0 0 0 1px var(--line); font-weight: 650; }
.day.on { background: var(--ink); color: var(--canvas); box-shadow: none; }
.day-times { display: flex; flex-direction: column; gap: 8px; margin-top: 10px; }
.day-line { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; }
.day-name { min-width: 44px; white-space: nowrap; font-size: 13px; color: var(--ink-3); }
.time-pill { position: relative; display: inline-flex; align-items: center; gap: 2px; height: 32px; padding: 0 4px 0 12px; border-radius: 16px; background: var(--surface); box-shadow: 0 0 0 1px var(--line); font-size: 16px; }
.time-pill button { width: 26px; height: 26px; display: grid; place-items: center; color: var(--ink-3); }
.time-pill .icon { width: 14px; height: 14px; stroke-width: 2.2; }
.time-pill.add { padding: 0 12px 0 8px; gap: 4px; color: var(--ink-2); font-family: var(--font); font-size: 13px; }
.time-pill.add input { position: absolute; inset: 0; opacity: 0; width: 100%; }
.unavailable { color: var(--ink-3); text-decoration: line-through; }
.form-error { margin: 8px 4px 0; color: var(--failed-fg); font-size: 13px; }
.delete-group { margin-top: 28px; }
</style>
