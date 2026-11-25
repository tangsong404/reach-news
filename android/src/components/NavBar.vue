<script setup>
// 页面顶栏：左侧返回圆钮（或自定义），中间标题，右侧动作。
import Icon from './Icon.vue';
import { pop } from '../lib/ui.js';
defineProps({ title: String, back: { type: Boolean, default: true }, lined: Boolean });
</script>

<template>
  <header class="bar" :class="{ lined }">
    <slot name="left">
      <button v-if="back" class="icon-btn" :aria-label="$t('返回')" @click="pop()"><Icon name="back" /></button>
    </slot>
    <div class="bar-title"><slot name="title"><span>{{ title }}</span></slot></div>
    <span class="bar-spacer" />
    <slot name="right" />
  </header>
</template>
