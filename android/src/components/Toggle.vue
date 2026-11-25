<script setup>
defineProps({ modelValue: Boolean, disabled: Boolean, label: String });
const emit = defineEmits(['update:modelValue']);
</script>

<template>
  <button
    class="toggle"
    :class="{ on: modelValue }"
    role="switch"
    :aria-checked="modelValue"
    :aria-label="label"
    :disabled="disabled"
    @click.stop="emit('update:modelValue', !modelValue)"
  ><i /></button>
</template>

<style>
.toggle { position: relative; flex: none; width: 46px; height: 28px; border-radius: 14px; background: var(--line-strong); transition: background 0.2s; }
.toggle i { position: absolute; top: 3px; left: 3px; width: 22px; height: 22px; border-radius: 50%; background: #fff; box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2); transition: transform 0.25s var(--ease); }
.toggle.on { background: var(--ink); }
.toggle.on i { transform: translateX(18px); }
.toggle:disabled { opacity: 0.5; }
</style>
