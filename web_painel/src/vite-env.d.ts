/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string;
  /** N44: chave publicável (`sb_publishable_…`). Prioritária sobre a legada abaixo. */
  readonly VITE_SUPABASE_PUBLISHABLE_KEY?: string;
  /** Legado (JWT `anon`) — só fallback até o Passo 4 do N44 (desativar o par legado). */
  readonly VITE_SUPABASE_ANON_KEY?: string;
  readonly VITE_GARMIN_DISPATCH_ENDPOINT?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
