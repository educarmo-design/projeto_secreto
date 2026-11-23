# 20261123_0003 — N45: tratar HTTP 402 (saldo/faturamento) do Gemini

**Data:** 2026-11-23
**Branch:** `feat/n45-tratar-http-402-gemini` (a partir de `main` em `87ebd22`, com o PR #27 já mesclado)
**Persona:** Backend (Edge Functions) + Flutter (Mestre v9.2.1 — Parte 0 regras 15, 16, 17, 21, 22, 23, 24, 25, 27; Parte 11.10 decisão 93; Parte 12.2 risco R44; Parte V1 N45)

## Fechamento do PR #27 (decisão 96)

PR #27 (N43 Etapa 2) mesclado em `main` (`87ebd22`) após teste do fundador no aparelho. Registro também no log `20261123_0002`, junto com a pendência futura da regra de cochilo (Bloco 1½: maior bloco ≥ 180 min, mínimo configurável em `configuracoes_sistema`; vazio só se dois blocos ≥ 180 min ou nenhum atingir o mínimo) — **não implementada**.

## Contexto

Com o faturamento pré-pago do Gemini, o saldo zerado passa a ser um erro real: a API devolve **HTTP 402**. O saldo pertence à conta de faturamento, então CORE e LITE (e a busca por embedding) falham igual. Antes, um 402 caía no ramo genérico (`ErroHttp 502`, "Falha ao analisar a imagem.") e, no cliente, aparecia como "Erro no servidor" — uma mensagem que não diz a causa (regras 15/23).

## O que mudou

**Backend (`supabase/functions/extract-metric-photo/index.ts`)**
- Nova classe `ErroSaldoGemini extends ErroHttp` (status 402), no mesmo padrão de `ErroCotaGemini` (429).
- `criarChamadorGeminiReal`: 402 lança na hora — **1 única tentativa, sem retry**.
- `criarChamadorGeminiComFallback`: `ErroSaldoGemini` é relançado — **nunca cai no modelo LITE** (decisão 93).
- `criarChamadorEmbeddingReal`: 402 vira `ErroSaldoGemini`; em `processarPratoRefeicao` a busca semântica **não engole** esse erro (a degradação graciosa continua valendo para os demais erros; saldo esgotado falha visível — regra 23).
- Handler: 402 responde HTTP 402 com mensagem própria sobre pendência de faturamento/créditos da plataforma.
- Regra 22: log `CONCLUSÃO` agora inclui `request_id`; a resposta ecoa `X-Request-Id` (o do cliente ou um gerado); CORS libera/expõe `x-request-id`.

**Backend (`supabase/functions/search-food/index.ts`)** — tocada porque também chama o Gemini (embedding): `ErroSaldoGemini`, 402 → HTTP 402 com a mesma mensagem; regra 22 (wrapper com log `CONCLUSÃO` + eco de `X-Request-Id`, que antes não existia nesta função).

**Flutter**
- `camera_capture_controller.dart` (foto de prato/visores/rótulo): status 402 usa a chave i18n `dashboard.camera_saldo_ia_indisponivel` (pt/en/es), com prioridade sobre o resto; a tela fica aberta em estado de erro (sem `pushReplacement`, sem fechar — regra 25). Comentário desatualizado sobre os status do backend corrigido (regra 27).
- `registro_refeicao_ia_service.dart` (áudio e texto): mesmo tratamento, constante `mensagemSaldoIaIndisponivel`.
- Busca de alimentos (`food_search_service.dart`) não precisou de código: já exibe a mensagem do corpo do backend em qualquer status.

## Mensagem exibida

"O serviço de análise por IA está temporariamente indisponível por uma pendência de faturamento/créditos da plataforma. Não é um problema no seu aparelho nem na sua conta. Você pode registrar manualmente por enquanto." (sem linguagem de alerta.)

## Verificação

- `deno test` em `extract-metric-photo`: 139 passam (7 novos N45: 402 → 1 chamada, sem retry, erro `ErroSaldoGemini` status 402 (não 429/502); com fallback configurado o modelo LITE **nunca** é chamado; sem fallback também 1 tentativa; embedding 402; handler 402 com mensagem de faturamento e sem "ocupado"; prato → 402; eco de `X-Request-Id`).
- `deno test` em `search-food`: 18 passam (2 novos: 402 → HTTP 402 com 1 chamada e eco de `X-Request-Id`; toda resposta ganha `X-Request-Id`). `deno check` das duas funções OK.
- `flutter test`: **622 passam** (2 novos no serviço de refeição por IA: 402 com corpo e 402 sem corpo → mensagem própria, 1 chamada, sem "ocupado"). `flutter analyze`: 30 issues (= teto do CI).
- Deploy: `supabase functions deploy extract-metric-photo` e `supabase functions deploy search-food` executados com sucesso (projeto `xtipphglpqqrjguxcajn`).
- **Não verificado:** um 402 real do Gemini (não há como provocar sem zerar o saldo) e o fluxo na tela do aparelho; a cobertura é por testes automatizados com resposta simulada. Não há teste automatizado do `CameraCaptureController` (não existia suíte dele; a mudança dele é uma ramificação de 3 linhas, coberta só por `flutter analyze` e pelo teste equivalente do serviço de refeição).

## Arquivos

Alterados: `supabase/functions/extract-metric-photo/index.ts`, `supabase/functions/extract-metric-photo/index_test.ts`, `supabase/functions/search-food/index.ts`, `supabase/functions/search-food/index_test.ts`, `lib/features/dashboard/presentation/controllers/camera_capture_controller.dart`, `lib/features/nutrition/data/services/registro_refeicao_ia_service.dart`, `test/features/nutrition/data/services/registro_refeicao_ia_service_test.dart`, `assets/i18n/{pt,en,es}.json`, log `20261123_0002` (mesclagem + pendência) e este log + `INDICE.md`.
