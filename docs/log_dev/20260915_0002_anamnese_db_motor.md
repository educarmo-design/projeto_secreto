# RELATÓRIO 20260915_0002 — Fundação de Dados: Anamnese, Rotina Semanal, Sugestão vs Meta

**Data**: 2026-09-15
**Branch**: `feat/anamnese-db-motor` (a partir de `main`)
**Referências**: Documento Mestre v8.0. Tarefa 100% backend/banco — nenhum arquivo Flutter tocado (restrição explícita da tarefa).

## Contexto

O fundador definiu novas regras para Anamnese Nutricional e Metas, e pediu que o banco/backend fosse preparado ANTES de qualquer mudança no Flutter. 4 itens pedidos; 2 já existiam (auditados, não recriados), 2 exigiram schema novo + 1 RPC nova.

## Parte 0 — Auditoria: o que já existia (sem migration necessária)

Antes de desenhar qualquer coisa, investiguei o schema atual pra não duplicar trabalho:

- **Altura/peso/sexo no perfil**: `perfis_usuarios.altura_cm` (desde 20260811130000), `perfis_usuarios.peso_kg` (autodeclarado no cadastro, desde 20260722120000) e `perfis_usuarios.sexo_biologico` (ENUM M/F, desde 20260812100000) — os 3 já existem e já são exatamente os insumos que `calcular_motor_metabolico` consulta. Só reforcei o `comment on column` de 2 deles (peso/altura) deixando explícito o papel de cada um no Motor — nenhuma coluna nova.
- **Alergias (catálogo + relacional pra múltiplas)**: `alergias` (catálogo, 20260811210000) + `usuario_alergias` (N:N direto no perfil) + `anamneses_alergias` (N:N versionado por preenchimento de anamnese, 20260811240000) já cobrem exatamente o pedido. Nenhuma tabela nova.

## Parte 1 — Rotina por Dia da Semana (schema novo, aditivo)

**Achado**: `anamneses_atividades` (já existente) é N:N anamnese×atividade, mas só tem 1 linha por par com `minutos_diarios` — um número único aplicado implicitamente a TODOS os dias da semana. Não representa "corro 30min seg/qua/sex, mas 60min domingo", nem distingue dias sem atividade nenhuma.

**Decisão** (respeitando a Restrição "não tocar no Flutter"): o app já grava linhas em `anamneses_atividades` hoje, sem nenhuma noção de dia da semana — alterar sua PK/colunas quebraria esse INSERT em produção até uma tarefa futura atualizar o Flutter. Em vez disso, criei uma tabela nova e **aditiva**, `anamneses_atividades_dias` — `anamneses_atividades` fica 100% intacta, zero risco pro app atual.

```sql
create table anamneses_atividades_dias (
  anamnese_id uuid references anamneses (id) on delete cascade,
  atividade_id smallint references tipos_atividades_fisicas (id),
  dia_semana smallint check (dia_semana between 0 and 6), -- 0=domingo..6=sábado (convenção Postgres dow)
  minutos int check (minutos > 0 and minutos <= 1440),
  primary key (anamnese_id, atividade_id, dia_semana)
);
```

Permite múltiplas atividades no mesmo dia (várias linhas com o mesmo `dia_semana`) e a mesma atividade com durações diferentes em dias diferentes. RLS idêntica a `anamneses_atividades` (dono ou profissional vinculado ativo lê; só o dono escreve/apaga).

## Parte 2 — Sugestão vs Meta (`sugestao_meta`, nova tabela)

**Achado**: `objetivos_alimentares` (já existente) já é a meta REAL do usuário, versionada, INSERT-only via `validar_e_salvar_meta`. Mas o output do Motor Metabólico (`calcular_motor_metabolico`) nunca era persistido — era calculado ao vivo e devolvido, sem deixar rastro nenhum.

Criei `sugestao_meta`: uma linha por rodada do motor, com o resultado bruto completo (`motor_resultado`), o detalhe por dia da semana (`detalhe_por_dia`, jsonb chaveado "0".."6") e a **média** como coluna própria (`tdee_medio`) — os dois conceitos pedidos pelo fundador ficam explícitos, sem precisar parsear jsonb pra achar a média. Versionamento idêntico ao de `anamneses`/`objetivos_alimentares` (trigger `before insert`, no máximo 1 'ativo' por usuário, histórico preservado com `gerado_em`). **Sem policy de INSERT/UPDATE para `authenticated`** — só a RPC (`security definer`) grava, mesmo padrão de `objetivos_alimentares`.

## Parte 3 — Motor Metabólico: `gerar_sugestao_meta` (RPC nova, não modifica a existente)

`calcular_motor_metabolico` tem 3 consumidores reais em produção (`validar_e_salvar_meta`, o App Flutter via `meta_bem_estar_repository.dart`, o Painel Web via `MotorMetabolicoCard.tsx`/`InserirMedicaoModal.tsx`) — mudar seu contrato quebraria os 3. Por isso criei uma função **nova**, `gerar_sugestao_meta(p_usuario_id uuid)`, que:

1. Chama `calcular_motor_metabolico` internamente (reaproveita TMB/gasto_sedentario/tef/insumos — zero duplicação de fórmula).
2. Itera os 7 dias da semana: usa `anamneses_atividades_dias` quando a anamnese ativa tem rotina detalhada por dia; senão cai no fallback uniforme de `anamneses_atividades.minutos_diarios` (o mesmo cálculo que o motor original já fazia sozinho — compatibilidade total pra quem ainda não tem rotina detalhada).
3. Grava o resultado em `sugestao_meta`.
4. **Nunca** chama `validar_e_salvar_meta` nem escreve em `objetivos_alimentares` — confirmado por teste ao vivo (ver Verificação).

## Achados de bug — encontrados testando ao vivo, corrigidos antes de fechar

Apliquei a migration no banco remoto (`supabase db push`) e testei contra um usuário real (`atleta1000@teste.com`) autenticado de verdade (magic link + troca de token via Admin API — não service_role, que não passaria no guard de `auth.uid()` da função). Comparando a saída de `gerar_sugestao_meta` com o baseline de `calcular_motor_metabolico`, achei 2 bugs reais na 1ª versão:

1. **Aviso duplicado**: `avisos` saía `["sem_anamnese_ativa", "sem_anamnese_ativa"]` — eu copiava os avisos do motor original E adicionava o mesmo aviso de novo, sem perceber que `calcular_motor_metabolico` já o inclui sozinho.
2. **`tdee` sempre `null` nos 7 dias mesmo com `gasto_sedentario` conhecido**: tratava "sem peso" (motor genuinamente não sabe o gasto de atividade → `null`, correto) e "com peso mas sem anamnese" (gasto de atividade CONHECIDO como zero → `0`, não `null`) da mesma forma — o motor original distingue os dois casos exatamente assim; minha 1ª versão não, e isso zerava o `tdee` de todos os 7 dias sempre que faltava anamnese, mesmo quando `calcular_motor_metabolico` já devolvia um TDEE real (`gasto_sedentario + 0`).

Corrigi os dois, reapliquei a migration e testei de novo — bate exatamente com o baseline (`tdee_medio` idêntico ao `tdee` do motor original quando sem rotina).

## Achado de idempotência — corrigido durante a própria verificação

Reaplicar a migration corrigida (via `supabase migration repair --status reverted` + `db push`, necessário porque o CLI já marcava a versão como aplicada) revelou que `create policy` **não é idempotente por padrão** no Postgres (sem `drop policy if exists` antes, falha com "policy already exists" numa 2ª execução) — as tabelas (`create table if not exists`) e o índice já estavam corretos, mas as 5 policies novas não tinham a guarda. Corrigido com `drop policy if exists` antes de cada `create policy`. **Testado de verdade**: rodei a migration 3 vezes seguidas (repair → push → repair → push) sem nenhum erro na 2ª/3ª rodada — idempotência confirmada por execução real, não só por inspeção do SQL.

## Verificação (contra o banco real, não simulada)

- **Matemática do motor conferida manualmente**: rotina de teste (Corrida, MET 8.0, 30min seg/qua/sex + 60min domingo, peso 79,3kg) → domingo `gasto_atividade = 8 × 79,3 × 1,0 = 634,4` ✓; seg/qua/sex `= 8 × 79,3 × 0,5 = 317,2` ✓; demais dias `= 0` ✓; `tdee_medio = (2825,6672 + 2508,4672×3 + 2191,2672×3) / 7 = 2417,838628...` ✓ — bate exatamente com o valor devolvido pela RPC.
- **`objetivos_alimentares` nunca tocado**: confirmado antes e depois de 3 chamadas de teste a `gerar_sugestao_meta` — a única linha pré-existente do usuário de teste (2000 kcal, PADRAO, ativo) permaneceu idêntica, nenhuma linha nova criada.
- **Versionamento de `sugestao_meta` confirmado em produção**: 3 chamadas de teste geraram 3 linhas com `gerado_em` distintos; só a última ficou `status_vigencia = 'ativo'`, as 2 anteriores viraram `'historico'` automaticamente via trigger.
- **Idempotência da migration**: confirmada por 3 execuções reais consecutivas (ver seção acima).
- **Dados de teste limpos**: a anamnese de teste (+ suas 4 linhas de `anamneses_atividades_dias`, apagadas em cascata) e as 3 linhas de `sugestao_meta` geradas durante a verificação foram removidas do banco ao final — nenhum dado de teste ficou residual em produção.

Nenhum arquivo TypeScript/Edge Function tocado nesta tarefa (o Motor Metabólico já vivia inteiramente como função SQL/RPC, não como Edge Function) — consistente com o ARQUIVOS da tarefa ("scripts SQL... e as funções/Edge Functions responsáveis"; aqui a função responsável é SQL).

## O que fica pendente, fora do escopo desta tarefa (Frontend, Restrição explícita)

- O app Flutter continua gravando só em `anamneses_atividades` (sem dia da semana) e só lê `objetivos_alimentares` com `tipo_dia = 'PADRAO'` fixo — nenhuma tela usa `anamneses_atividades_dias`, `sugestao_meta` ou `gerar_sugestao_meta` ainda. Isso é intencional: a tarefa pediu a fundação, não a integração.
- `objetivos_alimentares.tipo_dia` já é texto livre — suporta usar valores tipo 'SEG'/'TER'/.../'MEDIA' no futuro sem migration nova, mas não é validado (`CHECK`) porque isso quebraria o valor `'PADRAO'` que o Flutter já grava hoje. Decisão de convenção/CHECK fica para quando o Flutter for atualizado.

## Análise e sugestão de merge

Mudança puramente aditiva no schema (2 tabelas novas, 1 função nova) — nenhuma tabela/coluna/função existente foi alterada de forma incompatível (só 2 `comment on column`, sem efeito funcional). Já aplicada e testada de ponta a ponta no banco remoto real (não é uma migration pendente — já está em produção desde a verificação). Recomendo mesclar o código/relatório assim que autorizado — **não mesclado ainda** (Regra 18). Nada a fazer em termos de deploy (não é Edge Function, a migration já rodou contra o banco remoto).
