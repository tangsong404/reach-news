<script setup>
// 12 色色板（订阅色与本机标识色共用）。
import { PALETTE } from '../lib/model.js';
import Icon from './Icon.vue';
defineProps({ modelValue: Number });
const emit = defineEmits(['update:modelValue']);
</script>

<template>
  <div class="swatches">
    <button
      v-for="(c, i) in PALETTE"
      :key="c.key"
      class="swatch press"
      :style="{ background: c.hex }"
      :aria-label="$t(c.zh)"
      :aria-pressed="modelValue === i"
      @click="emit('update:modelValue', i)"
    ><Icon v-if="modelValue === i" name="check" /></button>
  </div>
</template>

<style>
.swatches { display: grid; grid-template-columns: repeat(6, 1fr); gap: 12px; padding: 14px 16px; }
.swatch { aspect-ratio: 1; border-radius: 50%; display: grid; place-items: center; color: #fff; }
.swatch .icon { width: 20px; height: 20px; stroke-width: 2.6; }
</style>
