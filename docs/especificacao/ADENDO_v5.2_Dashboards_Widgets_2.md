# ADENDO v5.2 AO DOCUMENTO MESTRE v5.0
## Dashboards Configuráveis (Paciente e Profissional), Arquitetura de Análise em 3 Níveis e Análises Complexas Pagas

**Data:** 22 de Julho de 2026
**Acopla-se a:** DOCUMENTO MESTRE v5.0 + ADENDO v5.1.
**Precedência:** v5.2 > v5.1 > v5.0 > anteriores.
**Uso:** cole v5.0 + v5.1 + este v5.2. Será incorporado ao corpo na próxima consolidação (v6.0).

---

# A. ARQUITETURA DE PROCESSAMENTO EM 3 NÍVEIS (princípio central)

Todo widget de análise do painel B2B declara um **nível**, que determina QUANDO e COMO é calculado. Isso permite "dezenas de widgets" sem explodir custo/performance.

## A.1 Nível 1 — Contagem simples (tempo real, sem IA, sem custo)
Consultas SQL diretas com filtro/contagem (ex.: nº de pacientes, pendentes de convite, sem registro alimentar). Calculado **na hora**, ao abrir o dashboard. Barato, sem pré-cálculo necessário.

## A.2 Nível 2 — Correlação/padrão (pré-calculado, no fechamento do período)
Cruzamento de múltiplas fontes por paciente (sono×treino, alimentação×exames). Caro para calcular a cada clique → calculado **uma vez por período** (diário/semanal/mensal, conforme o widget) por **Cron** (mesmo mecanismo dos rankings e da Retrospectiva Mensal), resultado **gravado em tabela**. Ao clicar, o profissional lê resultado pronto, não recalcula.

## A.3 Nível 3 — Análise complexa assistida por IA (sob demanda, paga por execução)
Roda só quando o profissional pede explicitamente (ex.: antes de consulta). Consome Gemini de verdade. Resultado **gravado permanentemente** (não precisa re-rodar para consultar depois). **Exclusiva do painel profissional — NUNCA disponível ao paciente/app B2C** (reforça blindagem ANVISA, Parte 5.2: interpretação clínica só no painel CRM/CRN, nunca ao leigo). Modelo de cobrança: créditos/execuções, adicional ao pacote fixo (Parte 2.1) — terceira linha de receita.

## A.4 Regra de implementação
Todo widget tem: `nivel` (1/2/3), `periodo_suportado` (diário/semanal/mensal/sob_demanda), `fonte_calculo` (SQL direto / Cron agregado / Gemini). Um catálogo central de definições de widget (Seção E) governa isso — não hardcoded por tela.

---

# B. TELA INDIVIDUAL DO PACIENTE (Painel B2B)

## B.1 Busca
Campo único de busca incremental (busca conforme digita) por **nome, CPF ou e-mail**, respeitando a criptografia de PII (busca via função server-side, análoga a `resolver_usuario_id_por_email` já existente — Parte 3.4 do v5.0) — nunca expor índice de busca em texto plano sobre dado criptografado.

## B.2 Estrutura da tela
- **Cabeçalho fixo:** dados do paciente (nome, idade, tipo de vínculo, data de início do acompanhamento).
- **Sub-abas (a primeira é sempre Dashboard):**
  1. **Dashboard** — grade de widgets configuráveis (Seção C).
  2. **Telemetria** — wearables (G.3/G.4 do v5.0).
  3. **Alimentação** — diário alimentar (`diario_alimentar_diario`).
  4. **Exames** — `resultados_exames` (EAV), com faixas do laboratório (Parte 5.2).
  5. **Insights/Correlações** — resultados de Nível 2 em formato narrativo + gráfico.
  6. **Análises Complexas (Nível 3)** — histórico de análises pagas já executadas para este paciente, permanentes, consultáveis sem custo adicional após geradas.

## B.3 Interação de widget
Clique no widget do Dashboard → abre gráfico/tabela da análise + observações textuais (para Nível 2/3) ou apenas o número/lista (Nível 1).

---

# C. CATÁLOGO DE WIDGETS — DASHBOARD DO PACIENTE

## C.1 Nível 1 (simples, tempo real)
- Consistência de registro (dias da semana com uso real do app — proxy de engajamento, diferente de adesão ao plano).
- Adesão a medicamentos (% de doses registradas no horário).
- Defasagem de exames (tempo desde o último exame novo).
- Tendência de FC de repouso / HRV (se o wearable fornecer).

## C.2 Nível 2 (correlação, pré-calculado)
- Perda/ganho de peso no período.
- Qualidade de sono × rendimento em treino.
- Alimentação × treino.
- Nutrientes × exames.
- Treino × exames.
- Sono × humor/energia (autorrelato).
- Regularidade de treino × tendência de peso.
- Aderência à prescrição (F26, quando existir) × resultado observado.
- **Janela de queda de engajamento** (paciente estava ativo e caiu — alerta precoce para o profissional agir antes do abandono do vínculo).

---

# D. DASHBOARD DO PROFISSIONAL (meta-dashboard, "resumo geral dos pacientes")

## D.1 Conceito
Mesmo princípio configurável do dashboard do paciente. Cada widget carrega **nome + período** (ex.: "Pacientes sem registro alimentar — Semanal"). Profissional pode ter o mesmo widget em períodos diferentes (ex.: diário E mensal, lado a lado). Nomenclatura: `{nome_da_analise} {periodo}`.

## D.2 Definição de período
- **Diário:** 00:00 às 23:59:59 do dia anterior.
- **Semanal:** segunda a domingo da última semana fechada.
- **Mensal:** dia 1 ao último dia do mês anterior.
Período é atributo do widget configurado pelo profissional, não fixo por tipo de análise.

## D.3 Interação
Clique no número/detalhe do widget → **lista de pacientes** que compõem aquela informação (drill-down para ação, não gráfico). Objetivo declarado: permitir que o profissional **entre em contato e demonstre acompanhamento ativo** — diferencial competitivo real contra Dietbox/Nutrium/DietSystem.

## D.4 Catálogo de widgets (confirmados + sugeridos)
**Do fundador:**
- Número de pacientes total e pendentes de aceite do convite.
- Pacientes que não registraram ≥2 refeições/dia no período.
- Pacientes com eventos (anomalias/Caixa Preta) no período.
- Pacientes que não realizaram atividades programadas no período.
- Conquista importante do paciente no período.

**Sugestões adicionais:**
- **Pacientes inativos** (sem abrir o app há N dias — sinal direto de risco de abandono do vínculo).
- Convites pendentes há mais de X dias (para cutucar aceite).
- Distribuição de slots do pacote (usados/contratados — ajuda o profissional a saber se precisa upgrade, e é sinal comercial para nós).
- Pacientes com anomalia na Caixa Preta no período (prioridade de contato clínico).
- Aniversário de acompanhamento (ex.: "3 meses com você" — gancho de relacionamento humano).

---

# E. SCHEMA DE BANCO (novas entidades)

## E.1 `catalogo_widgets` — definição central (fonte de verdade de todo widget disponível)
`widget_codigo` (PK), `escopo` (paciente / profissional), `nome_exibicao_pt/en/es`, `nivel` (1/2/3), `periodos_suportados` (array: diário/semanal/mensal/sob_demanda), `fonte_calculo` (sql_direto / cron_agregado / gemini_sob_demanda), `categoria` (nutrição/treino/sono/exames/engajamento/financeiro), `descricao_curta`.
Extensível: novo widget = nova linha aqui, não código novo por tela.

## E.2 `configuracao_dashboard` — o que cada profissional/paciente escolheu exibir
`usuario_id` (paciente OU profissional), `escopo`, `widget_codigo` (FK), `periodo_escolhido`, `posicao` (ordem no grid), `ativo` (bool). Um profissional pode ter o mesmo `widget_codigo` duas vezes com `periodo_escolhido` diferente (linhas distintas).

## E.3 `resultados_analise_nivel2` — cache de correlações pré-calculadas
`paciente_id`, `widget_codigo`, `periodo` (diário/semanal/mensal), `data_referencia` (início do período calculado), `valor_numerico`/`payload_jsonb` (gráfico/tabela), `observacoes_texto` (narrativa curta gerada por regra determinística ou template — sem IA na maioria dos casos de Nível 2), `calculado_em`. Gerado pelo Cron do fechamento do período (reaproveita o mesmo motor já usado para rankings/Retrospectiva Mensal — Parte 7.3 do v5.0). Índice `(paciente_id, widget_codigo, periodo, data_referencia DESC)`.

## E.4 `analises_complexas_nivel3` — execuções pagas, permanentes
`id`, `paciente_id`, `profissional_id` (quem solicitou/pagou), `widget_codigo` ou `tipo_analise_livre`, `prompt_usado` (auditoria), `resultado_jsonb`, `custo_creditos`, `solicitado_em`, `status` (processando/concluído/erro). **Nunca acessível pelo app do paciente** — RLS restrita ao profissional solicitante + vínculo ativo. Consulta futura ao mesmo resultado = grátis (já está gravado); nova execução = novo débito de créditos.

## E.5 `creditos_profissional` — saldo para análises Nível 3
`profissional_id`, `saldo_creditos`, `historico_transacoes` (compra/consumo). Terceira linha de receita, adicional ao pacote fixo (Parte 2.1).

## E.6 Regras de segurança aplicadas (herdadas da Parte 6 do v5.0)
- GRANT explícito em todas as tabelas novas (regra Parte 0.10).
- RLS: `resultados_analise_nivel2` e `analises_complexas_nivel3` seguem a mesma fonte única de verdade que métricas/anomalias (`vinculos_profissional_paciente` — Parte 3.4), nunca acesso direto sem vínculo ativo aceito.
- `analises_complexas_nivel3` alimenta o log de auditoria (S5) — quem solicitou, quando, sobre qual paciente.
- Busca por CPF/e-mail (B.1): via função server-side restrita, nunca índice em texto plano sobre campo criptografado.

---

# F. MODELO DE PRECIFICAÇÃO — ATUALIZAÇÃO (acrescenta à Parte 2 do v5.0)

## F.1 Terceira linha de receita: créditos de Análise Complexa (Nível 3)
Adicional aos pacotes fixos (Essencial R$97 / Performance R$167). Profissional compra créditos/execuções; cada análise complexa debita créditos; resultado fica gravado para sempre (sem custo de releitura). Calibração de preço por crédito: a definir (referência de custo real do Gemini por execução deve ser levantada antes de precificar ao profissional).

---

# G. SEQUENCIAMENTO (Diretor de Produto — nota de disciplina)
- **Nível 1 (widgets simples, ambos dashboards):** pode entrar cedo, junto com o painel básico da Onda 4.
- **Nível 2 (correlações pré-calculadas) e Nível 3 (análise paga):** pós-validação — construir depois que houver profissionais reais usando o painel básico e pedindo por eles. Desenho já pronto (este adendo); construção sequenciada, não simultânea ao Nível 1.

---

# H. ATUALIZAÇÃO DO LOG DE DECISÕES (Parte 11 do v5.0)
| Data | Decisão | Motivo |
|---|---|---|
| 22/Jul/2026 | Arquitetura de widgets em 3 níveis (SQL direto / Cron pré-calculado / IA sob demanda paga) | Permite dezenas de widgets sem explodir custo/performance |
| 22/Jul/2026 | Nível 3 (análise complexa por IA) exclusivo do painel profissional, nunca do app do paciente | Reforça blindagem ANVISA — interpretação clínica só via CRM/CRN humano |
| 22/Jul/2026 | Nível 3 cobrado por crédito/execução, adicional ao pacote fixo; resultado gravado permanentemente | Terceira linha de receita; releitura não gera novo custo |
| 22/Jul/2026 | Dashboard configurável (paciente e profissional) via catálogo central de widgets, não hardcoded | Extensibilidade: novo widget = nova linha, não novo código |
| 22/Jul/2026 | Widget do profissional = nome+período como atributo escolhido (mesmo widget, períodos distintos) | Flexibilidade de acompanhamento (diário/semanal/mensal simultâneos) |
| 22/Jul/2026 | Clique em widget do profissional → lista de pacientes (drill-down para ação) | Objetivo de negócio: permitir contato ativo e diferencial de acompanhamento |
| 22/Jul/2026 | Nível 1 na Onda 4 (painel básico); Nível 2/3 pós-validação | Sequenciamento — construir sob demanda comprovada |

---

*Fim do Adendo v5.2. Para continuidade: cole v5.0 + v5.1 + v5.2 em qualquer nova sessão. Será incorporado ao corpo na v6.0 no próximo marco.*
