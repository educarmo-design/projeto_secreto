import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'node:path';

// Painel Web Profissional — build simples, sem SSR: roda inteiramente no
// navegador do profissional, autenticado via Supabase Auth + RLS (ver
// src/core/supabase.ts). Nenhuma chave de serviço/elevada é usada aqui —
// só a anon key pública, exatamente como no app mobile.
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5173,
  },
});
