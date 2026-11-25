<script setup>
// 登录：账号密码换 7 天会话凭证。失败不写入任何凭证；429 本地冷却、禁用提交、不自动重试。
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { state, login, signIn, throttleSeconds } from '../lib/store.js';
import { errorText, errorDetail } from '../lib/format.js';

const base = ref(state.prefs.baseURL.replace(/^https:\/\//, ''));
const username = ref('');
const password = ref('');

let tick;
onMounted(() => (tick = setInterval(() => (login.now = Date.now()), 1000)));
onBeforeUnmount(() => clearInterval(tick));

const throttled = computed(() => throttleSeconds.value > 0);
const canSubmit = computed(() => username.value.trim() && password.value && !login.busy && !throttled.value);

async function submit() {
  if (!canSubmit.value) return;
  login.now = Date.now();
  const ok = await signIn(base.value, username.value, password.value);
  // 密码只在提交时使用，结束后立即从内存清空
  password.value = '';
  if (ok) username.value = '';
}
</script>

<template>
  <div class="login scroll">
    <form class="login-inner" @submit.prevent="submit">
      <img class="login-mark" src="/logo-mark.png" alt="" />
      <h1>{{ $t('连接到 Reach News') }}</h1>

      <label class="label" for="base">{{ $t('服务地址') }}</label>
      <input id="base" v-model="base" class="field" inputmode="url" autocapitalize="off" autocomplete="off" spellcheck="false" placeholder="reachapi.niuma.art" />

      <label class="label" for="user">{{ $t('账号') }}</label>
      <input id="user" v-model="username" class="field" autocapitalize="off" autocomplete="username" spellcheck="false" :placeholder="$t('管理员分配的用户名')" />

      <label class="label" for="pass">{{ $t('密码') }}</label>
      <input id="pass" v-model="password" class="field" type="password" autocomplete="current-password" :placeholder="$t('密码')" />

      <div v-if="throttled" class="banner warn login-msg">
        <div>
          <b>{{ $t('尝试次数过多') }}</b><br />
          {{ $t('同一账号 5 分钟内失败过多会暂时锁定，此时即使密码正确也会被拒绝。') }}
          {{ $t('请等待 {n} 秒后再试。期间不会自动重试，以免延长锁定。', { n: throttleSeconds }) }}
        </div>
      </div>
      <div v-else-if="login.error" class="banner warn login-msg">
        <div>
          <b>{{ errorText(login.error) }}</b>
          <template v-if="errorDetail(login.error)"><br />{{ errorDetail(login.error) }}</template>
        </div>
      </div>

      <button class="submit press" type="submit" :disabled="!canSubmit">
        <span v-if="login.busy" class="spinner light" />
        {{ login.busy ? $t('正在登录…') : $t('登录') }}
      </button>
    </form>
  </div>
</template>

<style>
.login { height: 100%; background: var(--canvas); }
.login-inner { max-width: 440px; margin: 0 auto; padding: calc(var(--sat) + 56px) 24px calc(var(--sab) + 40px); }
.login-mark { width: 52px; height: 52px; border-radius: 14px; display: block; }
.login h1 { margin: 18px 0 18px; font-size: 28px; font-weight: 800; line-height: 1.2; }
.login-msg { margin-top: 18px; }
.submit { width: 100%; height: 52px; margin-top: 26px; border-radius: 14px; background: var(--ink); color: var(--canvas); font-size: 17px; font-weight: 700; display: flex; align-items: center; justify-content: center; gap: 10px; }
.submit:disabled { opacity: 0.35; }
.spinner.light { border-color: rgba(255, 255, 255, 0.3); border-top-color: #fff; width: 18px; height: 18px; }
</style>
