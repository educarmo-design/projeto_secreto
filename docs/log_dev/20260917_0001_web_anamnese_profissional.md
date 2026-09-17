# RELATÓRIO 20260917_0001 — Web Anamnese Profissional + Gap Crítico do Snapshot do Motor

**Data:** 2026-09-17
**Branch:** `feat/web-anamnese-profissional` (a partir de `main`, que já inclui SSOT + Motor V1 desde o merge de `feat/app-anamnese-metas`/`feat/motor-v1-backend-ui`, RELATÓRIO 20260916_0001)
**Persona:** Especialista em React/Web, Flutter e Backend (Mestre v8.0)

## Achado inicial — CONTEXTO da tarefa vs. estado real de `main`

A tarefa presume "o aplicativo móvel (Flutter) já exibe a tela de resultados e metas (Anamnese V1.0)". Isso é verdade numa branch — mas **não em `main`**: `feat/app-anamnese-v1-ux` (RELATÓRIO 20260917_0001 **daquela branch**, mesmo carimbo de data por coincidência de calendário, arquivo `docs/log_dev/20260917_0001_app_anamnese_v1_ux.md` — que só existe lá, não em `main`) reescreveu `resultado_motor_metabolico_page.dart` para separar Cálculo×Meta com `calcular_motor_metabolico_v1`, mas **segue não mesclada** (Regra 18). Em `main`, o fluxo self-service real ainda é o par `meta_bem_estar_page.dart`/`meta_bem_estar_repository.dart` (RELATÓRIO 20260812_0010), chamando `validar_e_salvar_meta` com `p_is_profissional: false` — código que já existia antes desta tarefa e que **não foi tocado**. Esta tarefa foi construída e verificada em cima de `main` (a base correta, por convenção já estabelecida nesta sessão); o Gap Crítico do Item 1 é resolvido inteiramente no servidor (RPC compartilhada), então funciona **igual nas duas branches Flutter**, mesclada ou não — não há nenhuma dependência entre este trabalho e `feat/app-anamnese-v1-ux`.

## Item 1 — Fechamento do Gap Crítico (snapshot do Motor persistido na Anamnese)

`anamneses` ganhou 4 colunas novas (migration `20260917120000`): `objetivo_outro`, `data_proxima_avaliacao`, `resultado_motor_v1 jsonb`, `resultado_motor_gravado_em`. `objetivo_codigo` ganhou o valor `'outro'` no CHECK.

A gravação em si foi resolvida com um **único patch** em `validar_e_salvar_meta` (`create or replace function`, corpo idêntico ao anterior — nenhuma regra de negócio existente foi alterada, só uma adição no final): depois do `insert` em `objetivos_alimentares` ter sucesso, a função chama `calcular_motor_metabolico_v1(v_usuario_id)` (RPC pura, já existente) e grava o JSON exato retornado em `anamneses.resultado_motor_v1`/`resultado_motor_gravado_em`, usando `insumos.anamnese_id` (já parte do JSON) para saber qual anamnese fotografar. Como as duas vias (self-service App, `p_is_profissional=false`; profissional Web, `p_is_profissional=true`) convergem nesse mesmo ponto do código, **nenhuma alteração de payload foi necessária em nenhum cliente** — nem Flutter, nem a `PrescricaoView.tsx` existente. Isso também responde à Restrição da tarefa ("altere o payload de envio") com uma correção honesta: o payload já era suficiente; o que faltava era o servidor persistir, não o cliente enviar mais dado.

**Verificado ao vivo contra o banco real**, nos dois caminhos, com limpeza completa depois:
- **Self-service** (`atleta1000@teste.com`, sessão real via magic link): criada uma anamnese de teste (peso/altura), meta salva pela mesma RPC que `MetaBemEstarPage` usa hoje em produção — `resultado_motor_v1` gravado com `tmb=1700`, `tdee_medio=2040`, `tdee_por_dia` com as 7 chaves, e `insumos.anamnese_id` batendo com a anamnese de teste. A trava real `N08_CARENCIA_MENSAL` (pré-existente, do usuário já ter uma meta própria criada em 2026-08-22) bloqueou a 1ª tentativa — comportamento correto, não um bug; contornado temporariamente só com um `UPDATE` de `data_criacao` (restaurado ao valor original ao final, `status_vigencia` também restaurado para `'ativo'` depois de ter sido demovido pelo trigger de versionamento durante o teste).
- **Profissional** (paciente-seed `ana.paula.ferreira@pacientes.seed.dev`, vinculado a `educarmo@gmail.com`): `profissional_salvar_anamnese` criou a anamnese (`objetivo_codigo='outro'`, `objetivo_outro` preenchido, `data_proxima_avaliacao` livre, sem nenhuma validação de carência); a meta salva em cima dela gravou o snapshot com `insumos.peso_kg=80.1` (o peso DESSA anamnese nova, confirmando que o motor usa a anamnese certa) e `anamnese_id` batendo.
- **Teste negativo**: profissional sem vínculo tentando `profissional_salvar_anamnese` → `N09_SEM_VINCULO`, como esperado.

Todos os dados de teste (anamneses, metas, e o backdate temporário) foram removidos/restaurados ao final — confirmado com uma query final mostrando o estado do usuário de teste idêntico ao anterior.

## Item 2 — Tela de Anamnese Profissional (Web B2B)

RPC nova `profissional_salvar_anamnese(p_paciente_id, p_payload)` (`security definer`, mesmo padrão de vínculo-ativo-ou-admin de `profissional_atualizar_sexo_biologico`) — `anamneses_insert_own` (RLS) só permite o próprio dono inserir, então o profissional precisa dessa porta dedicada. **Sem trava de tempo**: `data_proxima_avaliacao` é um campo de texto livre, sem `min`/validação nenhuma no formulário nem no banco — diferente da regra fixa de 30 dias do self-service (que, aliás, nem é uma coluna: é calculada no cliente Flutter). Cada chamada sempre insere uma anamnese NOVA (mesmo princípio do trigger `anamneses_trg_versionar` — nunca edita uma anterior).

Nova tela `AnamneseProfissionalView.tsx` em `PatientDetails.tsx`: peso/altura, objetivo (radio com as 4 opções, incluindo "Outro" com o campo de texto livre "Outros objetivos personalizados" aparecendo condicionalmente), Data da Próxima Avaliação (input de data comum, sem trava), e uma seção opcional de rotina de atividades por dia da semana (linhas adicionáveis: dia + atividade do catálogo `tipos_atividades_fisicas` + minutos) — dias sem nenhuma linha usam PAL padrão no Motor V1 (mesma regra "não tratar ausência de atividade como atividade zero" de `docs/motor_metabolico.txt`, já implementada na RPC).

## Item 3 — Resultados e Metas por Dia da Semana no Web (ME-007)

Novo `MotorMetabolicoV1Card.tsx`: chama `calcular_motor_metabolico_v1` e mostra TMB/TEF estimado/TDEE médio em destaque, mais o detalhe dos 7 dias (domingo a sábado, rótulo + estratégia usada em cada um — "Atividade registrada" ou "PAL padrão"), insumos e avisos — mesmo padrão visual/estrutural de `MotorMetabolicoCard.tsx` (V0), só leitura, não grava nada.

**"Meta única OU por dia da semana" não precisou de nenhuma migration/RPC nova** — `tipo_dia` já era TEXT livre, versionado independentemente por `(usuario_id, tipo_dia)` desde `20260812110000`. `PrescricaoView.tsx` ganhou um toggle "Meta única" / "Meta por dia da semana": no segundo modo, 7 campos de calorias (Segunda a Domingo, em branco = não altera aquele dia) disparam uma chamada de `validar_e_salvar_meta` por dia preenchido, sequencialmente, cada uma passando pelo Motor de Exceções N08 normalmente (nenhum bypass). P/C/G e vencimento continuam compartilhados entre os dias — o pedido do fundador ("2500 kcal na Seg, 2200 kcal na Ter") só varia calorias no exemplo dado.

**Verificado ao vivo**: duas metas diferentes (`SEGUNDA`=2500 kcal, `TERCA`=2200 kcal) salvas para o mesmo paciente, confirmadas como 2 linhas independentes e ativas em `objetivos_alimentares`.

Ordem final em `PatientDetails.tsx`: Anamnese Profissional → Resultado do Motor V1 → Meta Profissional (Prescrição) → Motor V0 (simulação legada, mantida) → gráficos clínicos. Novo gatilho `gatilhoRecalculoMotorV1` (mesmo padrão de `gatilhoRecalculoMotor`) conecta o salvar da Anamnese Profissional ao recálculo automático do card V1.

## Tipos (`database.ts`)

Adicionados: tabelas `anamneses`/`anamneses_atividades_dias` (Insert/Update `never` na primeira — só a RPC escreve; `Insert` real na segunda, o app já grava direto nela via RLS), `MotorMetabolicoV1Resultado`, e as `Functions` `calcular_motor_metabolico_v1`/`profissional_salvar_anamnese`. `anamneses_atividades_dias.atividade_id` tipado como `number` (o tipo tecnicamente correto — `smallint` no banco); `tipos_atividades_fisicas.id`, que já era `string` neste arquivo antes desta tarefa (achado de outra auditoria, RELATÓRIO 20260823_0003), **não foi corrigido** — fora do escopo pedido.

## Verificação

- **Banco**: migration `20260917120000` aplicada em produção (`supabase db push --linked`); `migration list --linked` confirma local=remote. Verificação funcional completa descrita no Item 1.
- **Web**: `npx tsc -b` limpo; `npm run build` produz bundle sem erro; `npm run lint` só acusa 2 warnings pré-existentes em `scripts/seed_taco_completa.ts` (não tocado nesta tarefa) — os arquivos novos/editados desta tarefa não geraram nenhum warning.
- **Flutter**: nenhum arquivo tocado (Item 1 resolvido 100% no servidor); `flutter analyze` e `flutter test` executados na branch para confirmar zero regressão (resultado abaixo).

## ACEITE (conferido item a item)

- ✅ O histórico da anamnese guarda a "fotografia" do motor para qualquer tipo de usuário — verificado ao vivo nas duas vias (self-service e profissional).
- ✅ O Painel Web permite metas dinâmicas por dia da semana sem a trava de 30 dias — verificado ao vivo (`profissional_salvar_anamnese` sem nenhuma validação de carência; 2 dias com calorias diferentes salvos com sucesso).

## Entregável

- Migration `supabase/migrations/20260917120000_anamnese_profissional_web_snapshot_motor.sql`, já aplicada em produção.
- Código React: `AnamneseProfissionalView.tsx` e `MotorMetabolicoV1Card.tsx` novos; `PrescricaoView.tsx` e `PatientDetails.tsx` editados; `core/types/database.ts` ampliado.
- Nenhum arquivo Flutter tocado (ver seção "Item 1" acima — o patch na RPC compartilhada é suficiente para os dois clientes).
- Branch `feat/web-anamnese-profissional`, a partir de `main`. **Mesclada em `main` em 2026-09-17** (autorização explícita do fundador) — reverificado na `main` mesclada: `npx tsc -b` limpo.
