import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { mockApi } from './mock/server.js';

// 浏览器开发：`npm run mock` 用 Fixtures 模拟接口；`npm run dev` 代理到真实服务。
// 手机上（Capacitor）直接请求用户填写的服务地址，不经过这里。
const target = 'https://reachapi.niuma.art';

export default defineConfig({
  plugins: [vue(), process.env.MOCK && mockApi()].filter(Boolean),
  server: {
    proxy: process.env.MOCK ? undefined : { '/api': { target, changeOrigin: true }, '/health': { target, changeOrigin: true } },
  },
});
