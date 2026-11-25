import { createApp, watchEffect } from 'vue';
import './style.css';
import App from './App.vue';
import { initStore, state } from './lib/store.js';
import { applyLang, t } from './lib/i18n.js';

initStore().then(() => {
  watchEffect(() => applyLang(state.prefs.lang));
  const app = createApp(App);
  app.config.globalProperties.$t = t;
  app.mount('#app');
});
