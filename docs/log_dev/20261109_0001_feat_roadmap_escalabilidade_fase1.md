# 20261109_0001 — Roadmap de Escalabilidade: Fase 1 (índices) concluída + Fases 2/3 planejadas

## Contexto

Preparação de infraestrutura para alta escala. O fundador aprovou a execução imediata da Fase 1 (indexação B-Tree sem custo e sem risco de regressão) e a formalização do roadmap completo (Fases 2 e 3) na documentação do projeto, para orientar decisões futuras sem precisar implementá-las agora.

Restrição explícita cumprida: nenhuma lógica de negócio, RPC ou regra de RLS foi alterada — só índices físicos (`CREATE INDEX IF NOT EXISTS`), que não mudam o resultado de nenhuma consulta, só a velocidade.

## Fase 1 (Concluída) — Índices B-Tree em colunas de RLS e FK

### Metodologia

Auditoria de todas as 54 migrations existentes em `supabase/migrations/`, levantando:
1. Toda coluna usada em `using (...)`/`with check (...)` de uma policy de RLS (comparação direta contra `auth.uid()`, ou indireta via `exists (...)` que junta de volta à tabela externa).
2. Toda Foreign Key do schema (`references`, inline ou via `alter table ... add column ... references`).

**Achado**: as duas listas colapsam numa só — nenhuma policy de RLS deste schema compara uma coluna que não seja também uma FK (o padrão do projeto é sempre "dono da linha" ou "vínculo profissional-paciente", ambos sempre FKs pra `auth.users`/outra tabela).

A maioria das colunas levantadas **já tinha índice** — quase sempre como coluna líder de um índice composto já existente (ex. `idx_anamneses_usuario_status (usuario_id, status_vigencia)`) ou como coluna líder de uma Primary Key composta (ex. `anamneses_alergias (anamnese_id, alergia_id)`, onde `anamnese_id` já é indexado pela própria PK). Criar um índice duplicado nessas colunas não traria ganho nenhum, só custo de espaço/escrita — por isso a migration (`20261109120000_fase1_indices_escalabilidade_rls_fk.sql`) cobre **exclusivamente** as colunas que sobraram descobertas: FKs que nunca tiveram índice próprio, ou que são a coluna **trailing** (não líder) de uma PK/índice composto.

### Índices criados (17)

| Tabela | Coluna | Motivo |
|---|---|---|
| `planejamento_clinico` | `profissional_id` | RLS compara direto, sem índice |
| `planejamento_clinico` | `paciente_id_anonimo` | RLS compara direto, sem índice |
| `resultados_exames` | `marcador_codigo` | FK, trailing do índice composto existente |
| `atividades_fisicas_treinos` | `tipo_atividade_codigo` | FK, sem índice próprio |
| `usuario_papeis` | `papel_id` | FK, trailing da PK composta |
| `papeis_permissoes` | `permissao_id` | FK, trailing da PK composta |
| `usuario_alergias` | `alergia_id` | FK, trailing da PK composta |
| `anamneses` | `profissional_id` | FK (quem prescreveu), sem índice próprio |
| `anamneses_alergias` | `alergia_id` | FK, trailing da PK composta |
| `anamneses_problemas_saude` | `problema_saude_id` | FK, trailing da PK composta |
| `anamneses_atividades` | `atividade_id` | FK, trailing da PK composta |
| `anamneses_atividades_dias` | `atividade_id` | FK, 2ª coluna de PK composta de 3 |
| `objetivos_alimentares` | `profissional_id` | FK (quem prescreveu a meta), sem índice próprio |
| `sugestao_meta` | `anamnese_id` | FK nullable, sem índice próprio |
| `anamneses_medicamentos` | `anamnese_id` | FK direta, sem índice próprio |
| `anamneses_suplementos` | `anamnese_id` | FK direta, sem índice próprio |
| `anamneses_exames_laboratoriais` | `anamnese_id` | FK direta, sem índice próprio |

Essas colunas aceleram diretamente a checagem de RLS em toda consulta feita pelo app/Painel Web (o Postgres avalia a policy POR LINHA; sem índice, cada checagem de "esta linha pertence a este usuário?" em tabelas grandes pode degradar pra um scan completo) e os `JOIN`s mais comuns (ex. `anamneses_medicamentos` por `anamnese_id` ao montar o detalhe de uma anamnese, `anamneses_atividades_dias` por `atividade_id` ao resolver o nome de exibição).

### Verificação

- Migration aplicada em produção (`supabase db push --linked`).
- `create index if not exists` em todas as 17 — idempotente, pode ser reaplicada sem erro.

## Fase 2 (Planejada — Médio Prazo): Caching de Borda

**Objetivo**: reduzir latência e carga no banco para consultas REPETITIVAS e de leitura pesada que mudam pouco — candidatos óbvios: catálogo de alimentos (`alimentos_referencia`, `alimentos_medidas_caseiras`), metadados dos Protocolos de Macronutrientes (parâmetros versionados de MACRO-001 a 005, hoje recalculados a cada chamada de `calcular_motor_metabolico_v1`), catálogos fixos (`problemas_saude`, `alergias`, `tipos_atividades_fisicas`).

**Estratégia**:
- Supabase Edge Functions na frente das consultas de catálogo, com Upstash Redis (serverless, cobra por request — alinhado ao modelo de custo do Supabase) como camada de cache.
- Padrão cache-aside: a Edge Function checa o Redis primeiro; se vazio, consulta o Postgres, grava no Redis com TTL, devolve.
- TTL sugerido: minutos a horas pra catálogos (mudam raramente), invalidação manual/por deploy quando o catálogo for atualizado.
- Não se aplica a dados por-usuário (anamneses, metas, histórico) — esses continuam direto no Postgres, RLS garante o isolamento que um cache compartilhado quebraria.

**Pré-requisito**: nenhum código existente precisa mudar pra isso começar — é uma camada NOVA, opcional, na frente das rotas de leitura de catálogo que hoje já existem.

## Fase 3 (Planejada — Longo Prazo): Infraestrutura de Conexão e Observabilidade

**Transaction Pooling via Supavisor (porta 6543)**: migrar as conexões de aplicação (Flutter/Edge Functions) do modo de sessão (porta 5432) pro pooler de transação do Supavisor — necessário quando o número de conexões simultâneas se aproximar do limite do plano/instância Postgres (cada conexão de sessão fica reservada; pooling de transação reaproveita conexões entre requisições curtas, muito mais eficiente pro padrão request-response deste app).

**Read Replicas**: quando o volume de LEITURA (relatórios, dashboards, consultas de histórico) começar a competir com ESCRITA (RPCs de gravação, trava clínica, versionamento) pelo mesmo primary, direcionar leituras read-only pra uma réplica secundária — reduz contenção sem replicar a complexidade de RLS (réplicas de leitura do Supabase herdam o mesmo schema/RLS do primary).

**Gatilhos de alerta de métricas**: configurar alertas no dashboard do Supabase para:
- CPU > 70% sustentado (sinal de que o plano atual está perto do limite, antes de degradar a experiência);
- Esgotamento do pool de conexões (sinal de que o Transaction Pooling/réplicas da Fase 3 precisam entrar em produção, não só estar planejados).

**Gatilho de ativação**: estas 3 ações da Fase 3 não são "configure agora" — são "configure quando a métrica cruzar o limiar". A Fase 1 (índices) e a Fase 2 (cache) adiam bastante o momento em que isso se torna necessário.

## Arquivos

- `supabase/migrations/20261109120000_fase1_indices_escalabilidade_rls_fk.sql` (nova — 17 índices).
- `docs/log_dev/20261109_0001_feat_roadmap_escalabilidade_fase1.md` (este relatório).
- `docs/log_dev/INDICE.md`.

Branch `feat/fase1-indices-roadmap-escalabilidade`, a partir de `main`.
