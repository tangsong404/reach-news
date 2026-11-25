<script setup>
import { toastState } from '../lib/ui.js';
</script>

<template>
  <Transition name="toast">
    <div v-if="toastState.text" :key="toastState.id" class="toast" role="status">{{ toastState.text }}</div>
  </Transition>
</template>

<style>
.toast {
  position: fixed; left: 16px; right: 16px; bottom: calc(var(--tabbar-h) + var(--sab) + 14px); z-index: 90;
  max-width: 480px; margin: 0 auto; padding: 13px 18px; border-radius: 14px;
  background: var(--ink); color: var(--canvas); font-size: 14.5px; line-height: 1.4;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.22);
}
.toast-enter-active { transition: transform 0.4s var(--ease), opacity 0.25s; }
.toast-leave-active { transition: transform 0.25s var(--ease), opacity 0.2s; }
.toast-enter-from { transform: translateY(20px); opacity: 0; }
.toast-leave-to { transform: translateY(10px); opacity: 0; }
</style>
