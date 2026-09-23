# RELATÓRIO 20260922_0001 — Motor de Agregação de Smartwatch, Composição Corporal Automática, Schema de IA e Validade da Anamnese

**Branch:** `feat/anamnese-smart-backend-v3` (a partir de `main`).
**Data:** 2026-09-22.
**Escopo:** 100% Backend/Supabase — nenhum arquivo Flutter ou React tocado (`RESTRIÇÕES` explícitas). Migration única: `supabase/migrations/20260922100000_anamnese_smart_backend_v3.sql`.

## 1. Motor de Inicialização e Histórico — `iniciar_rascunho_anamnese(p_usuario_id)`

Função pura (só leitura). Passos:

1. Busca a última anamnese do usuário (`order by data_preenchimento desc limit 1`, qualquer `status_vigencia` — a mais recente é sempre a relevante).
2. **Regra de Janela de Tempo**: sem anamnese anterior → `janela.data_inicio = now() - 30 dias`; com anterior → `janela.data_inicio = data_preenchimento` daquela anamnese. `janela.data_fim = now()` sempre.
3. **Preenchimento automático**: copia exatamente os 4 grupos citados na tarefa — `sexo_biologico` (lido **ao vivo** de `perfis_usuarios`, não uma cópia potencialmente desatualizada dentro da anamnese anterior — decisão explícita, já que a tarefa pede "sexo_biologico atualizado"), condições de saúde (`anamneses_problemas_saude` join `problemas_saude`, com diagnóstico/status/profissional/observações), alergias (`anamneses_alergias` join `alergias`), e as 3 restrições (`restricoes_alimentares`, `intolerancias_alimentares`, `restricoes_culturais_religiosas`).

Não foram copiados campos fora dessa lista (peso, altura, objetivo, etc.) — decisão de escopo deliberada, seguindo o texto literal da tarefa ("sexo_biologico atualizado, doenças, alergias, restrições"), documentada aqui em vez de simplesmente omitida.

O retorno inclui `janela` (com `anamnese_anterior_id`/`anamnese_anterior_data`/`dias_totais`) justamente para alimentar a RPC do Item 2 sem uma segunda consulta.

## 2. Motor de Agregação de Smartwatch — `processar_medias_smartwatch(p_usuario_id, p_data_inicio, p_data_fim)`

Função pura. Duas fontes de dado, deliberadamente diferentes:

- **`metricas_saude_diarias`** — 1 linha por usuário/dia (passos, distância, FC repouso, HRV, calorias ativas/basais/totais, minutos de sono, peso, % gordura). Usada para as **médias diárias**.
- **`atividades_fisicas_treinos`** — 1 linha por treino real (início/fim/modalidade), a fonte de verdade de sessões de exercício sincronizadas do wearable. **Não** é `anamneses_atividades_dias` (que é a rotina *autorrelatada* de uma anamnese específica, sem data real — inadequada para "médias de um período histórico").

### 2.1 — Médias diárias e confiabilidade

Para cada métrica, a query usa `avg(coluna)` do Postgres, que **já ignora `NULL` nativamente** — ou seja, a média sai dividida só pelos dias que têm aquele dado, nunca por uma constante fixa (30, ou os dias totais do período). `percentual_confiabilidade = count(coluna não nula) ÷ dias_totais_do_período × 100`, onde `dias_totais_do_período = (data_fim::date − data_inicio::date) + 1`.

Exemplo verificado ao vivo: período de 14 dias, `passos` preenchido em 7 deles → `dias_com_dado: 7`, `percentual_confiabilidade: 50`, `media` = média dos 7 valores reais (não `soma ÷ 14`).

### 2.2 — Atividades por dia da semana e modalidade

Este é o ponto estatístico mais delicado da tarefa: **"a média de duração ou ocorrência DEVE ser dividida pelo número de semanas (ou seja, pelo número daquele dia específico contido no período)"**.

Implementação em 2 passos:

1. `contagem_dow` — via `generate_series(data_inicio::date, data_fim::date, '1 day')` + `extract(dow from dia)`, conta **quantas vezes cada dia da semana (0=domingo..6=sábado) realmente ocorre** dentro do período. Este é o denominador correto — não é `dias_totais ÷ 7` (que dilui igualmente entre os 7 dias mesmo que o período não comece/termine alinhado à semana), é a contagem exata de, por exemplo, quantas terças-feiras caem entre 1/jan e 14/jan.
2. `atividades_agrupadas` — agrupa `atividades_fisicas_treinos` por `(dow, modalidade)`, somando ocorrências e duração total (`extract(epoch from fim−início)/60`).
3. Junta os dois: `media_ocorrencias_por_semana = ocorrências ÷ contagem_dow`, `media_duracao_minutos_por_semana = duracao_total_minutos ÷ contagem_dow`.

**Verificado ao vivo** (janela controlada de 14 dias/2 semanas exatas, isolada em 2019 para não colidir com dados reais já sincronizados do usuário de teste): 2 corridas na mesma terça-feira (uma em cada semana, 30min + 45min) → `ocorrencias_totais: 2`, `semanas_do_periodo: 2`, `duracao_total_minutos: 75`, `media_duracao_minutos_por_semana: 37.5` (75÷2, não 75÷14 nem 75÷7). 1 natação só na 1ª semana → `media_ocorrencias_por_semana: 0.5` (1÷2) — captura corretamente que a atividade não é semanal.

Dias da semana sem nenhuma atividade no período aparecem como `[]` (chave sempre presente, nunca omitida) — decisão para o consumidor da API nunca precisar tratar "chave ausente" como um caso especial.

### 2.3 — Carga do Atleta

`horas_totais_periodo` = soma de todas as durações de treino (qualquer dia, qualquer modalidade) no período inteiro, em horas. `semanas_no_periodo = dias_totais ÷ 7` (fracionário, não arredondado antes da divisão final — um período de 10 dias vale 1.43 semanas, não 1 ou 2). `media_semanal_horas = horas_totais_periodo ÷ semanas_no_periodo`.

Verificado ao vivo: 3 treinos somando 135 minutos (2.25h) num período de 14 dias (2 semanas exatas) → `media_semanal_horas = 1.125h ≈ 1.13` (arredondado a 2 casas, conferido manualmente).

## 3. Motor de Composição Corporal

Implementado como **trigger `BEFORE INSERT`** em `anamneses` (`anamneses_trg_computar_campos_automaticos`), não como lógica dentro de uma RPC — cobre automaticamente **os 2 caminhos de escrita** (App self-service via `.insert()` direto pela RLS `anamneses_insert_own`, e `profissional_salvar_anamnese`) sem precisar duplicar a lógica nos dois lugares nem tocar no Flutter.

Regra: quando `peso_kg` e `percentual_gordura` estão presentes E (`massa_gorda_kg` ou `massa_magra_kg` vêm nulos), calcula:
- `massa_gorda_kg = peso_kg × (percentual_gordura ÷ 100)`
- `massa_magra_kg = peso_kg − massa_gorda_kg`

**Decisão de design**: só preenche o que vier NULO — nunca sobrescreve um valor já informado explicitamente (ex.: profissional com bioimpedância própria dando `massa_magra_kg` de um método mais preciso que a derivação simples peso×%gordura). Verificado ao vivo: payload com `peso_kg=80, percentual_gordura=20` (sem massa) → `massa_gorda_kg=16, massa_magra_kg=64` calculados; payload com `massa_gorda_kg=999` explícito → preservado intacto, `massa_magra_kg` calculado em cima dele (`80−999`), nunca substituindo o 999.

## 4. Estrutura para Dieta Baseada em IA e Restrições

- `anamneses.restricoes_culturais_religiosas text[]` — mesmo padrão de `restricoes_alimentares`/`intolerancias_alimentares` (array livre, sem catálogo curado, `default '{}'`).
- `anamneses.refeicoes_diarias_habituais jsonb` — array de refeições, schema documentado em comentário de coluna: `{numero_refeicao, horario "HH:MM", fora_de_casa bool, descricao_texto, kcal, proteina_g, carboidrato_g, gordura_g}`. `CHECK` garante que, quando não nulo, é um `jsonb` do tipo `array` (`jsonb_typeof(...) = 'array'`) — validação de forma, não de conteúdo (cada objeto do array pode ter qualquer subconjunto das chaves, já que é um rascunho que a IA/usuário preenche incrementalmente). Verificado ao vivo: array de 2 refeições gravado corretamente; um objeto solto (não-array) rejeitado pelo `CHECK` como esperado.
- `profissional_salvar_anamnese` estendida para aceitar os 2 campos no payload (opcionais — quem não enviar continua funcionando exatamente como antes).

## 5. Parâmetro e Validade (Expiração)

- `configuracoes_sistema` ganha a linha `anamnese_dias_validade_padrao = '30'` (mesma infraestrutura chave/valor já usada por outros parâmetros do sistema).
- `anamneses.data_validade timestamptz` — nova coluna.
- Regra de gravação, implementada no **mesmo trigger** do Item 3 (`BEFORE INSERT`, só preenche se vier `NULL`):
  - **Profissional**: `profissional_salvar_anamnese` agora aceita `p_payload.data_validade` — quando presente, é gravada tal qual, e o trigger nunca a toca (chega já não-nula).
  - **Self-service**: o App nunca envia esse campo (nenhuma mudança no Flutter) — chega sempre `NULL`, e o trigger calcula `data_preenchimento + anamnese_dias_validade_padrao dias`.

Verificado ao vivo nos dois caminhos: self-service sem valor → `data_validade = data_preenchimento + 30 dias` (diferença < 1 minuto na comparação, dentro da tolerância de execução); profissional com `data_validade: '2030-06-15T00:00:00Z'` explícita → gravada exatamente, não sobrescrita.

## Verificação — resumo

Dois scripts Node temporários (magic link, usuário real `atleta1000@teste.com` para os itens 1/2/3/4/5 self-service, e `educarmo@gmail.com` autenticado como profissional para o caminho `profissional_salvar_anamnese`), todos os dados de teste inseridos e depois apagados (incluindo um vínculo profissional-paciente temporário, restaurado ao estado original). Destaque do processo: a primeira tentativa de testar `processar_medias_smartwatch` usou uma janela de "últimos 14 dias" e foi contaminada por dados **reais** já sincronizados do wearable deste usuário de teste — corrigido isolando a verificação numa janela histórica (2019) sem nenhuma sobreposição possível, e documentado aqui como lição (mesmo espírito de "nunca confiar em verificação sem isolamento adequado" já estabelecido nesta sessão).

- Item 1: 3/3 checks.
- Item 2: 15/15 checks (após isolar a janela).
- Item 3: 4/4 checks (cálculo + não-sobrescrita).
- Item 4: 3/3 checks (2 campos + CHECK constraint).
- Item 5: 2/2 checks (self-service) + 5/5 checks (caminho profissional, incluindo confirmação de que a reescrita de `profissional_salvar_anamnese` não desalinhou nenhuma coluna).

Migration aplicada em produção (`supabase db push --linked`), `supabase migration list --linked` confirma `local=remote`.

## Fora do escopo desta tarefa (documentado, não esquecido)

- Nenhuma tela (Flutter/React) consome ainda `iniciar_rascunho_anamnese`/`processar_medias_smartwatch` — são RPCs prontas, aguardando uma tarefa futura de integração de UI (fora do `ARQUIVOS`/`RESTRIÇÕES` desta tarefa, que pediu 100% Backend).
- `refeicoes_diarias_habituais` não tem nenhuma IA consumindo-a ainda — o item pedia só "o schema pronto", não a integração da IA em si.
- `iniciar_rascunho_anamnese` copia só os 4 grupos citados literalmente na tarefa (sexo/doenças/alergias/restrições) — outros campos "óbvios" (peso, altura, objetivo) foram deliberadamente deixados de fora.
