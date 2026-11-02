# 20261102_0002 — Histórico de Anamnese: FK direta (`anamnese_id`) substitui a janela de tempo

## Contexto

O RELATÓRIO `20261102_0001` entregou o "Plano de Metas" na `AnamneseDetalhesPage` correlacionando `objetivos_alimentares` a `anamneses` por JANELA DE TEMPO (início = `data_preenchimento` da anamnese, fim = `data_preenchimento` da próxima, ou sem limite se ainda vigente) — não havia FK entre as duas tabelas, e a tarefa original não pedia uma.

O fundador rejeitou essa correlação explicitamente: "Correlação por data é frágil e viola boas práticas de modelagem relacional. O vínculo DEVE ser feito exclusivamente por Chave Estrangeira (FK) direta (`anamnese_id`)." Esta tarefa substitui a heurística pela FK, de ponta a ponta (schema → RPC → Flutter → testes).

## Auditoria — achado chave

`validar_e_salvar_meta` (RPC única de gravação de `objetivos_alimentares`, N08/N10/N11) **já resolvia** o `anamnese_id` certo antes desta tarefa — só não o persistia na própria tabela. Desde o RELATÓRIO `20260917_0001` (Gap Crítico do snapshot do Motor), a função chama `calcular_motor_metabolico_v1(v_usuario_id)` logo DEPOIS do INSERT e lê `insumos.anamnese_id` do resultado — a anamnese mais recente do usuário com `peso_kg` E `altura_cm` preenchidos (SSOT do motor, RELATÓRIO `20260916_0001`) — só para gravar o snapshot em `anamneses.resultado_motor_v1`.

Ou seja: **o valor certo da FK já existia dentro da própria transação**, calculado pela mesma RPC que insere a meta. Não foi necessário inventar nenhuma heurística nova — só reordenar a função para calcular isso ANTES do INSERT em vez de depois, e gravar no próprio INSERT.

## O que mudou

### 1. Schema (migration `20261102140000_objetivos_alimentares_fk_anamnese_direta.sql`)

- `objetivos_alimentares.anamnese_id uuid references anamneses(id) on delete cascade` (nullable — nem toda meta tem uma anamnese com dados antropométricos completos por trás).
- Índice `idx_objetivos_alimentares_anamnese_id`.
- `validar_e_salvar_meta`: mesmo corpo, com a chamada a `calcular_motor_metabolico_v1` (e a leitura de `insumos.anamnese_id`) movida para ANTES do `insert into objetivos_alimentares`, incluindo a coluna `anamnese_id` no próprio INSERT. O snapshot em `anamneses.resultado_motor_v1` continua gravado depois, com o MESMO `v_resultado_v1` já calculado (nenhuma segunda chamada à RPC pura).
- **Backfill retroativo** (Parte 3 da migration): `update objetivos_alimentares set anamnese_id = (select a.id from anamneses a where a.usuario_id = o.usuario_id and a.data_preenchimento <= o.data_criacao order by a.data_preenchimento desc limit 1) where anamnese_id is null`.

**Gap honesto, documentado na própria migration**: para linhas que já existiam, não há nenhuma FK gravada originalmente — reconstruir o vínculo exige, por definição, inferir qual anamnese já existia quando aquela meta foi salva. A Restrição "proibido comparação de data" é sobre a CONSULTA em runtime do app (ver item 3); este UPDATE é um evento ÚNICO, roda uma vez nesta migration, e nunca mais é necessário depois — todo INSERT novo já grava a FK real via `validar_e_salvar_meta`.

### 2. Flutter

- `MetaResumo` ganha `anamneseId` (mapeado de `objetivos_alimentares.anamnese_id`).
- `MetaBemEstarRepository.buscarMetasPorAnamneseId(String anamneseId)` substitui `buscarMetasNoPeriodo(inicio, fim)` — filtra só por `.eq('anamnese_id', anamneseId)`, nenhuma comparação de data.
- `AnamneseRepository.buscarDataProximaAnamnese` removido por completo (só existia para calcular o fim da janela — não tem mais consumidor).
- `AnamneseDetalhesPage._carregar()` simplificado: chama `_metaRepository.buscarMetasPorAnamneseId(widget.anamneseId)` direto, sem calcular janela nenhuma. Nenhuma outra parte da UI mudou (badge de origem, card único/expansível por dia, fallback — tudo do RELATÓRIO `20261102_0001` continua igual, só a fonte dos dados mudou).

### 3. Testes

- `anamnese_repository_test.dart`: removido o grupo `buscarDataProximaAnamnese` e o override `.gt()` do fake (sem outro consumidor).
- `meta_bem_estar_repository_test.dart`: grupo `buscarMetasNoPeriodo` → `buscarMetasPorAnamneseId` (mesma cobertura: múltiplos `tipo_dia`/profissional, defaults quando a coluna não vem na resposta, usuário deslogado); removidos os overrides `.gte()`/`.lt()` do fake.
- `anamnese_detalhes_page_test.dart`: stubs trocados para `buscarMetasPorAnamneseId`; o teste que verificava "janela sem limite superior" foi substituído por um teste que verifica a chamada exclusivamente por `anamneseId` (`verify(() => metaRepository.buscarMetasPorAnamneseId('anamnese-1')).called(1)`).

## Verificação

- `flutter analyze` (lib/test de nutrição): **sem issues**.
- `flutter test` completo: **566/566** (nenhuma regressão).
- Migration aplicada em produção (`supabase db push --linked`); `supabase migration list --linked` confirma `local=remote` para `20261102140000`.
- **Backfill real**: `objetivos_alimentares` tinha 1 linha em produção no momento da migration (usuário de teste `atleta1000@teste.com`, criada em 2026-08-22). O backfill deixou `anamnese_id = null` — correto: a anamnese mais antiga deste usuário é de 2026-10-16, ou seja, **nenhuma anamnese existia ainda** quando aquela meta foi salva. O gap honesto documentado na migration se confirmou na prática, não inventou um vínculo falso.
- **Teste end-to-end da FK nova** (simulando a sessão do usuário via `request.jwt.claims`, mesma técnica usada no RELATÓRIO `20261101_0002` para reproduzir bugs): chamei `validar_e_salvar_meta` como `atleta1000@teste.com` (payload `calorias_alvo=2200, proteina_g=150, carbo_g=250, gordura_g=70`) — sucesso, sem violação clínica. A linha nova (`6d4caf7d-...`) foi gravada com `anamnese_id = '923de9e1-...'`, exatamente a anamnese ATIVA deste usuário (confirmado por `calcular_motor_metabolico_v1` resolvendo o mesmo id antes da chamada). O snapshot em `anamneses.resultado_motor_v1` também continuou sendo gravado (`resultado_motor_gravado_em` não nulo) — a reordenação não quebrou o Gap Crítico do RELATÓRIO `20260917_0001`.
- Essa chamada é uma gravação de meta real e legítima (não um artefato de bug, como a duplicata limpa no RELATÓRIO `20261101_0002`) — ficou em produção no histórico deste usuário de teste como evidência viva do comportamento novo (a meta antiga virou `historico` pelo trigger de versionamento, nada foi apagado).

## Arquivos

- `supabase/migrations/20261102140000_objetivos_alimentares_fk_anamnese_direta.sql` (nova).
- `lib/features/nutricao/data/repositories/meta_bem_estar_repository.dart`.
- `lib/features/nutricao/data/repositories/anamnese_repository.dart`.
- `lib/features/nutricao/presentation/pages/anamnese_detalhes_page.dart`.
- `test/features/nutricao/data/repositories/anamnese_repository_test.dart`.
- `test/features/nutricao/data/repositories/meta_bem_estar_repository_test.dart`.
- `test/features/nutricao/presentation/pages/anamnese_detalhes_page_test.dart`.

Branch `feat/historico-anamnese-fk-direta`, a partir de `main`.
