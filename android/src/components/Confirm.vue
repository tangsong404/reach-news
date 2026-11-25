<script setup>
// 二次确认：标题 + 说明 + 取消 / 确认。破坏性操作用警示色。
import { watch, onBeforeUnmount } from 'vue';
import { pushBack } from '../lib/ui.js';

const props = defineProps({ open: Boolean, title: String, message: String, action: String, danger: Boolean });
const emit = defineEmits(['close', 'confirm']);
let popBack = null;
watch(
  () => props.open,
  (v) => {
    popBack?.();
    popBack = v ? pushBack(() => emit('close')) : null;
  },
  { immediate: true },
);
onBeforeUnmount(() => popBack?.());
</script>

<template>
  <Teleport to="body">
    <Transition name="fade">
      <div v-if="open" class="confirm-wrap" @click.self="emit('close')">
        <div class="confirm" role="alertdialog">
          <h3>{{ title }}</h3>
          <p v-if="message">{{ message }}</p>
          <div class="confirm-actions">
            <button class="text-btn" @click="emit('close')">{{ $t('取消') }}</button>
            <button class="text-btn strong" :class="{ danger }" @click="emit('confirm')">{{ action }}</button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style>
.confirm-wrap { position: fixed; inset: 0; z-index: 70; display: grid; place-items: center; padding: 24px; background: rgba(20, 20, 15, 0.38); }
.confirm { width: 100%; max-width: 340px; padding: 22px 22px 12px; border-radius: 20px; background: var(--surface); box-shadow: 0 20px 50px rgba(0, 0, 0, 0.2); }
.confirm h3 { margin: 0 0 8px; font-size: 18px; font-weight: 700; }
.confirm p { margin: 0; color: var(--ink-2); font-size: 14.5px; line-height: 1.55; }
.confirm-actions { display: flex; justify-content: flex-end; gap: 4px; margin-top: 16px; }
.confirm-actions .danger { color: var(--failed-fg); }
</style>
