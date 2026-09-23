# RELATÓRIO 20260918_0003 — Painel Web: MACRO-003/004/005 e Tabela de Déficit Multicritério no `MotorMetabolicoV1Card`/`PrescricaoView`

**Branch:** `feat/web-motor-macros-final` (a partir de `main`, que já contém o RELATÓRIO `20260920_0001`).
**Data:** 2026-09-18.

## Nota sobre a numeração/data

O relatório anterior (`20260920_0001_motor_macros_deficit_final.md`, já mesclado em `main`) foi nomeado com a data `20260920`, dois dias à frente da data real do sistema (`Get-Date` confirma `2026-09-18` no momento em que este relatório é escrito). O nome do arquivo e a migration correspondente (`20260920100000...`) já estão aplicados em produção e mesclados — não foram renomeados retroativamente (evitar dessincronizar `supabase migration list`). Este relatório usa a data real (`20260918`), próxima sequência livre daquele dia (`0003`, depois de `0001`/`0002`).

## Contexto

O Backend e o Flutter já entregavam os 5 protocolos de macros e a tabela de déficit multicritério (RELATÓRIO `20260920_0001`). Esta tarefa é 100% Painel Web (React) — `ARQUIVOS`/`RESTRIÇÕES` explícitos: nenhum código de Backend ou Flutter foi tocado.

## 1. `MotorMetabolicoV1Card.tsx`

- **MACRO-003**: novo bloco na grade de macros. Quando `macro_003.disponivel === true`, renderiza como os demais (P/C/G + validação de soma). Quando `false` (sem `massa_magra_kg` na anamnese), renderiza um card de aviso amarelo explícito ("Indisponível: falta massa magra...") em vez de omitir silenciosamente o protocolo — o profissional sempre vê que o protocolo existe e por que não está calculado agora.
- **MACRO-004**: novo bloco, mesmo padrão de `BlocoMacro` dos demais.
- **MACRO-005**: card informativo (sem gramas — por definição é o profissional quem define os valores), apontando para a seção de Prescrição onde a validação ao vivo acontece.
- Grade de macros passa de `sm:grid-cols-2` para `sm:grid-cols-2 lg:grid-cols-3` (agora com até 5 cards).
- **Avisos**: `ROTULO_AVISO` ganha 8 entradas novas (`macro_003_sem_massa_magra_kg_disponivel`, `macro_004_carboidrato_negativo_...`, `deficit_sem_rotina_diaria_usando_padrao_moderado`, `deficit_limitado_pelo_piso_da_tmb`, etc.) — antes desses códigos apareceriam crus (fallback `ROTULO_AVISO[aviso] ?? aviso`), agora traduzidos.
- **Fatores do déficit multicritério**: dentro do card "Recomendação do sistema", um `<details>` colapsável ("Como o sistema chegou nesse percentual") lista os 6 fatores — nível de atividade (traduzido via `ROTULO_NIVEL_ATIVIDADE`), percentual base, os 3 ajustes (TDEE/condição/qualidade dos dados), percentual final após os limites de 5–20%, teto de déficit por peso, déficit aplicado em kcal e se o piso da TMB foi acionado. Só aparece quando `fatores_considerados` não é `null` (ou seja, só na estratégia de déficit, nunca na manutenção).

## 2. `PrescricaoView.tsx` — MACRO-005 ao vivo

- Novo `useEffect` (debounce de 400ms) que, **só no modo "Meta única"** (o único com uma Calorias inequívoca para comparar contra P/C/G — no modo "por dia da semana" cada dia teria seu próprio alvo, fora do escopo desta tarefa e documentado como tal), chama `validar_macro_personalizado` sempre que Calorias/Proteína/Carboidrato/Gordura estão todos preenchidos com números válidos.
- Banner visual logo abaixo dos campos: cinza "Validando..." enquanto a chamada está em voo; verde "✓ Consistente" quando `valido: true`; vermelho "✕ Inconsistente" com a soma calculada e a diferença exata quando `valido: false`.
- **Nunca bloqueia o salvamento** — mesmo espírito já estabelecido para o caminho profissional em `validar_e_salvar_meta`/N08 ("uma violação clínica NUNCA impede o salvamento... o profissional decide, o Motor só avisa"). O texto do banner vermelho deixa isso explícito: "A prescrição pode ser salva mesmo assim — revise os valores antes de confirmar."

## 3. Tipos (`database.ts`)

- `MotorMetabolicoV1Resultado.energia_recomendacao` ganha `fatores_considerados` (os mesmos 9 campos que a migration `20260920100000` devolve — nomes conferidos campo a campo contra o `jsonb_build_object` da função no banco, para eliminar erro silencioso de digitação).
- `MotorMetabolicoV1Resultado.macros_recomendados` ganha `macro_003` (incluindo `disponivel`/`massa_magra_kg`/`massa_magra_data_medicao`), `macro_004` e `macro_005`.
- Nova entrada em `Functions`: `validar_macro_personalizado` (Args/Returns espelhando exatamente a RPC pura do backend).

## 4. Verificação

- `npx tsc -b`: limpo.
- `npm run build`: limpo (vite build completo, sem erros).
- `npm run lint`: 2 warnings pré-existentes em `scripts/seed_taco_completa.ts` (arquivo não tocado nesta tarefa) — zero warning novo nos arquivos alterados.
- Nomes de campo do JSON (`fatores_considerados.*`, `macro_003.*`, `macro_004.*`, `macro_005.*`) conferidos linha a linha contra o `jsonb_build_object` da migration `20260920100000` (Backend, já em produção) — nenhuma divergência.
- Backend não foi tocado (`RESTRIÇÕES` explícitas) — a matemática dos protocolos/déficit já foi verificada ao vivo no RELATÓRIO `20260920_0001` e continua válida.

## Fora do escopo desta tarefa (documentado, não esquecido)

- No modo "Meta por dia da semana" de `PrescricaoView.tsx`, a validação ao vivo do MACRO-005 não roda (não há uma única Calorias para comparar) — decisão de escopo, não esquecimento.
- `validar_macro_personalizado` não bloqueia o salvamento por design (mesmo espírito de N08 no caminho profissional) — se o fundador quiser bloqueio duro no futuro, é uma decisão de produto separada.
