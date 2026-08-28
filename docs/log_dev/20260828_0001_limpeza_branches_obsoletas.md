# RELATÓRIO 20260828_0001 — Limpeza de branches obsoletas

**Data:** 2026-08-28
**Pedido:** "Vamos fazer o merge de todas a branch em aberto."

## Investigação

`git branch --merged main` — verificação de ancestralidade real no grafo de
commits, não estimativa — mostrou que das 4 branches locais/remotas
divergentes de `main`, **3 já estavam 100% contidas** (todo commit delas já
era ancestral do `main` atual):

- `feature/n17-n18-telemetria-persistida`
- `fix/distancia-fallback-sincronizacao`
- `fix/imc-perfil-atleta1000`

Só `feat/seed-problemas-saude` divergia de verdade — 2 commits com uma
migration (`20260812230000_seed_problemas_saude_clinicos.sql`) e seu
relatório de dev-log.

## O que foi feito

1. **`git diff main...feat/seed-problemas-saude`**: a migration já estava
   **byte-idêntica** em `main` (trazida manualmente em 19/08, RELATÓRIO
   20260819_0021, ao investigar um desalinhamento de histórico) — só o
   relatório de dev-log nunca tinha sido trazido.
2. **`git merge --no-ff feat/seed-problemas-saude`**: conflito só em
   `docs/log_dev/INDICE.md` (esperado — as duas histórias divergiram há
   16 dias). Resolvido preservando a ordem cronológica real.
3. **Achado no caminho**: a ausência dessa branch tinha deixado um buraco
   real na numeração (`20260812_0011` → `0013`, sem `0012`). O relatório
   resgatado preencheu esse buraco (renomeado de `_0011_` pra `_0012_`,
   já que `0011` tinha sido reaproveitado por outra tarefa — `fix_imc` —
   na linha que seguiu adiante sem essa branch).
4. **Deletadas as 4 branches**, local e remoto (`git branch -d` — a forma
   que RECUSA apagar qualquer coisa não mesclada, segunda checagem
   independente da verificação acima; nenhuma falhou, confirmando que a
   análise estava certa).

## Verificação

Migration idêntica confirmada via `git diff` vazio antes do merge — zero
mudança funcional no banco (já aplicada desde 19/08). Nenhum código Dart/TS
tocado nesta tarefa, só documentação e histórico de git. `git branch -a`
final: só `main` (+ `cloudflare/workers-autoconfig`, branch de integração
de plataforma, fora do escopo deste pedido — não tocada).
