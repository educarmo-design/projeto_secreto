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
  build: {
    // Esbuild é o minificador padrão do Vite (mais rápido que Terser) —
    // deixado explícito em vez de confiar no default silencioso, para que
    // uma futura mudança de default do Vite não afrouxe isto sem ninguém
    // notar.
    minify: 'esbuild',
    rollupOptions: {
      output: {
        // Code Splitting de dependências pesadas: separa cada uma em seu
        // próprio arquivo, para que:
        //  1. o navegador baixe os 3 chunks de vendor + o chunk da tela em
        //     paralelo, em vez de esperar um bundle único e monolítico;
        //  2. como o vendor code muda com muito menos frequência que
        //     src/**, o navegador do médico/seguradora reaproveita esses
        //     chunks do cache em cada novo deploy que só mexe em código de
        //     tela — menos bytes re-baixados por sessão de trabalho, o que
        //     é exatamente o espírito de Custo Zero aplicado a hospedagem
        //     estática (menos tráfego servido = mais folga dentro do
        //     limite gratuito do host).
        manualChunks: {
          'vendor-react': ['react', 'react-dom', 'react-router-dom'],
          'vendor-supabase': ['@supabase/supabase-js'],
          'vendor-charts': ['recharts'],
        },
      },
    },
  },
  // `legalComments: 'none'` garante que nem comentários de licença/banner
  // (que o esbuild preserva por padrão, mesmo minificando) sobrevivam ao
  // build de produção — zero comentário de qualquer tipo no JS servido.
  esbuild: {
    legalComments: 'none',
  },
});
