// 下拉刷新：滚动容器在顶部时下拉超过阈值即触发。
import { ref } from 'vue';

export function usePullRefresh(scroller, onRefresh) {
  const pull = ref(0);
  let startY = null;
  return {
    pull,
    handlers: {
      touchstart(e) {
        startY = scroller.value?.scrollTop <= 0 ? e.touches[0].clientY : null;
      },
      touchmove(e) {
        if (startY === null) return;
        const d = e.touches[0].clientY - startY;
        pull.value = d > 0 ? Math.min(90, d * 0.5) : 0;
      },
      async touchend() {
        if (startY === null) return;
        startY = null;
        if (pull.value >= 60) {
          pull.value = 48;
          await onRefresh();
        }
        pull.value = 0;
      },
    },
  };
}
