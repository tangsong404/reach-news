<script setup>
// 底部弹窗：进出动画、拖动把手下滑关闭、接入安卓返回键、跟随键盘上移（写法同可及清单）。
import { ref, watch, onBeforeUnmount } from 'vue';
import { pushBack } from '../lib/ui.js';

const props = defineProps({ open: Boolean, maxHeight: { type: String, default: '88dvh' } });
const emit = defineEmits(['close']);

let popBack = null;
watch(
  () => props.open,
  (v) => {
    popBack?.();
    popBack = v ? pushBack(() => emit('close')) : null;
    if (!v && document.activeElement?.closest?.('.sheet')) document.activeElement.blur();
  },
  { immediate: true },
);
onBeforeUnmount(() => popBack?.());

const dragY = ref(0);
const dragging = ref(false);
let start = null;
function down(e) {
  if (!e.target.closest('[data-drag]')) return;
  start = { y: e.clientY, t: performance.now() };
  dragging.value = true;
  try {
    e.currentTarget.setPointerCapture(e.pointerId);
  } catch {
    /* 指针已抬起 */
  }
}
function move(e) {
  if (!start) return;
  const d = e.clientY - start.y;
  dragY.value = d > 0 ? d : -Math.sqrt(-d) * 2;
}
function up() {
  if (!start) return;
  const v = dragY.value / (performance.now() - start.t);
  start = null;
  dragging.value = false;
  if (dragY.value > 110 || (v > 0.5 && dragY.value > 20)) emit('close');
  dragY.value = 0;
}
</script>

<template>
  <Teleport to="body">
    <Transition name="fade">
      <div v-if="open" class="sheet-backdrop" @click="emit('close')" />
    </Transition>
    <Transition name="sheet">
      <div
        v-if="open"
        class="sheet"
        :class="{ dragging }"
        :style="{ '--drag': dragY ? `${dragY}px` : undefined, maxHeight: `calc(${maxHeight} - var(--kb, 0px))` }"
        role="dialog"
        @pointerdown="down"
        @pointermove="move"
        @pointerup="up"
        @pointercancel="up"
      >
        <div class="sheet-grip" data-drag><i /></div>
        <slot />
      </div>
    </Transition>
  </Teleport>
</template>

<style>
.sheet-backdrop { position: fixed; inset: 0; z-index: 50; background: rgba(20, 20, 15, 0.38); }
.sheet {
  position: fixed; left: 0; right: 0; bottom: 0; z-index: 51; max-width: 640px; margin: 0 auto;
  display: flex; flex-direction: column; background: var(--canvas);
  border-radius: 22px 22px 0 0; padding-bottom: var(--sab);
  box-shadow: 0 -8px 40px rgba(0, 0, 0, 0.12);
  translate: 0 calc(var(--drag, 0px) - var(--kb, 0px));
  transition: translate 0.3s cubic-bezier(0.2, 0, 0, 1);
}
.sheet.dragging, .kb-snap .sheet { transition: none; }
.sheet-grip { flex: none; height: 22px; display: grid; place-items: center; touch-action: none; }
.sheet-grip i { width: 38px; height: 5px; border-radius: 3px; background: var(--line-strong); }
.sheet-enter-from, .sheet-leave-to { transform: translateY(100%); }
.sheet-enter-active { transition: transform 0.42s var(--ease); }
.sheet-leave-active { transition: transform 0.3s var(--ease); }
</style>
