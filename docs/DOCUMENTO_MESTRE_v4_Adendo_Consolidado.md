# ADENDO v4.0 AO DOCUMENTO MESTRE — CONSOLIDAÇÃO DE DECISÕES
## Plataforma de Saúde Preventiva Baseada em IA

**Data:** Julho de 2026
**Como usar este arquivo:** Este adendo acopla-se ao DOCUMENTO MESTRE v3.0. Onde houver conflito, **este adendo v4.0 prevalece** (é mais recente). As seções abaixo indicam se SUBSTITUEM ou ACRESCENTAM conteúdo ao v3.0. Para uma nova IA assumindo o projeto: leia o v3.0 inteiro primeiro, depois aplique este v4.0 por cima.

**Regra de precedência atualizada:** v4.0 (este) > v3.0 > documentos anteriores.

---

# A. ATUALIZAÇÃO DE MERCADO E CONCORRENTES (SUBSTITUI Partes 1.4 e 1.5 do v3.0)

## A.1 Categoria validada globalmente (novo)
A convergência exames laboratoriais + wearables + nutrição já é uma categoria consolidada nos EUA, o que **valida a tese** (não é mais preciso evangelizar o conceito) e ao mesmo tempo **refina o fosso** (não somos mais "os únicos que cruzam dados"). Players de referência:
- **InsideTracker** — pioneiro; ~50 biomarcadores de sangue + 1.500+ marcadores de DNA; integra Garmin, Apple Health, Fitbit; permite upload dos próprios exames; foco performance/longevidade.
- **OneTwenty** (ex-Outlive.bio) — o mais próximo da nossa visão; painéis laboratoriais trimestrais + 500+ sinais diários de wearables (Oura, Whoop, Apple Watch, balança, pressão) **vinculados diretamente aos exames**; inclui clínicos e prescrição (fora do nosso escopo).
- **Function Health** — o mais amplo em exames (~100 na coleta inicial + ~60 no meio do ano); captou US$ 300M; foco em amplitude diagnóstica e detecção precoce.
- **Superpower** — 100+ biomarcadores a US$ 199/ano; care team + IA + idade biológica; entrada de baixo preço.
- **Movimento estratégico:** Whoop e Oura adicionaram exames de sangue via Quest (<US$ 200) — os donos de wearables estão comprando o lado laboratorial. Sinal de que a janela de consolidação está aberta agora.

**Diferença regulatória crítica (registrar):** essas plataformas **são as testadoras** (coletam sangue, definem painel, respondem clinicamente — território CLIA/FDA nos EUA). **Nosso produto NÃO faz isso:** o usuário já possui o exame (feito no laboratório dele) e nós apenas lemos o PDF, extraímos e organizamos a série temporal. Somos **organizador de dados que o usuário já possui**, não plataforma de diagnóstico. Essa distinção é o que nos mantém fora do enquadramento SaMD (ver reforço em E).

## A.2 Concorrente B2B nacional a monitorar (novo)
- **DietSystem** (R$ 79,90/mês) — já faz extração de exames por IA (PDF), análise de refeição por foto, app nativo do paciente e WhatsApp oficial. É o concorrente B2B mais próximo.
- **SimpleDiet** (R$ 27,90/mês) — upload de PDF de exames com extração automática.
- **O que nenhum deles tem** (nosso diferencial B2B): telemetria contínua de wearables (Garmin, sono, FC, glicose) cruzada aos exames e à nutrição, e o loop profissional→prescrição de treino→relógio via Garmin Training API.

## A.3 Fosso defensável refinado (substitui a antiga formulação)
Não é "somos os únicos que cruzam dados". É a combinação, que nenhum player reúne: **(1) Brasil-first** (PDF de laboratórios locais, idioma, preço, exames do SUS/Fleury/Dasa/Pardini) + **(2) telemetria contínua de wearables** que os softwares de nutrição BR não têm + **(3) motor de retenção gamificado** que as plataformas de biomarcadores não têm + **(4) captura por foto de aparelhos analógicos** (glicosímetro/pressão de braço do público sênior sem wearable caro) + **(5) o loop completo** profissional→prescrição→relógio Garmin.

---

# B. TABELA DE PREÇOS (ACRESCENTA à Parte 1; substitui os tickets citados em 1.2 e 1.6)

## B.1 B2B — Pacote por profissional, com DUAS dimensões
O preço do profissional é função de **duas dimensões combinadas**, e o valor é **fixo por faixa** (o profissional paga o pacote e usa até o teto; não é cobrado proporcionalmente aos vínculos efetivamente usados):

**Dimensão 1 — Faixa de pacientes (slots):** ex. até 15 / até 40 (ajustável).
**Dimensão 2 — Tipo de produto:** com ou sem **envio de treino ao Garmin** (Garmin Training API). Separa o nutricionista (sem Garmin) do treinador/personal (com Garmin).

Preços de referência (calibrar no lançamento):
- **Essencial (sem Garmin, até 15 pacientes): R$ 97/mês.** Acima do DietSystem (R$ 79,90) para sinalizar categoria superior, perto o bastante para a comparação não doer.
- **Performance (com Garmin, até 40 pacientes): R$ 167/mês.** O plano do treinador; o Garmin é argumento sem concorrente.
- **Fundadores:** primeiros 10–20 profissionais com desconto vitalício (ex. R$ 67) em troca de feedback e depoimento.
- Margem > 80% em ambos (custo de IA agregado R$ 0,30–0,60/mês por carteira).

## B.2 B2C — Usuário individual
- **Anual (herói do funil): R$ 179,90/ano** (≈ R$ 15/mês). Mantido — bem calibrado contra MyFitnessPal/Lifesum (~R$ 31,90/mês).
- **Mensal (âncora, não para vender): R$ 34,90/mês.** Existe para fazer o anual parecer barato ("economize 57%") e dar margem melhor a quem escolher mensal.
- **Regra:** não lançar B2C com desconto (preço baixo vira âncora permanente). Se precisar de tração, estender o trial (21 dias), nunca cortar preço.
- LTV do anual ≈ R$ 142 líquidos/ano (após loja 15% + imposto 6%). **Teto de CAC = R$ 142; meta de CAC ≤ R$ 47** (1/3 do LTV).

## B.3 Relação entre pagadores (ver Parte F — modelo multi-profissional)
O paciente que entra **via profissional não paga** o app e **não recebe nenhum gatilho de venda**. Só há cobrança B2C quando o próprio usuário opta pelo plano individual.

---

# C. DICIONÁRIO DE BIOMARCADORES — NÚCLEO BRASILEIRO (ACRESCENTA à Parte 2)

## C.1 Princípio
Não temos painel próprio de exames (não coletamos sangue). Esta é uma **lista de reconhecimento/normalização** do OCR: o que o extrator deve saber identificar e padronizar quando aparecer no PDF que o usuário enviar. Prioriza o que os laboratórios brasileiros (Fleury, Dasa, Hermes Pardini, SUS) realmente reportam.

## C.2 Núcleo essencial (com chave universal normalizada — regra i18n)
- **Metabólico:** glicose de jejum (`blood_glucose`), HbA1c (`hba1c`), insulina (`insulin`), HOMA-IR (`homa_ir`, calculável).
- **Lipídico:** colesterol total (`total_cholesterol`), LDL (`ldl`), HDL (`hdl`), triglicérides (`triglycerides`), **ApoB (`apob`)** e **Lp(a) (`lpa`)** — os dois marcadores cardiovasculares mais preditivos que os painéis básicos pulam; diferencial barato.
- **Tireoide:** TSH (`tsh`), T4 livre (`free_t4`), T3 (`t3`).
- **Fígado:** AST/TGO (`ast`), ALT/TGP (`alt`), GGT (`ggt`).
- **Rim:** creatinina (`creatinine`), ureia (`urea`), TFG (`egfr`), microalbuminúria (`microalbuminuria` — chave para diabético/hipertenso do perfil Guardião).
- **Sangue:** hemograma completo (`cbc` + componentes).
- **Inflamação:** PCR ultrassensível (`hs_crp`), homocisteína (`homocysteine`).
- **Vitaminas/minerais:** vitamina D (`vitamin_d`), B12 (`vitamin_b12`), ferritina (`ferritin`), ferro (`iron`).
- **Hormônios:** testosterona (`testosterone`), cortisol (`cortisol`).
- **Outros:** ácido úrico (`uric_acid`).

## C.3 Fora do escopo do dicionário (deliberado)
DNA/genética (outro produto, outro passivo), metais pesados e autoimunidade exótica (raros nos PDFs brasileiros comuns). Regra: o extrator reconhece o que o brasileiro testa e **guarda graciosamente o valor bruto do que não conhece** (em JSONB de metadados), sem tentar normalizar — para nunca perder dado.

## C.4 Tabela-dicionário de referência (obrigatória)
Criar `marcadores_referencia`: `marcador_codigo` (PK), `nome_exibicao_pt/en/es`, `categoria`, `unidade_padrao`, `faixa_referencia_min/max`, `direcao_saudavel` (maior_melhor / menor_melhor / faixa). Dá à IA o contexto semântico sem hardcode e separa a tradução i18n do dado bruto.

---

# D. NOVA FEATURE — ÍNDICE DE BEM-ESTAR / IDADE BIOLÓGICA (ACRESCENTA à Parte 4 do v3.0 como F31)

- **F31 — Índice de Bem-Estar (estilo "idade biológica"):** gancho de marketing nº1 das plataformas globais (ex. PhenoAge). Apresentado **exclusivamente como índice de bem-estar/estilo de vida**, jamais como diagnóstico ou idade clínica. É a evolução natural da "Projeção de Hábitos e Consistência" (v3.0, 3.4/5.2).
- **Faixas ótimas vs. normais:** a lógica de "alvo ideal" com código de cor (verde/amarelo/vermelho) vive **no painel do profissional** (interpretação é do CRM/CRN), nunca como veredito da IA no app do paciente.
- Cálculo **server-side** (regra da Parte 3.5), baseado em hábitos e consistência; se usar marcadores, apenas de forma agregada e não-diagnóstica no B2C.

---

# E. REFORÇO REGULATÓRIO — "ORGANIZADOR DE DADOS" vs. "PLATAFORMA DE DIAGNÓSTICO" (ACRESCENTA à Parte 5.2 do v3.0)

Registrar explicitamente como argumento central de blindagem SaMD: **o produto não coleta sangue, não define painel, não emite resultado laboratorial e não interpreta clinicamente para o usuário.** Ele lê um exame que o laboratório do usuário já produziu, extrai e organiza a série temporal. Isso o diferencia juridicamente das plataformas-testadoras (Function/InsideTracker/etc.) e sustenta o enquadramento de bem-estar. A interpretação clínica é sempre do profissional humano no painel B2B. SpO2/oximetria e demais métricas beirando o clínico: exibir tendência/número no app é ok; **nunca** alertar ação clínica ao usuário.

---

# F. MODELO MULTI-PROFISSIONAL — VÍNCULOS, PRIVACIDADE, GAMIFICAÇÃO E CICLO DE VIDA (ACRESCENTA nova Parte ao v3.0)

## F.1 Duas portas de entrada
- **Via profissional:** cadastro e pagamento vêm do profissional. **Nenhum gatilho de venda individual** (paywall, cenoura do dia 7, lembretes de assinatura são suprimidos). Toda a gamificação (ofensiva, pontos, chama, rankings) **é mantida integralmente**.
- **Individual:** o usuário paga o próprio plano (B2C) e **controla, classe por classe, o que compartilha** (nada é compartilhado por padrão).

## F.2 O vínculo é a unidade central (banco + faturamento)
Criar `vinculos_profissional_paciente`: `profissional_id`, `paciente_id`, `status` (ativo / em_carencia / encerrado), `tipo_pagador` (profissional / individual), `tipo_produto` (com_garmin / sem_garmin, herdado do pacote do profissional), datas (início, saída, fim_carencia).
- **Múltiplos profissionais por paciente:** permitido. Um mesmo paciente pode ser pago por vários profissionais simultaneamente. Cada profissional **paga pelo seu próprio acesso** àquele paciente (o paciente compartilhado gera receita de N vínculos, um por profissional — não é cobrança dupla ao mesmo profissional).
- **O vínculo consome 1 slot do pacote do profissional.** A contagem de "pacientes ativos" de um profissional = nº de vínculos ativos dele. Um mesmo paciente conta 1 slot para **cada** profissional que o acompanha.
- **Preço fixo por faixa:** o profissional paga o valor do pacote (faixa de pacientes × tipo de produto) e usa até o teto; não é cobrado por vínculo avulso.
- O `tipo_produto` no vínculo habilita/desabilita o botão "enviar treino ao Garmin" naquele relacionamento.

## F.3 Escopo de consentimento POR VÍNCULO
Criar tabela de escopo referenciando o **vínculo** (não o profissional global): por classe de dados (exames, wearables, nutrição, medicamentos, autorrelatos), registra se aquele profissional pode ver.
- Via profissional: escopo **amplo por padrão** (o paciente entrou para ser acompanhado), mas **visível e revogável** — se o paciente restringe uma classe, o profissional vê que foi restringida.
- Individual: **nada liberado por padrão**; o usuário libera classe por classe.
- Alimenta o log de auditoria (S5): cada acesso é rastreado por vínculo (qual profissional viu qual classe de qual paciente e quando). Argumento de privacidade vendável: "você decide exatamente o que cada profissional vê".

## F.4 Gamificação estendida
- **Liga por profissional:** nova liga (pacientes de um mesmo profissional competindo). Segue o **padrão anônimo já definido** (nickname + avatar entre pacientes; só o profissional vê nomes reais no painel).
- **Desafios do profissional:** nova entidade `desafios` (`profissional_id`, título, critério, período). Reaproveita o motor de streak/pontos. Pontos dos desafios contam em **placar separado do grupo**, não nos rankings geográficos públicos (evita distorção).
- **Na saída do vínculo:** pontos e histórico **pessoais são do usuário** (ele mantém); ele apenas sai da liga/desafios daquele profissional. Progresso individual preservado.

## F.5 Ciclo de vida e mensagens (revisar sistema de mensagens)
- **Carência dispara por ausência de acesso ativo, não por vínculo isolado.** Verificação server-side no login/refresh: "o usuário tem alguma fonte de acesso ativa (algum profissional pagante OU plano individual)?" Se sim → segue pleno. Se um de vários profissionais o remove mas outro vínculo pago continua → **não entra em carência**.
- Quando o usuário fica **sem nenhum acesso ativo:** recebe comunicado (push + tela), ganha **30 dias** de acesso completo, e pode optar pelo plano individual. Tom de convite, nunca de punição (microcopy Parte 8.5, i18n pt/en/es). Nudges progressivos (dia 1 informativo, dia 20 lembrete, dia 28 última chamada).
- **Fim dos 30 dias sem conversão: bloqueado até reativar.** Dados **preservados** (não apagados), **chama pausada** (não zerada). Se voltar depois, reativa sem trauma. Exclusão de dados só a pedido do titular (LGPD).

## F.6 Impacto por camada (checklist de implementação)
- **Banco:** `vinculos_profissional_paciente` (com status/pagador/produto/datas), tabela de escopo por vínculo, campo `pagador` na assinatura, entidade `desafios`.
- **Gamificação:** liga por profissional, desafios, regra de pontos na saída.
- **Mensagens:** jornada de ciclo de vida (não uma msg só), i18n.
- **Permissões/auditoria:** escopo por vínculo alimenta o log S5.
- **Paywall:** bifurcação por `pagador` (suprime venda para via-profissional).

---

# G. ARQUITETURA DE DADOS DE SAÚDE — MODELO FINAL EM MÚLTIPLAS TABELAS (SUBSTITUI/DETALHA a Parte 2.2 do v3.0)

Princípio: **separar por natureza do dado, não por tipo de saúde.** Cada tabela recebe a modelagem que lhe cabe.

## G.1 `resultados_exames` — EAV (pontual, laboratorial)
Formato longo, uma linha por medição: `usuario_id`, `marcador_codigo`, `valor_numerico`, `valor_texto` (não-numéricos), `unidade`, `data_coleta`, `origem` (=pdf_exame), `laboratorio` (opcional), `criado_em`. Índice composto `(usuario_id, marcador_codigo, data_coleta DESC)`. **Normalização de unidade na entrada** (na Edge Function), guardando a unidade original. Glicose de exame vive aqui.

## G.2 `coleta_diaria` — EAV (frequente; device / OCR / manual)
Mesma filosofia EAV (extensível sem ALTER TABLE para métricas futuras): `usuario_id`, `marcador_codigo`, `valor`, `unidade`, `origem` (device / ocr_foto / manual), `confianca` (score do OCR/Gemini para leituras por foto), `data_registro`. Recebe: **pressão arterial, oximetria (SpO2), glicose de glicosímetro de dedo, peso/composição (Fitdays via device ou OCR do visor), temperatura, e autorrelatos** (humor, energia, dor — ver H). O campo `origem` é obrigatório (confiabilidade, auditoria, antifraude); a mesma métrica pode chegar por 3 caminhos e deve cair na mesma série.

## G.3 `metricas_saude_diarias` — COLUNAS FIXAS (agregado de wearable)
Uma linha por usuário por dia, agregados de alta frequência: passos totais, FC média/repouso/máxima, sono, etc. Estrutura conhecida e imutável → coluna fixa é mais compacta e rápida que EAV aqui.

## G.4 Alta frequência bruta — COLUNAS FIXAS + FIFO 3 dias
Ex.: frequência cardíaca contínua. Estrutura fixa (timestamp + valor + tipo). **Janela FIFO de 3 dias** no bruto (entra novo, sai o de 3 dias atrás — teto fixo, sem inchaço). **Consolidação no device, em lote, na janela de background noturna** (aparelho na tomada + Wi-Fi): o Health Connect/HealthKit acumulam o bruto localmente (de graça); o app consolida 1x/dia e envia ao servidor **apenas o agregado diário (G.3) + eventos de anomalia (G.5)**. O bruto granular **nunca sobe** (mais barato, mais privado, menor superfície de risco). Ver justificativa em G.7.

## G.5 `eventos_anomalias_saude` — Caixa Preta (permanente)
Se, durante a consolidação noturna no device, um padrão de distúrbio for detectado, o evento é gravado com a granularidade fina daquele momento e **persistido no servidor** (o servidor recebe o evento já consolidado, valida e grava — mantém a regra server-side como fonte de verdade do que fica registrado). Permanente (não entra no FIFO).
- **Definição de anomalia = desvio estatístico do baseline do próprio usuário**, NUNCA limiar clínico absoluto (limiar absoluto tipo "FC>120=perigo" caracteriza dispositivo médico). Ex.: "FC fora da faixa usual deste usuário em repouso".
- **Sem interpretação clínica ao usuário:** a anomalia é dado silencioso (alimenta Caixa Preta + painel do profissional). No máximo, convite neutro ("registramos uma variação fora do seu padrão — vale mostrar ao seu médico").
- Como o critério roda no device, **versioná-lo bem** (ajustes exigem atualização do app).

## G.6 Leitura pela IA (insight)
A IA lê os **resumos textuais curtos pré-consolidados** pelo Cron (não as tabelas brutas): tendências vêm do agregado diário (G.3), momentos críticos dos eventos (G.5). Cada evento de anomalia gera na consolidação uma frase curta que entra no resumo ("dia X: variação de FC fora do padrão em repouso"). Mantém consumo de token baixo. Exames (G.1) entram como série temporal por `marcador_codigo`; a IA usa a `faixa_referencia` da tabela-dicionário (C.4) como contexto semântico.

## G.7 Justificativa da consolidação no device (registro da decisão)
Trade-off avaliado nos 4 eixos: **custo financeiro** (device = R$ 0 de compute servidor; vence), **capacidade de insight** (servidor não ganha nada relevante porque com FIFO 3 dias o valor está nas tendências de médio prazo do agregado, não no bruto curto), **UX** (consolidar em lote noturno no carregamento torna o custo de bateria imperceptível; subir bruto gastaria dados móveis do usuário), **segurança** (granular nunca sai do aparelho = menos passivo LGPD). Os 4 eixos apontam para device.

---

# H. AUTORRELATO E PERGUNTAS AO USUÁRIO (ACRESCENTA à Parte 7 do v3.0)

Regra de ouro: **toda coleta ativa do usuário é opt-in, de toque único, recompensada e DESVINCULADA da ofensiva.**
- Autorrelato (humor, energia, dor, sono percebido) é valioso para a IA e **100% seguro no enquadramento ANVISA** (bem-estar puro), mas **pergunta demais mata a retenção**.
- **Nunca** vincular autorrelato à ofensiva. A chama se mantém só pelo comportamento central (foto de refeição + treino/passos). Autorrelato é a cereja, não o bolo.
- **Máximo uma pergunta por dia, rotativa** (um dia energia, outro sono, outro humor — nunca as três juntas), de **toque único** (escala de carinhas/1-5), oferecida como **missão opcional que dá pontos** ("+5 pontos: como está sua energia hoje?"). Quem responde é recompensado; quem ignora não perde nada.
- No público sênior (Guardião), onde o autorrelato é mais valioso, o Modo Cuidador pode incentivar — sem pressa nem obrigação.

---

# I. DECISÃO DE ARQUITETURA DE APPS (ACRESCENTA à Parte 2 do v3.0)

**Mantida a arquitetura atual — três superfícies, decisão de separação adiada:**
- **Painel Web B2B (React)** — superfície do profissional (a separação profissional↔paciente já existe: profissional = web, paciente = mobile).
- **App mobile único do paciente** — perfil dinâmico via `perfil_uso` (Atleta / Guardião / foto-assíncrono). **NÃO** dois apps de paciente.
- **Companion mobile do profissional** — decisão futura de baixa prioridade (ou PWA do painel web responsivo); o desktop cobre o profissional por ora.

**Opção condicional registrada (não descartada):** "descascar" o perfil Guardião num segundo app dedicado no futuro, reaproveitando ~80% do código sobre o mesmo backend, **se e quando** dados de aquisição comprovarem que uma identidade separada na App Store (ASO/marca por nicho) justifica o custo de manutenção dobrado. Gatilho = dados de aquisição, não engenharia. Justificativa da decisão atual: backend único torna a transição de perfil fluida (o atleta de hoje é o sênior de amanhã), e um app/código/pipeline único é essencial para um fundador solo desenvolvendo via IA.

---

# J. ATUALIZAÇÃO DO REGISTRO DE DECISÕES (ACRESCENTA à Parte 11 do v3.0)

| Data | Decisão | Motivo |
|---|---|---|
| Jul/2026 | Categoria validada globalmente (InsideTracker/OneTwenty/Function/Superpower); fosso refinado | Não somos únicos no cruzamento; diferencial = Brasil-first + wearable + gamificação + loop Garmin |
| Jul/2026 | Somos "organizador de dados", não "plataforma de diagnóstico" | Não coletamos sangue/definimos painel — reforça blindagem SaMD |
| Jul/2026 | DietSystem/SimpleDiet = concorrentes B2B a monitorar | Já fazem exame+foto; nosso diferencial é wearable+Garmin |
| Jul/2026 | Preços: B2B R$97 (sem Garmin/15) e R$167 (com Garmin/40), fixo por faixa; B2C R$179,90/ano + R$34,90/mês âncora | Ancoragem competitiva vs DietSystem e MyFitnessPal |
| Jul/2026 | Dicionário de biomarcadores = núcleo brasileiro (reconhecimento, não painel próprio) | Prioriza PDFs de labs BR; extensível via tabela-dicionário |
| Jul/2026 | F31 Índice de Bem-Estar/idade biológica como bem-estar (não diagnóstico) | Gancho de marketing das plataformas globais, dentro do enquadramento |
| Jul/2026 | Multi-profissional: vínculo = unidade de slot e faturamento; múltiplos pagadores por paciente | Cada profissional paga seu acesso; SaaS multi-assento |
| Jul/2026 | Escopo de consentimento por vínculo | Controle granular por profissional; LGPD + argumento de venda |
| Jul/2026 | Carência/bloqueio avaliada por ausência de QUALQUER acesso ativo; bloqueio preserva dados e pausa chama | Reaproveita usuário engajado; não pune; LGPD |
| Jul/2026 | Dados de saúde em múltiplas tabelas (exames EAV, coleta_diaria EAV, métricas diárias coluna, alta freq. coluna FIFO 3d, anomalias permanente) | Cada natureza de dado na modelagem correta |
| Jul/2026 | Consolidação de alta frequência no device, lote noturno; bruto não sobe | Custo/UX/segurança apontam device; insight não perde com FIFO curto |
| Jul/2026 | Anomalia = desvio do baseline do próprio usuário, sem interpretação clínica ao usuário | Limiar clínico absoluto caracterizaria dispositivo médico |
| Jul/2026 | Autorrelato opt-in, toque único, recompensado, desvinculado da ofensiva | Coleta valiosa sem matar retenção |
| Jul/2026 | App único de paciente; Guardião separável no futuro condicionado a aquisição | Backend único + fundador solo; separação = decisão de marketing futura |

---

# K. IMPACTO NA MATRIZ DE STATUS (ACRESCENTA à Parte 3.2 do v3.0)

Novas funcionalidades/entidades PENDENTES a incluir na matriz (todas 🔲):
- F31 — Índice de Bem-Estar / idade biológica (bem-estar, server-side).
- F32 — `marcadores_referencia` (tabela-dicionário i18n + faixas).
- F33 — `resultados_exames` refinado (EAV + normalização de unidade).
- F34 — `coleta_diaria` (EAV com origem/confiança).
- F35 — Alta frequência bruta com FIFO 3 dias + consolidação no device.
- F36 — `vinculos_profissional_paciente` (status/pagador/produto/datas).
- F37 — Tabela de escopo de consentimento por vínculo.
- F38 — Liga por profissional + entidade `desafios`.
- F39 — Jornada de mensagens de ciclo de vida do vínculo (i18n).
- F40 — Bifurcação de paywall por `pagador`.
- F41 — Verificação server-side de "acesso ativo" no login/refresh.

Estas se somam a F15–F30 do v3.0 (seed, exportação, alerta de tendência, widget, válvula alimentar, modo cuidador, logs_acesso, segurança S1–S9, telas do design system).

---

*Fim do Adendo v4.0. Para continuidade do projeto em qualquer IA: cole o DOCUMENTO MESTRE v3.0 seguido deste Adendo v4.0. Atualize a matriz (Parte 3.2 do v3.0 + seção K) e os logs (Parte 11 do v3.0 + seção J) a cada marco concluído.*
