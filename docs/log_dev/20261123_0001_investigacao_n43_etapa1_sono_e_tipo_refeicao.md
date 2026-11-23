# 20261123_0001 — N43 Etapa 1: instantes do sono e tipo da refeição (investigação, sem código)

**Data:** 2026-11-23
**Branch:** `docs/n43-etapa1-investigacao-sono-refeicao` (a partir de `main` em `cb12738`)
**Natureza:** investigação pura (Parte 10.6, Etapa 1). **Nenhum código de aplicação, migration ou regra de negócio foi alterado.** Só este log e a linha no `INDICE.md`.
**Método:** schema **real de produção** lido com `supabase db query --linked` (somente `SELECT` em `information_schema`/`pg_*` e contagens agregadas; nenhum dado de usuário foi lido ou impresso) + leitura do código em `lib/` e `supabase/`. Nada foi presumido pela documentação.

## Resposta curta

| # | Pergunta | Resposta |
|---|---|---|
| 1 | Início/fim do sono estão persistidos em `metricas_saude_diarias`? | **NÃO.** Só as durações em minutos. Os instantes chegam do Health Connect e são **descartados** na agregação diária, em `HealthSyncService._mesclarPorDia` (`lib/features/dashboard/data/services/health_sync_service.dart`, método a partir da linha 1519). |
| 2 | O tipo da refeição é gravado nos 4 métodos (foto, áudio, texto, favoritas)? | **NÃO, em nenhum dos 4.** `coleta_diaria` não tem coluna de tipo e o `valor_jsonb` da refeição só tem `itens`, `itens_nao_reconhecidos` e `totais`. O tipo só existe em `alimentos_favoritos` (quando o usuário salva uma favorita) e **não é copiado** para a refeição registrada. |

## 1. Instantes de início e fim do sono

### Schema real (produção) — `public.metricas_saude_diarias`
Colunas de sono: `minutos_sono` (integer), `sono_leve_minutos`, `sono_profundo_minutos`, `sono_rem_minutos`, `sono_acordado_minutos` (todas integer, nullable). **Não existe nenhuma coluna `timestamptz`/`time` de sono** nem coluna de fuso/offset. As únicas colunas de tempo da tabela são `data_referencia` (date), `criado_em` e `atualizado_em` (momentos da sincronização, não do sono).
- Varredura de todo o schema `public` por colunas com `sono|sleep|dormir|acordar`: além das 5 acima, só `anamneses.horario_dormir_habitual`, `horario_acordar_habitual`, `horas_sono_medias`, `qualidade_sono_percebida`, `sono_observacoes` (autorrelato da anamnese, **não** medido pelo wearable) e `anamneses.sono_dados_wearable` (**boolean** que só diz se há dado de wearable).
- Não há triggers em `metricas_saude_diarias` nem em `coleta_diaria`. A única função de banco que lê sono é `processar_medias_smartwatch` (só `avg(minutos_sono)`). Nenhuma Edge Function grava sono ou telemetria desta tabela.

### Fluxo real no app (Flutter)
1. **O que é lido:** a lista de tipos do sync (`health_sync_service.dart` ~linhas 365–379) pede `SLEEP_ASLEEP`, `SLEEP_LIGHT`, `SLEEP_DEEP`, `SLEEP_REM`, `SLEEP_AWAKE` — um ponto por segmento de estágio, cada um com `dateFrom`/`dateTo`. **`SLEEP_SESSION` (a sessão inteira, com hora de deitar e acordar) NÃO é lido pelo sync**; o comentário nas linhas 365–369 diz que ficou de fora de propósito. Ele só é lido por `lerSonoRecente()` (linha ~540), uma tela de teste manual que, nas palavras do próprio método, **"Não grava nada"**.
2. **Onde os instantes existem:** `HealthPayloadModel.dateFrom`/`dateTo` (`health_payload_model.dart` linhas 53–54) carregam o início/fim de cada estágio em memória.
3. **Onde são descartados:** em `_mesclarPorDia`, `payload.dateFrom` é usado apenas para (a) achar o fuso vigente (`_offsetParaInstante`) e (b) decidir a **data** da noite (`_dataDoSonoLocal`: estágio às 15h ou depois conta para o dia seguinte). Em seguida só os minutos são somados (`somar('sono_leve_minutos', …)` etc., linhas ~1636–1639) e `minutos_sono = leve + profundo + REM` (linhas ~1766–1773). A linha montada tem apenas colunas fixas; **nenhuma chave de instante** é colocada nela.
4. **O que é enviado:** `_enviarLinhas` (linha ~1121) faz `upsert` em `metricas_saude_diarias` com `onConflict: 'usuario_id_anonimo,data_referencia'` — a linha agregada, sem instantes.
5. **Fuso:** o histórico de fuso (`_chaveHistoricoFuso`) fica só no armazenamento seguro do aparelho (`_secureStorage`), **não no banco**. Logo, mesmo se um instante UTC fosse gravado, o offset local da época não estaria disponível no servidor.

### Consequência direta para a Etapa 2 (sono, 22 templates)
O dado **precisa ser capturado do zero**; não há como derivar início/fim do que já está no banco (os instantes originais foram descartados). Para as noites já sincronizadas, o único caminho é **reler do Health Connect** no aparelho (limitado ao histórico que o Health Connect ainda guarda); noites antigas fora dessa janela ficam sem instantes.

**O que faltará persistir (mapa, sem decidir o desenho — isso é da Etapa 2):**
- Início e fim do sono da noite, como `timestamptz` (UTC) **e** o offset/fuso local da época (porque o servidor não os conhece) — hoje há zero colunas para isso.
- A regra de qual instante vale quando há várias sessões/cochilos no mesmo `data_referencia` (hoje a heurística de 15h agrupa tudo numa linha por dia).
- A origem do instante: derivar de `min(dateFrom)`/`max(dateTo)` dos estágios (já disponíveis em `_mesclarPorDia`, sem leitura nova) **ou** ler `SLEEP_SESSION` (que traz bedtime/waketime oficiais, mas hoje fora do sync por decisão antiga documentada). Regra G.2/G.3: guardar o dado cru e derivar na consulta.
- Impacto: mudança em `HealthPayloadModel`/`_mesclarPorDia`/`_enviarLinhas` (app) e uma migration em `metricas_saude_diarias` (RLS já existente por `auth.uid()`; coluna nova herda a policy da tabela, mas o `GRANT` explícito deve ser conferido).

## 2. Tipo da refeição nos 4 métodos de registro

### Schema real (produção)
- `public.coleta_diaria`: `id`, `usuario_id`, `atributo`, `valor_numerico`, `valor_jsonb`, `unidade`, `origem`, `confianca`, `data_coleta` (**date**), `criado_em` (**timestamptz, default now()**). **Sem coluna de tipo de refeição.** Constraints: só `confianca` em [0,1] e "valor_numerico ou valor_jsonb não nulo" (nada restringe `atributo`/`origem`). Sem triggers.
- **Chaves reais de `valor_jsonb` por atributo** (consulta agregada em produção): `refeicao` → `itens`, `itens_nao_reconhecidos`, `totais` (360 linhas, **todas com `origem = 'ocr_refeicao'`**); `rotulo_nutricional` (42) → macros e `porcao_descricao`; `balanca` (3), `glicosimetro` (9), `agua_ml` (20, manual). **Nenhuma chave `tipo`/`tipo_refeicao`/`horario`.**
- `public.alimentos_favoritos`: `id`, `usuario_id`, **`tipo_refeicao` (text, CHECK com 4 valores: `cafe_da_manha`, `almoco`, `lanche`, `jantar`)**, `nome`, `payload_jsonb`, `criado_em`.
- `public.diario_alimentar_diario` tem `tipo_refeicao`, `data_refeicao`, `registrado_em`, mas **0 linhas** e nenhum código do app a escreve (a migration `20260712120000_remove_tabelas_orfas.sql` a cita entre tabelas nunca escritas; `GeminiGatewayService.toDiarioAlimentarJson` existe, mas nenhum chamador). Não é o destino das refeições.

### Fluxo real no app (Flutter) — os 4 métodos convergem num único ponto
| Método | Tela de entrada | Abre `ConfirmacaoPratoPage` em |
|---|---|---|
| Foto | `camera_capture_view.dart` | linha 212 |
| Texto | `descrever_refeicao_page.dart` | linha 107 |
| Áudio | `gravar_refeicao_page.dart` | linha 189 |
| Favoritas | `favoritas_page.dart` (`_usarFavorita`) | linha 117 |

Os 4 chamam `ConfirmacaoPratoController.confirmar()` → `ColetaDiariaRepository.gravarRefeicao({payloadRevisado, confianca, dataColeta})` (`coleta_diaria_repository.dart` linhas 82–104). **A assinatura não tem parâmetro de tipo.** O `INSERT` grava `usuario_id`, `atributo='refeicao'`, `valor_jsonb=payloadRevisado`, `origem='ocr_refeicao'` (constante `_origemOcrRefeicao`, **igual para os 4 métodos — o método de registro também não é distinguível**), `confianca` e `data_coleta` (só a data, do relógio do aparelho). `payloadRevisado()` (`confirmacao_prato_controller.dart` linhas ~346–375) devolve apenas `itens`, `itens_nao_reconhecidos`, `totais`.

- **Foto, texto, áudio:** nenhuma tela pergunta o tipo; não existe nenhuma menção a `tipo_refeicao`/`TipoRefeicao` em `descrever_refeicao_page.dart`, `gravar_refeicao_page.dart`, `registro_refeicao_ia_*` ou na Edge Function `extract-metric-photo` (varredura em `supabase/functions` por `tipo_refeicao|meal_type|horario_refeicao`: zero resultados).
- **Favoritas:** o tipo **existe** e é obrigatório ao criar a favorita (`DialogoNomeTipoFavorita`, enum `TipoRefeicao` em `favorita_model.dart`, gravado por `FavoritasRepository.salvar`/`atualizarTipo`, usado como filtro em `FavoritasPage`). Mas ao **usar** uma favorita (`_usarFavorita`), o fluxo cai no mesmo `gravarRefeicao`, sem passar o tipo: **o tipo é perdido na hora de registrar a refeição**.
- Resumo: tipo persistido na **refeição registrada**: **0 de 4** métodos. Tipo persistido em outra tabela: só `alimentos_favoritos` (cadastro de favoritas, não refeições consumidas).

### Como o tipo convive com o horário (nota do pedido)
O único instante da refeição no banco é `coleta_diaria.criado_em` (`default now()`, servidor, **no momento do `INSERT`**, isto é, quando o usuário confirma) e `data_coleta` (data local). Não há coluna ou chave de "início da refeição" separada do instante da confirmação. Se "início da refeição" (decisão 94) significa o momento em que o registro é feito/confirmado, o dado existe em `criado_em`; se significa o início do ato de comer informado pelo usuário, **o schema não tem esse campo**. Registro apenas o fato; a decisão 94 não é contestada aqui.

### Consequência direta para a Etapa 2 (tipo da refeição, 7 templates)
**O que faltará persistir (mapa):**
- O tipo (4 valores já existentes no enum `TipoRefeicao`/CHECK de favoritas: `cafe_da_manha`, `almoco`, `lanche`, `jantar`) em `coleta_diaria` para `atributo='refeicao'` — como chave nova de `valor_jsonb` **ou** coluna dedicada (decisão de desenho da Etapa 2; o repositório e a tabela hoje não têm onde guardar).
- Como o funil é único (`ConfirmacaoPratoPage` → `confirmar()` → `gravarRefeicao`), **um único seletor de tipo** nessa tela cobre os 4 métodos; para "favoritas", pode vir pré-preenchido com `favorita.tipoRefeicao` (já disponível). Não é preciso alterar 4 telas separadas.
- As **360 refeições já gravadas não têm tipo** e não há como recuperar com certeza (só inferência por `criado_em`, que é heurística e não dado).
- Opcional a decidir na Etapa 2: o método de registro (foto/áudio/texto/favorita) hoje não é distinguível (`origem` é sempre `ocr_refeicao`); só necessário se algum dos 7 templates depender disso.
- Impacto de testes: `confirmacao_prato_controller_test.dart`, `confirmacao_prato_page_test.dart` e `favoritas_page_test.dart` exercitam `gravarRefeicao`/o payload.

## Desvios
- A pergunta cita `SleepSessionRecord` com `startTime/endTime`; no app o plugin `health` expõe isso como `HealthDataType.SLEEP_SESSION`/pontos com `dateFrom/dateTo`. Mapeei os termos; a conclusão não muda.

## Problemas encontrados
Nenhum impeditivo para a investigação. Observações: (1) o enunciado "horário gravado no início da refeição" não é rastreável a um campo específico (ver nota acima); (2) `diario_alimentar_diario` é tabela órfã com coluna de tipo e zero linhas — não reaproveitar sem decisão.

## Riscos mapeados
- Noites de sono anteriores à Etapa 2 ficarão sem instantes (descartados na origem); só reaparecem se ainda estiverem no Health Connect.
- Refeições anteriores (360) ficarão sem tipo; templates de tipo terão cobertura parcial até o dado novo acumular.
- Qualquer migration da Etapa 2 em `metricas_saude_diarias`/`coleta_diaria` deve manter RLS por `auth.uid()` e `GRANT` explícito (Parte 6); `revoke … from public` sozinho não remove o grant de `anon` (achado do log 0003).

## Como o fundador verifica
1. Confira que o PR altera **só** `docs/log_dev/` (este log e `INDICE.md`): nenhum `.dart`, `.ts` ou `.sql`.
2. Leia a "Resposta curta" no topo.
3. Leia, em cada seção, "O que faltará persistir" — é a lista de trabalho da Etapa 2.

## Infra/config, entidades novas, performance
Infra/config: nenhuma mudança. Entidades novas: **nenhuma**. Performance: **não aplicável — apenas auditoria**. Consultas ao banco foram somente leitura (catálogo + agregados).

## Mesclagem (decisão 96) — registrada em 2026-11-23

- **PR #26 mesclado em `main`** (merge commit `cf91ad9`), sem force push, com autorização explícita do fundador e 5/5 checks verdes. O PR continha só este log e a linha no `INDICE.md`.
- Desdobramento: a Etapa 2 foi antecipada pelo fundador — ver `20261123_0002_feat_n43_etapa2_sono_instantes_e_tipo_refeicao.md`.

## CORREÇÃO (2026-11-23) — contagens de linhas desta investigação estavam infladas

Ao verificar a Etapa 2 em produção, `select count(*) from coleta_diaria where atributo = 'refeicao'` devolveu **120**, não 360. Causa do erro (minha, na Etapa 1): a consulta que levantou as chaves de `valor_jsonb` fazia `LEFT JOIN LATERAL jsonb_object_keys(...)`, que **repete cada linha uma vez por chave do JSON**; eu li o `count(*)` dessa junção como se fosse o número de linhas. Números reais (`count(*)` simples por `atributo`): `refeicao` **120** (não 360), `rotulo_nutricional` **7** (não 42), `glicosimetro` **3** (não 9), `balanca` **1** (não 3), `agua_ml` 20 (correto, sem chaves). **Nada mais neste log muda**: as listas de chaves de `valor_jsonb` e todas as conclusões (sem coluna/chave de tipo; instantes de sono descartados) continuam válidas. Onde este log e o texto do PR dizem "360 refeições", leia **120**.
