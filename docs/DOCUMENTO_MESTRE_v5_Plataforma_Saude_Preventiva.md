# DOCUMENTO MESTRE v5.0 — PLATAFORMA DE SAÚDE PREVENTIVA COM IA
## Ecossistema Unificado B2C/B2B (Single-Backend / Multi-App)

**Data:** 16 de Julho de 2026
**Status:** FONTE ÚNICA DE VERDADE E AUTOSSUFICIENTE. Este documento consolida e substitui integralmente: PRD Consolidado v1, Apêndice de Arquitetura, Roadmap em Ondas, Estudo de Mercado, Handover Técnico, PRD v2.0, Documento Mestre v3.0, Adendo v4.0 e os logs de execução até 16/Jul/2026. Qualquer IA que receba este arquivo deve conseguir assumir o projeto sem contexto adicional.

**Precedência:** este documento (v5.0) prevalece sobre todos os anteriores.

### Documentos históricos (apenas para consulta de contexto de decisões antigas — NÃO usar para execução)
- Documento Mestre v3.0 (estrutura base, protocolo de auditoria)
- Adendo v4.0 (mercado, preços, dados de saúde, multi-profissional)
- Logs de execução técnica (auditoria + Etapa 0.5 + estrutura B2B), até 16/Jul/2026
Para executar, use SOMENTE este v5.0. Os antecessores ficam arquivados para rastreabilidade histórica.

---

# PARTE 0 — INSTRUÇÕES DE OPERAÇÃO PARA O ASSISTENTE DE IA

Se você é uma IA recebendo este documento, siga em ordem de precedência:

1. **NUNCA implemente, expanda ou corrija** itens EM HOLD (Parte 4).
2. **Antes de escrever código novo**, verifique a Matriz de Status (Parte 3) e execute o Protocolo de Auditoria se ainda não foi feito nesta fase. "Declarado-implementado" (✅) significa relatado por sessão anterior — trate ⚠️ e ✅ como não-verificados-por-humano até auditar.
3. **Requisitos de segurança (Parte 6) são bloqueadores de release.**
4. **Diretrizes de UX (Parte 8) prevalecem** sobre qualquer default visual.
5. **Regra de arquitetura inegociável:** toda lógica sensível (pontos, streaks, scores, elegibilidade, trial, prescrição, criação de vínculos) é server-side (Edge Functions/Cron). O cliente apenas exibe.
6. **Regra de dados inegociável:** nenhum dado real de usuário em IA de tier gratuito ou com cláusula de treinamento. Zero mídia persistida (pipeline RAM volátil).
7. **Git:** proibido force push; branch main protegida; PRs obrigatórios; zero segredos/chaves/IDs em código; stacked branches.
8. **Perfil do fundador:** não-desenvolvedor, solo, usando IA para 100% do código. Explique em linguagem simples, uma tarefa por vez, sempre diga como testar.
9. **Ferramenta de execução:** Claude Code (Parte 10 traz política de modelos e template de prompt).
10. **Toda migração de banco** = RLS habilitado + policy vinculada a `auth.uid()`/vínculo + **GRANT explícito** para o papel `authenticated` (o Supabase retirou privilégios default; sem GRANT o app perde DML mesmo com RLS correto).
11. **Idioma:** português brasileiro. i18n em pt/en/es (pt é a fonte).
12. **Não gerar novos documentos** exceto quando o fundador pedir explicitamente ("consolida"/"gera"). Evolução por adendo/log; consolidação em marcos.

---

# PARTE 1 — VISÃO DE NEGÓCIO E ESTRATÉGIA

## 1.1 Problema
Fragmentação das healthtechs (apps isolados de calorias, prontuário ou wearable), baixa retenção crônica de diários manuais, perda do histórico clínico de longo prazo pelo paciente.

## 1.2 Solução
Um backend único (Supabase) + múltiplas interfaces por nicho:
- **App Atleta** (B2C, gamificação Duolingo/Strava, tema escuro competitivo).
- **App Guardião Clínico** (B2C sênior/crônico/feminino, linha do tempo de exames, medicamentos, sem competição).
- **Painel Web B2B** (React) para nutricionistas, treinadores e médicos.
Um único app mobile de paciente com perfil dinâmico (`perfil_uso`); Guardião separável em app próprio no futuro se dados de aquisição justificarem (decisão de marketing, não de engenharia).

## 1.3 Decisão estratégica central
**O B2B (profissionais) é o coração comercial.** O B2C é ferramenta de engajamento e canal de aquisição, não a aposta principal de receita — canal B2B é identificável e previsível; B2C viral é loteria estatística.

## 1.4 Beachhead (público inicial estreito)
**Marketing** mira nutricionistas esportivos + treinadores de corrida e seus pacientes usuários de Garmin — nicho onde a dor é aguda, o diferencial é máximo (telemetria + prescrição no relógio) e os concorrentes são fracos. O usuário Garmin já tem dados sobrando e insights faltando: menor fricção de onboarding possível. **Beachhead de marketing, leque técnico aberto:** a tecnologia (Health Connect/HealthKit) atinge do smartwatch de R$ 200 ao Apple Watch — não se restringe o produto ao Garmin; restringe-se a mensagem de entrada.

## 1.5 Mercado
- Global de apps saúde/fitness: US$ 13,8–14,6 bi → projeção > US$ 33 bi (CAGR > 13,5%).
- Validadores globais: Cal AI (visão por foto, ARR US$ 30-35M, vendida ~US$ 50M), Whoop (US$ 3,6 bi), Strava (US$ 2,2 bi), MyFitnessPal (US$ 310M/ano).
- **Categoria "exames+wearables+nutrição" já validada nos EUA:** InsideTracker (sangue+DNA+wearables), OneTwenty (labs trimestrais + 500+ sinais de wearables cruzados), Function Health (~160 biomarcadores; captou US$ 300M), Superpower (100+ biomarcadores, US$ 199/ano). Whoop e Oura adicionaram exames via Quest (<US$ 200) — consolidação em curso; timing importa.
- **Distinção regulatória crítica:** esses players **são as testadoras** (coletam sangue, definem painel, respondem clinicamente — CLIA/FDA). Nós **não**: o usuário já possui o exame; nós lemos o PDF, extraímos e organizamos a série temporal. Somos **organizador de dados que o usuário já possui**, não plataforma de diagnóstico. Base da blindagem SaMD (Parte 5).
- Cenário nacional: Wellhub não faz inteligência de dados; Desrotulando é ferramenta isolada; Dietbox/Nutrium têm apps de paciente fracos. **Concorrentes B2B diretos a monitorar:** DietSystem (R$ 79,90/mês; já faz extração de exames por IA + análise de foto + app + WhatsApp) e SimpleDiet (R$ 27,90/mês; extração de PDF). Nenhum tem telemetria contínua de wearables nem o loop prescrição→relógio.

## 1.6 Fosso defensável (combinação que nenhum player reúne)
(1) Brasil-first (PDF de labs locais, idioma, preço); (2) telemetria contínua de wearables cruzada a exames e nutrição; (3) motor de retenção gamificado; (4) captura por foto de aparelhos analógicos (glicosímetro/pressão do sênior sem wearable caro); (5) loop completo profissional→prescrição→relógio Garmin; (6) base longitudinal que aumenta de valor e custo de troca com o tempo.

## 1.7 Lacunas não-técnicas (pendências)
1. **Análise de CAC** (3 cenários: orgânico/híbrido/pago a R$ 3–8/instalação) antes de investir em divulgação. CAC pode superar LTV.
2. **Resposta competitiva** (Samsung/Google podem embutir foto grátis; fosso real = base longitudinal + B2B).
3. **Validação primária:** 20 nutricionistas + 20 usuários-alvo antes do lançamento público.

## 1.8 Unit economics
- B2C anual R$ 179,90 (herói do funil) ≈ R$ 142 líquidos/ano após loja 15% + imposto 6%. **Teto de CAC = R$ 142; meta ≤ R$ 47.**
- B2B margem > 80% (custo IA agregado R$ 0,30–0,60/carteira/mês).
- Premissa realista: conversão trial→pago 1–2,5%; retenção 30 dias de mercado 5–10% (daí a engenharia de retenção ser mandatória).
- Premissa corrigida: **"custo mínimo controlado"**, não "custo zero".

## 1.9 Custos reais reconhecidos
| Item | Valor | Quando |
|---|---|---|
| Gemini API paga (nunca free com dado real) | ~R$ 0,012/usuário/mês | 1º usuário real |
| Supabase Pro | ~US$ 25/mês | 1º usuário real (free só p/ dev com seed) |
| Google Play Console | US$ 25 único | Agora |
| Apple Developer | US$ 99/ano | Beta iOS |
| CNPJ + contador | R$ 200–400/mês | Gatilho: 50 assinantes OU campanha pública |
| Parecer jurídico ANVISA/LGPD | R$ 5–15 mil | Antes do lançamento público |
| Revisão de segurança sênior | R$ 2–5 mil | Antes do lançamento público |

## 1.10 Situação jurídico-fiscal
Operação em CPF na fase de teste e primeiras vendas (contas de desenvolvedor pessoa física; receita das lojas via carnê-leão, rendimento do exterior até 27,5%). **MEI não permitido** para a atividade → ME/Simples. Responsabilidade ilimitada no CPF → gatilho de CNPJ (50 assinantes ou campanha pública) é mandatório. LGPD aplica-se desde o 1º usuário real.

---

# PARTE 2 — PREÇOS

## 2.1 B2B — pacote por profissional, valor FIXO por faixa (duas dimensões)
Dimensão 1 = faixa de pacientes (slots). Dimensão 2 = tipo de produto (com/sem envio de treino ao Garmin). O profissional paga o pacote e usa até o teto (não é cobrado por vínculo avulso).
- **Essencial (sem Garmin, até 15 pacientes): R$ 97/mês.**
- **Performance (com Garmin, até 40 pacientes): R$ 167/mês.**
- **Fundadores:** primeiros 10–20 profissionais, desconto vitalício (~R$ 67) por feedback + depoimento.
- Margem > 80%.

## 2.2 B2C — usuário individual
- **Anual (herói): R$ 179,90/ano** (≈ R$ 15/mês).
- **Mensal (âncora, não para vender): R$ 34,90/mês** — existe para o anual parecer barato.
- Não lançar B2C com desconto (vira âncora permanente); se precisar de tração, estender trial (21 dias), nunca cortar preço.

## 2.3 Relação entre pagadores
Paciente que entra **via profissional não paga** e **não recebe gatilho de venda** (paywall/cenoura/lembretes suprimidos). Cobrança B2C só quando o próprio usuário opta pelo plano individual. Múltiplos profissionais podem pagar pelo mesmo paciente (cada um consome 1 slot do seu pacote; o paciente compartilhado gera receita de N vínculos — não é cobrança dupla ao mesmo profissional).

---

# PARTE 3 — ARQUITETURA TÉCNICA E MATRIZ DE STATUS

## 3.1 Stack
- **Backend:** Supabase (PostgreSQL + Auth + Edge Functions Deno/TS + Cron). RLS em todas as tabelas + GRANT explícito.
- **Mobile:** Flutter (Feature-First), i18n pt/en/es. UI dinâmica por `perfil_uso` (atleta / exames_puro / foto_assincrono) sem reinício. Perfil selecionado via ProfileSelectionPage no cadastro.
- **Web B2B:** React + TypeScript + Vite, code splitting (vendor-react/supabase/charts), deploy Cloudflare Pages (no ar). Sidebar/DashboardLayout com render condicional por papel (Admin vs Profissional).
- **IA:** Google Gemini 2.5 Flash via **API paga**, chamada exclusivamente pelo servidor. Chaves só em variáveis de ambiente do servidor.
- **Wearables:** leitura LOCAL via pacote `health` (Health Connect / HealthKit). Proibido API de nuvem paga de agregação (ex. Terra) nas Ondas 1–2. Sync: oportunista + background 1x/dia (WorkManager, carregando + Wi-Fi). Carga inicial: 30 dias históricos no 1º acesso.
- **Garmin:** Edge Function `garmin-gateway/` (OAuth 1.0a HMAC-SHA1) server-to-server para enviar treinos. Tokens em tabela `garmin_conexoes` (isolada de GRANTs do app).

## 3.2 Legenda de status
✅ Declarado-implementado (não verificado por humano) · 🔍 Verificado (auditado/testado pelo fundador) · ⚠️ Parcial/desconectado · 🔲 Pendente · ⛔ Em Hold

## 3.3 MATRIZ DE STATUS (atualizada pós-auditoria + Etapa 0.5 + estrutura B2B, 16/Jul/2026)

| # | Funcionalidade | Status | Nota |
|---|---|---|---|
| F01 | Esquema de dados + RLS em todas as tabelas | 🔍 | RLS validado em 6 cenários (isolamento paciente×profissional via vínculos) |
| F02 | Caixa Preta (eventos_anomalias_saude) | ⚠️ | Tabela existe (append-only via GRANT INSERT); lógica de detecção pendente |
| F03 | Login social + OTP 6 dígitos | ⚠️ | Rebaixado na auditoria; religar/testar |
| F04 | Keystore/Keychain + biometria (CryptoStorageService) | ✅ | Mantido para tokens; ver Parte 6 S1/F04 |
| F05 | Suíte de testes de segurança | ⚠️ | Ceticismo: revisar cobertura real |
| F06 | Cadastro adaptativo BR (ViaCEP)/internacional | ⚠️ | Rebaixado; religar |
| F07 | Sync wearables (30 dias + oportunista + background) | ✅ | Teste real com Garmin pendente |
| F08 | Dashboard modular drag-and-drop | ⚠️ | Rebaixado; religar após F10 |
| F09 | Esteira 14 dias + cadeado dourado | ⚠️ | Rebaixado; renomear cenoura p/ "Projeção de Hábitos e Consistência" |
| F10 | Gateway Gemini + Zero Storage Pipeline | ⚠️→🔲 | **Edge Functions do Gemini INEXISTENTES. BLOQUEADOR DE PRODUTO — maior prioridade** |
| F11 | Painel React B2B (dados brutos, Cloudflare) | ✅ | Funcional c/ seed; bug de responsividade da sidebar mobile pendente; verificar login obrigatório |
| F12 | Filtragem seguradoras no painel | ⛔ | HOLD (Parte 4); UI já bloqueia exibição p/ contas seguradora |
| F13 | Garmin Training API Gateway (OAuth 1.0a) | ✅ | Depende de aprovação Garmin p/ teste real; construir com mock |
| F14 | Motor de sinistralidade | ⛔ | HOLD (Parte 4) |
| F15 | Seed de dados (seed_cloud.ts via Admin API) | ✅ parcial | 10 pacientes + 6 meses de métricas diárias, idempotente. **Falta:** exames EAV variados + 2-3 anomalias na Caixa Preta |
| F16 | Exportação de dados (PDF+CSV, LGPD) | 🔲 | Onda 2; loop viral B2B (PDF com marca+QR) |
| F17 | Alerta de Tendência não-clínico | 🔲 | Onda 2/3, server-side |
| F18 | Widget de tela inicial (streak+anel) | 🔲 | Onda 2 |
| F19 | Válvula de proteção alimentar | 🔲 | Onda 2 |
| F20 | Modo Cuidador/Familiar | 🔲 | Onda 3 |
| F21 | Modo Recuperação Humano | ⚠️ | Movido para stub HTTP 501 server-side; lógica real pendente |
| F22 | Registro de medicamentos + push local + missão | ⚠️ | Auditar implementação real |
| F23 | Relatórios sazonais macro | 🔲 | Onda 3 |
| F24 | Revogação instantânea de acesso do profissional | ⚠️ | Via aceitar/encerrar vínculo; auditar |
| F25 | 2FA no painel web profissional | 🔲 | Onda 4 (bloqueador Fase 2) |
| F26 | Prescrição ativa (cardápio + treino) | 🔲 | Onda 4; prescrição por papel (ver 7.x) |
| F27 | Deep linking WhatsApp | 🔲 | Onda 4 |
| F28 | logs_acesso append-only | 🔲 | Criar schema já; popular na Fase 2 |
| F29 | Requisitos de segurança S1–S9 | 🔲 | Bloqueadores de release |
| F30 | Telas no design system (Parte 8) | 🔲 | Checklist 8.6 (Playwright 375/1280px como método) |
| F31 | Índice de Bem-Estar / idade biológica (bem-estar) | 🔲 | Server-side; não-diagnóstico |
| F32 | marcadores_referencia (dicionário i18n) | ⚠️ | Criado com faixa_referencia NULA (usa faixa do PDF do lab); fallback: sem faixa se PDF não trouxer |
| F33 | resultados_exames refatorada p/ EAV | ✅ | Refatoração in-place preservando dados da Onda 1.5 (G.1) |
| F34 | coleta_diaria (EAV, origem/confiança) | 🔲 | Pressão, oximetria, glicose de dedo, peso, autorrelatos |
| F35 | Alta frequência bruta + FIFO 3 dias + consolidação no device | 🔲 | Ver G.4 |
| F36 | vinculos_profissional_paciente | ✅ | Sem RLS de INSERT (só via Edge Function de faturamento); nasce pendente; aceitar_vinculo/encerrar_vinculo |
| F37 | Escopo de consentimento por vínculo | ⚠️ | Implementado como aceite BINÁRIO do vínculo. Granularidade por classe = débito F37-fase2 (ver Parte 5 e 7) |
| F38 | Liga por profissional + desafios | 🔲 | Onda 2/4 |
| F39 | Mensagens de ciclo de vida do vínculo | 🔲 | i18n |
| F40 | Bifurcação de paywall por pagador | 🔲 | Suprime venda p/ via-profissional |
| F41 | Verificação server-side de "acesso ativo" no login/refresh | 🔲 | Carência por ausência de QUALQUER acesso ativo |
| F42 | Onboarding e aprovação de profissionais | ⚠️ | **NOVO — precisa de spec formal.** Campos is_admin/eh_profissional/tipo_profissional/status_aprovacao; backoffice admin; trava Blast Radius; critério de aprovação (validação CRM/CRN?) a definir |
| F43 | Motor viral (retrospectivas + cartões + pontos sociais) | 🔲 | Bloco detalhado na Parte 7 |
| F44 | Ciclo menstrual e menopausa | 🔲 | Onda 3; opt-in separado; ver Parte 5 e 7 |

## 3.4 Entidades de banco criadas/documentadas (schema real)
Além das tabelas de saúde (Parte 3.5): `perfis_usuarios` (PII com criptografia — ver decisão D2 abaixo), `garmin_conexoes` (tokens Garmin, isolada), tabela de **Trial/assinatura** (algoritmo server-side atrelado a `auth.users.created_at`; GRANT só SELECT), `vinculos_profissional_paciente` (status pendente/ativo/em_carencia/encerrado; pagador; tipo_produto; datas), campos de profissional em perfil (is_admin, eh_profissional, tipo_profissional, status_aprovacao).
**Views:** `perfis_pacientes_vinculados` (B2B, SEM security_invoker — ver risco R1), `perfis_profissionais_vinculados` (B2C, nickname do profissional no card de convite).
**Funções:** `resolver_usuario_id_por_email` (restrita à service_role; convite por e-mail sem quebrar criptografia; anti-injeção de schema). Edge Function de vínculos (aceitar/encerrar).
**Removidas (Etapa 0.5):** tabelas órfãs `metricas_saude` (legado) e `ciclo_menstrual` (volta redesenhada em F44/Onda 3).

## 3.5 ARQUITETURA DE DADOS DE SAÚDE — MODELO FINAL (múltiplas tabelas por natureza do dado)
- **G.1 `resultados_exames` — EAV (pontual/laboratorial).** `usuario_id`, `marcador_codigo`, `valor_numerico`, `valor_texto`, `unidade`, `data_coleta`, `origem`=pdf_exame, `laboratorio`, `criado_em`. Índice `(usuario_id, marcador_codigo, data_coleta DESC)`. **Normalização de unidade na entrada** guardando a original. Glicose de exame vive aqui. (Refatorada in-place — F33.)
- **G.2 `coleta_diaria` — EAV (frequente; device/OCR/manual).** `usuario_id`, `marcador_codigo`, `valor`, `unidade`, `origem` (device/ocr_foto/manual), `confianca` (score do OCR), `data_registro`. Recebe pressão, oximetria (SpO2), glicose de dedo, peso/composição (Fitdays via device ou OCR), temperatura e **autorrelatos** (humor/energia/dor). `origem` obrigatório (confiabilidade/auditoria/antifraude); mesma métrica por 3 caminhos cai na mesma série. EAV = extensível sem ALTER TABLE.
- **G.3 `metricas_saude_diarias` — COLUNAS FIXAS (agregado de wearable).** 1 linha/usuário/dia: passos, FC média/repouso/máx, sono. Estrutura fixa e imutável → coluna é mais compacta/rápida.
- **G.4 Alta frequência bruta — COLUNAS FIXAS + FIFO 3 dias.** Ex.: FC contínua. **Consolidação no device, em lote, na janela de background noturna** (Health Connect/HealthKit acumulam bruto local de graça; app consolida 1x/dia e envia só o agregado G.3 + eventos G.5). Bruto granular **nunca sobe** (mais barato/privado/menor superfície). Justificativa nos 4 eixos: custo (device=R$0), insight (com FIFO 3d o valor está nas tendências do agregado, não no bruto curto), UX (lote noturno = bateria imperceptível; subir bruto gastaria dados móveis), segurança (granular não sai do aparelho).
- **G.5 `eventos_anomalias_saude` — Caixa Preta (permanente, append-only).** Anomalia detectada na consolidação noturna é gravada com granularidade fina e **persistida no servidor** (evento já consolidado; servidor valida e grava — fonte de verdade). **Anomalia = desvio estatístico do baseline do próprio usuário**, NUNCA limiar clínico absoluto (isso caracterizaria dispositivo médico). Sem interpretação clínica ao usuário (dado silencioso p/ Caixa Preta + painel do profissional; no máximo convite neutro). Critério roda no device → versioná-lo bem.
- **G.6 Leitura pela IA:** lê **resumos textuais curtos pré-consolidados** pelo Cron (não tabelas brutas). Tendências vêm de G.3; momentos críticos de G.5 (cada anomalia vira frase curta no resumo). Exames = série por `marcador_codigo`; usa faixa do dicionário/PDF como contexto semântico. Mantém token baixo.

---

# PARTE 4 — ITENS EM HOLD (PROIBIDO IMPLEMENTAR)

## 4.1 Score Atuarial / Sinistralidade para Seguradoras — ⛔ EM HOLD (F14, F12)
Congela: `sinistralidade_engine`, espelho TS, indicador "Redução de Sinistralidade", login administrativo de operadoras, venda/exibição de score a terceiros.
Motivos: (1) políticas Google Health Connect / Apple HealthKit proíbem uso desses dados para fins atuariais/seguros → risco de banimento; (2) cálculo estava no cliente (manipulável); (3) LGPD exige base legal + consentimento destacado + RIPD inexistentes.
Retomada só sob TODAS: redesenho usando exclusivamente dados fornecidos direto pelo usuário (nunca HealthKit/Health Connect) + consentimento específico revogável com benefício direto ao titular (modelo Vitality) + cálculo 100% server-side auditado + parecer jurídico (LGPD/SUSEP) + verificação das políticas das lojas vigentes.
Se encontrar o código: não expandir/corrigir/integrar; manter isolado atrás de feature flag desligada. (UI já bloqueia exibição p/ contas seguradora.)

## 4.2 Fora de escopo sem nova revisão
Chat aberto de IA sobre saúde; SDKs proprietários de wearables além dos agregadores nativos; feed social estilo Strava; expansão internacional/idiomas antes do PMF no Brasil.

---

# PARTE 5 — BLINDAGEM JURÍDICA E REGULATÓRIA

## 5.1 LGPD
- Dado de saúde = sensível (art. 11): consentimento específico/destacado no onboarding; política de privacidade pública (URL exigida pela Play); direitos de exclusão e portabilidade (F16) no app.
- **Pseudonimização ≠ anonimização:** `usuario_id_anonimo` com FK vinculável é dado pessoal pleno. Nunca usar "anônimo" em termos/marketing (só no contexto de exibição pública de ranking: nickname+avatar).
- Ranking público de localidade só com N ≥ 30 usuários ativos (mitiga reidentificação).
- Proibido dado real em IA de tier gratuito/com treinamento.
- Incidente: referência de 3 dias úteis à ANPD (S7). RIPD antes do lançamento público.
- **Consentimento de vínculo:** vínculos nascem **pendentes**; o paciente chama `aceitar_vinculo` para liberar a RLS (Zero Trust — profissional não força leitura). **Em produção, backfills de legado devem nascer pendentes** (o backfill atual de teste nasceu ativo — exceção de ambiente, ver R4).

## 5.2 ANVISA (RDC 657/2022) — classificação pela FINALIDADE, não pelo vocabulário
- Somos **organizador de dados que o usuário já possui**, não plataforma de diagnóstico (não coletamos sangue, não definimos painel, não emitimos resultado). Argumento central da blindagem SaMD.
- App B2C **não cruza exames laboratoriais com telemetria** para predições clínicas individuais. Predições B2C ficam em hábitos/comportamento (consistência, tendência de sono, regularidade).
- A "cenoura" do dia 7 chama-se **"Projeção de Hábitos e Consistência"** (streak/pontos/ranking/metas). Correlações clínicas só no painel do profissional (CRM/CRN).
- `faixa_referencia` do dicionário é NULA por padrão: usa-se a faixa do próprio PDF do laboratório; sem faixa no PDF → não exibir faixa (nunca inventar). Reforça "organizador de dados".
- IA do app proibida de laudo/diagnóstico/termo médico direto. SpO2 e métricas beirando o clínico: exibir número/tendência ok; **nunca** alertar ação clínica ao usuário.
- Índice de Bem-Estar/idade biológica (F31): apresentado como bem-estar/estilo de vida, jamais idade clínica ou diagnóstico.
- Parecer jurídico formal antes do lançamento público (bloqueador de release, não de desenvolvimento).
- Fase 2: prontuário médico tem guarda própria (até 20 anos) — reconciliar com minimização antes de ativar painel médico.

## 5.3 Lojas e Health Connect
- Play: formulário Data Safety espelhando a política; **Declaração de Apps de Saúde do Health Connect** (revisão manual do Google, semanas, bloqueia distribuição ampla — protocolar JÁ).
- Contas pessoais novas: teste fechado (14 dias contínuos, nº mínimo de testadores — conferir no Console) antes de produção; Internal Testing liberado de imediato (até 100 testadores).
- **Garmin Developer Program:** maior lead time do projeto; protocolar JÁ. Sem aprovação não há credenciais da Training API → construir com **mock**; leitura via Health Connect não depende da Garmin (só a escrita de treinos depende).

## 5.4 Permissões de dados (minimização)
Pedir só o tipo de dado que uma feature visível usa (sem permissão órfã — passivo LGPD + bandeira na loja). Nem todo dado existe em todo aparelho (VO2max/HRV/SpO2 dependem do wearable) → tratar estados vazios graciosamente.

---

# PARTE 6 — REQUISITOS DE SEGURANÇA (BLOQUEADORES DE RELEASE)

Complementam TLS 1.3 + SSL pinning, Keystore/Keychain + biometria, RLS + GRANT e Zero Storage.
- **S1. Sessão server-side:** refresh token com rotação; "Desconectar todos os aparelhos"; token revogado rejeitado <60s. Corrigida race condition no `onAuthStateChange` (signOut() explícito entre signup e logins).
- **S2. Proteção de tela:** FLAG_SECURE nas rotas clínicas + ocultar miniatura em apps recentes (Android); ofuscar snapshot no iOS. Exceção: telas de gamificação podem permitir screenshot (viralização controlada — só dado de atividade).
- **S3. Root/jailbreak:** detectar na abertura, avisar sem bloquear, gravar flag `dispositivo_comprometido` no servidor.
- **S4. Rate limiting + teto financeiro:** máx. 30 análises de imagem/dia/usuário; alerta de billing (US$ 10/dia) no Google Cloud; circuit breaker global acima do teto diário.
- **S5. logs_acesso append-only:** criar já; popular na Fase 2 e Modo Cuidador. Sem UPDATE/DELETE. Cada acesso rastreado por vínculo.
- **S6. Backup testado:** ritual mensal de restauração em staging com validação de integridade.
- **S7. Plano de resposta a incidente:** `INCIDENT_RESPONSE.md` no repo privado (contenção: revogar chaves→banco read-only→invalidar sessões; responsáveis; modelo de comunicação a titulares/ANPD; contato do advogado).
- **S8. Higiene de repositório:** main protegida (sem force push, incl. IA); PRs; varredura de segredos no CI; zero chaves em código; Service Role Key SEM prefixo VITE_ (só backend); `.env.example` só placeholders. **Ação pendente: rotacionar a Service Role Key usada no .env temporário do seed (R6).**
- **S9. Revisão humana sênior antes do 1º release público:** RLS, fluxo de tokens/biometria, pipeline de imagem em RAM, e **prioritariamente a view `perfis_pacientes_vinculados` sem security_invoker (R1)**. Testes de IA não substituem.
- **GRANT explícito** em toda migração (regra da Parte 0.10). Saneamento com exclusões intencionais: `garmin_conexoes` sem acesso do app, Caixa Preta só INSERT, Trial só SELECT.
- **Contas de teste segregadas:** proibido testar com conta híbrida (admin+profissional); roteamento de menor privilégio trava híbrido fora da área clínica por design.
- **Método de validação visual:** Playwright headless (375px/1280px).

---

# PARTE 7 — REGRAS DE NEGÓCIO: GAMIFICAÇÃO, RETENÇÃO, MOTOR VIRAL, MULTI-PROFISSIONAL, CICLO

## 7.1 Gamificação e retenção (base)
- **Streak diário:** Condição 1 (1 foto de refeição OU, até 2x/semana, registro rápido sem foto) + Condição 2 (treino Garmin OU 8.000 passos locais). Quebra zera a chama e −100 pts. Nunca punir conteúdo calórico; pontuar consistência. Cálculo server-side; cliente só exibe.
- **Rankings:** ligas de amigos/cidade/estado/país; cache noturno; nickname+avatar; localidade pública só com N≥30.
- **Esteira 14 dias:** Dia 1 carga de 30 dias (mata dashboard vazio); dias 1–6 missões homeopáticas de upload de exames; dia 7 desbloqueio do 1º prêmio (congela — não zera — em imprevisto) + teaser "Projeção de Hábitos e Consistência" borrada com cadeado; conversão no dia 14 (anual). **Trial atrelado a `auth.users.created_at`** (antifraude server-side); avaliar mudar para "primeira ativação significativa" para não penalizar quem demora a ativar (R3).
- **Marcos:** relatórios 21/28 dias; Modo Competição Target aos 45 dias.
- **Modo Recuperação Humano (F21):** voluntário, congela ofensivas sem punição, paleta calma, foco sono/medicação/nutrição regenerativa. Casa com a fase menstrual (dias de cólica podem ativar tom acolhedor sem quebrar chama). Hoje é stub server-side 501; lógica pendente.
- **Medicamentos:** dose/horário, push local, missão diária (+10 pts).
- **Copy de paywall:** Atleta = pontos/ranking/relatório trancado; Guardião = linha do tempo clínica de uma vida + controle de remédios.

## 7.2 Autorrelato (regra de ouro)
Toda coleta ativa do usuário é **opt-in, toque único, recompensada e DESVINCULADA da ofensiva**. Máx. 1 pergunta/dia, rotativa (energia/sono/humor/dor), como missão opcional que dá pontos. Quem ignora não perde nada. Autorrelato é 100% seguro no enquadramento ANVISA (bem-estar). No Guardião, o Modo Cuidador pode incentivar sem pressa.

## 7.3 MOTOR VIRAL (F43) — três momentos + pontos sociais + loop B2B
Reaproveita um único **gerador de cartões 9:16** com três templates. Regras transversais: compartilhamento sempre **opt-in por ação**; cartões públicos só com dados de **atividade/gamificação** (nunca clínico — glicose/pressão/peso jamais, nem em tela, pois print existe); visual do design system é prioridade (cartão feio não é compartilhado).

**(a) "Uau do Dia 1" — Retrospectiva de Boas-Vindas.** Durante a Carga Inicial de 30 dias, tela "preparando sua retrospectiva". 5 cartões stories: (1) número que impressiona com comparação da cidade do usuário; (2) recorde do mês + pergunta de memória; (3) curiosidade/padrão (o diferencial — escolhe o maior contraste entre 4-5 padrões: sono semana×fds, dia mais ativo, regularidade de sono, tendência de passos); (4) ponte ao futuro ("imagine quando cruzar com alimentação e exames"); (5) compartilhável (3 números + marca + botões "Compartilhar" e "Começar"). Cálculo no device durante a Carga Inicial; tabela local de ~50 cidades BR + fallback "X maratonas". Cada cartão emite analytics; **métrica-norte: taxa de compartilhamento do cartão 5**.
- Degradação graciosa (NUNCA mostra zeros): 14+ dias = completa; 3-13 dias = versão curta 2 cartões; <3 dias = pula e promete retrospectiva no dia 7 (vira +1 recompensa do dia 7).
- Anti-vergonha: dados baixos = enquadramento de ponto de partida, nunca envergonhar.

**(b) Dia 7 — cenoura mantida + gêmeo compartilhável ("Cartão da Primeira Semana").** Sequência: celebração plena (cartão-troféu) ANTES da tela do cadeado. Cartão único (conquista se exibe num relance): chama de 7 dias como herói visual (assinatura da marca), 3 números (pontos, refeições+treinos, percentil da cidade — "Top 12%", nunca posição absoluta; fallback liga de amigos/recorde quando base pequena), rodapé com marca + frase de identidade. Variantes: 7/7 = cartão dourado "Semana Perfeita" (colecionável); quebra com atividade = cartão de progresso; uso quase nulo = mensagem de recomeço (sem troféu vazio). Legenda pré-preenchida editável com **deep link de convite do usuário** → cartão é troféu E convite rastreável (aciona +50 de convite aceito). Reaproveita 100% do gerador de imagem.

**(c) Retrospectiva Mensal — evento recorrente sincronizado.** Liberada para TODOS no **dia 1 do mês às 19h** (sincronização = onda coletiva nas redes); push é evento ("Sua retrospectiva de [mês] está pronta"). 5 cartões: (1) placar do mês com setas de evolução vs. mês anterior (a partir do mês 2); (2) momento do mês; (3) padrão descoberto (correlação entre comportamentos — exclusivo, sempre hábitos); (4) vida na liga (posição; se sem liga, vira recrutador com botão de convite); (5) compartilhável + **meta do próximo mês em um toque** (emenda retenção na celebração). Gerado no **Cron da madrugada do dia 1** (pré-calcula p/ toda a base; evita pico às 19h). Consumo de IA ~zero (cálculo determinístico; frase do cartão 3 por templates). Usuário dormente **recebe o push mesmo assim** (ferramenta de ressurreição: "seu mês teve X passos mesmo sem abrir"). Novo no meio do mês = versão adaptada. Cartão 4 mostra só a posição do próprio usuário (nunca nomes/avatares de amigos no compartilhável). Métricas-norte: abertura do push, partilha do cartão 5, taxa de ressurreição.

**Pontos sociais (alimenta ranking, NUNCA a ofensiva; tudo validado server-side):**
- Convidar (deep link enviado): +10, teto 3/dia.
- Convite **aceito** (amigo instalou + criou conta + completou 1º dia — trava anti-farming): +50.
- Liga de amigos ativada (3+ membros): +100, uma vez.
- Participar de desafio: +20 na entrada; pontos do desafio na conclusão (placar separado do grupo, não distorce ranking geográfico).
- Compartilhar cartão: +15 (1x por cartão por plataforma, teto 2/dia); +10 por plataforma distinta adicional (pontua a intenção direcionada — o Android não confirma o post real).
- Vale para todos os cartões.

**(d) Loop B2B (o mais valioso):** exportação (F16) sai com capa/marca + QR discreto "profissional: acompanhe seus pacientes assim". Cada consulta vira demonstração de vendas B2B na mesa da persona compradora.

## 7.4 Modelo multi-profissional
- **Duas portas:** via profissional (cadastro/pagamento do profissional; sem gatilho de venda; gamificação integral) e individual (paga o próprio plano; controla o que compartilha).
- **Vínculo = unidade central (banco + faturamento):** `vinculos_profissional_paciente` (status pendente/ativo/em_carencia/encerrado; pagador; tipo_produto herdado do pacote; datas). Criado só via Edge Function de faturamento (sem RLS de INSERT = antifraude de slot). Múltiplos profissionais por paciente; cada vínculo consome 1 slot do pacote do profissional; preço fixo por faixa.
- **Permissões (definição atual):** **leitura uniforme** — todo profissional com vínculo aceito vê **todos os dados** do paciente (o valor está no cruzamento; fatiar leitura destruiria o prontuário de visão cruzada). **Escrita/prescrição segregada por papel:** prescrever treino (e enviar ao Garmin) = exclusivo do personal/treinador; prescrever cardápio (quando implementado) = exclusivo do nutricionista; médico vê tudo, sua prescrição fica para discussão futura. Permissão de prescrição checada server-side contra `tipo_profissional` + pacote. **Exceção à leitura uniforme:** dados de ciclo menstrual ficam FORA por padrão (opt-in separado da mulher — ver 7.6); nenhum agente deve "uniformizar" isso.
- **Consentimento (F37):** hoje **binário** (aceitar/recusar o vínculo inteiro) — cumpre LGPD (explícito, informado, revogável). Microcopy do convite deve ser honesta ("ao aceitar, [profissional] poderá ver seus dados de saúde, atividade e nutrição"), sem prometer controle fino inexistente. Granularidade por classe = **débito F37-fase2**, gatilho pós-teste de campo, rebaixado em prioridade (leitura uniforme por design reduz a necessidade). Recusa reaproveita `encerrar_vinculo` (pendente→encerrado).
- **Gamificação estendida:** liga por profissional (padrão anônimo entre pacientes; só o profissional vê nomes no painel); desafios do profissional (`desafios`; placar separado); na saída, pontos/histórico pessoais ficam com o usuário (sai só da liga/desafios daquele profissional).
- **Ciclo de vida / carência (F41):** carência dispara por **ausência de QUALQUER acesso ativo** (nenhum profissional pagante E sem plano individual) — verificação server-side no login/refresh. Se um de vários profissionais remove mas outro vínculo pago continua → não entra em carência. Sem acesso ativo → comunicado (push+tela) + 30 dias completos + opção de plano individual; tom de convite, nudges (dia 1/20/28), i18n. Fim dos 30 dias sem conversão → **bloqueado até reativar** (dados preservados, chama pausada, nada apagado; exclusão só a pedido).
- **Aprovação de profissionais (F42):** segregação Admin×Profissional com trava Blast Radius (admin preso na gestão, sem dados clínicos); `status_aprovacao='aprovado'` obrigatório para liberar área clínica; backoffice de aprovação; admin tem bypass de atributos clínicos. **Spec pendente:** critério de aprovação (validação de CRM/CRN?), fluxo de rejeição, quem aprova.

## 7.5 Prescrição por papel (resumo para implementação futura — Onda 4)
Leitura: todos veem tudo. Escrita: treino→personal (+Garmin); cardápio→nutricionista; médico→leitura total, prescrição a definir. Validado server-side por `tipo_profissional` + `tipo_produto` do pacote.

## 7.6 Ciclo menstrual e menopausa (F44 — Onda 3)
- **Território exclusivo de bem-estar/autoconhecimento.** Registro de padrões/sintomas e **previsão do próximo ciclo** (calendário) permitidos. **PROIBIDO** previsão de fertilidade para concepção/contracepção (caracterizaria dispositivo médico — Natural Cycles precisou de aprovação FDA).
- **Privacidade máxima:** opt-in separado e explícito; dado sensível politicamente exposto; **nunca compartilhado por padrão** com profissionais (fora da leitura uniforme; a mulher libera por vínculo se quiser); nunca em ranking.
- **Previsão como janela com incerteza honesta** (aperta com o histórico); **recuo automático em ciclos irregulares/perimenopausa** ("vamos acompanhar padrões em vez de prever datas" — a própria irregularidade é dado de bem-estar do Guardião).
- **Cruzamento de fase com os demais dados** (sono/energia/peso/treino) = diferencial que nenhum tracker isolado tem.
- **Menopausa:** vertente do perfil Guardião (público 45-55+, que paga); sintomas em `coleta_diaria`, flag de fase reprodutiva no perfil, IA adapta insights.
- **Modelagem:** sintomas em `coleta_diaria` (EAV, origem=manual); entidade `ciclo_menstrual` para marcos (início/duração → média pessoal → previsão do calendário). Pontua como autorrelato (opt-in, desvinculado da ofensiva). Versão mínima possível na Onda 2 se a validação pedir.

---

# PARTE 8 — DESIGN SYSTEM E UX (PREVALECE SOBRE DEFAULTS DE IA)

## 8.1 Proibições (eliminar "tiques de IA")
Gradiente roxo/índigo como identidade; glassmorphism generalizado; sombras difusas em cascata; **emoji como ícone de UI**; paleta creme+serifa+terracota default; fundo quase-preto com verde-ácido único; marcadores numerados decorativos sem sequência real; placeholders ("Lorem ipsum", "usuário123"); microcopy traduzida do inglês ("Ops, algo deu errado :("); dois estilos de componente para a mesma função.

## 8.2 Identidades por superfície
- **Atleta (escuro competitivo):** base grafite #0E1114 (não preto puro); UM acento de energia (laranja-cobre OU verde-sinal, nunca ambos); números em face condensada tabular; assinatura = anel de HealthScore segmentado por métrica com gaps (não copiar Apple).
- **Guardião (claro clínico-acolhedor):** off-white quente; corpo ≥18pt; toque ≥48dp; contraste AA/AAA; acento único azul-petróleo ou verde-sálvia; sem contadores agressivos; vermelho só em confirmação destrutiva; assinatura = linha do tempo vertical por ano.
- **B2B Web:** instrumento profissional — densidade alta, hairlines, zero ornamento, Recharts com paleta sóbria e legendas completas, números tabulares.

## 8.3 Tokens (fonte única)
Grade 8pt (4pt micro); um raio global (ex. 12) + um p/ chips (999); escala tipográfica única (12/14/16/18/22/28/34) em TextTheme central; um set de ícones outline (Phosphor/Lucide, 1 peso); cores só via tokens semânticos (surface/onSurface/accent/positive/critical), zero hex em widget; motion 150ms micro / 250ms navegação, respeitar reduce-motion; animação só com significado (streak/anel); confete/parallax gratuito proibido.

## 8.4 Padrões de tela
Estados vazios projetados (ilustração do sistema + 1 frase de ação); skeletons na forma do conteúdo (não spinner de tela cheia); erros com direção ("Sem conexão com o Health Connect. Verifique permissões em Ajustes > Apps conectados."), sem desculpas/humor; 1 número-herói por tela; acessibilidade como piso (AA, foco visível, TalkBack/VoiceOver, texto escalável a 130% sem quebra).

## 8.5 Microcopy pt-BR nativo
Sentence case; verbos que dizem o que acontece ("Gerar PDF", nunca "Enviar"/"OK"); nomes estáveis do botão ao toast; tom Atleta direto sem gíria, Guardião claro e caloroso sem diminutivos ("remedinho" proibido), B2B técnico neutro; glossário fixo no i18n (pt é a fonte).

## 8.6 Checklist por tela (antes de codificar)
(1) objetivo + número-herói em 3 linhas; (2) checar contra 8.1; (3) só tokens de 8.3; (4) após codificar: validação visual Playwright headless 375px e 1280px, conferindo quebras em palavras longas pt-BR ("sincronização", "acompanhamento").

---

# PARTE 9 — ETAPAS DE EXECUÇÃO E PLANO DE TESTE

## 9.1 Prioridade imediata (ordem obrigatória)
1. **F10 — Edge Functions do Gemini + Zero Storage Pipeline.** BLOQUEADOR DE PRODUTO (sem ele o app não tem o diferencial; nem o teste fake exercita o "uau"). Modelo topo de linha (segurança + RAM volátil).
2. **Migração de criptografia de PII para server-side em repouso** (decisão D2 — ver Parte 11) antes de qualquer dado real. Modelo topo de linha.
3. **Build Android de homolog** para avaliação com dados fake.
Em paralelo (lead time externo, iniciar já): conta Google Play Console (verificação de identidade), Declaração Health Connect, cadastro Garmin Developer.

## 9.2 Ambientes (homolog × produção)
- **Dois projetos Supabase:** `homolog` (free tier, dados fake — mantidos vivos para demonstrações) e `prod` (Supabase Pro quando entrar dado real). Migrações via Supabase CLI, versionadas no git, aplicadas primeiro em homolog.
- **Git:** `develop` (→ homolog) e `main` protegida (→ prod). Fluxo: feature branch → PR develop → testa homolog → PR main → prod. Stacked branches para trabalho progressivo.
- **Cloudflare Pages:** preview por branch (painel de homolog em URL própria, de graça) — variáveis de ambiente de homolog vs. prod nunca no mesmo build.
- **Flutter flavors:** homolog e produção (apontando cada um ao seu banco). Teste pessoal roda no flavor de produção.
- **Checklist de subida a produção (avaliação de impacto):** migração testada em homolog + smoke test das funções críticas + backup do prod antes + registro do que mudou. **Paridade de configuração** documentada (o painel Supabase — providers/auth settings — não é versionado; manter checklist para prod não nascer diferente — ver R-E4).

## 9.3 Plano de teste (sequência)
Web fake (pronto para começar; bug de sidebar mobile conhecido) → correções/backlog → app fake (após F10) → correções → **zerar** → teste real do fundador 1 semana com **diário** (registrar/dia: o que usei, o que funcionou, o que falhou com print, o que me irritou = fricção, o que senti falta, e "eu abriria amanhã sem obrigação?") → amigos com Garmin/Android (2ª fase, via loja, CPF — conhecer o processo Google) → iOS depois (Mac em casa; esposa/filho com Garmin; TestFlight quando maduro).
- **Envio de treino Garmin:** validar com **mock** enquanto a aprovação Garmin não sai; teste com amigos pode começar sem prescrição de treino (leitura não depende da Garmin).
- **Backlog:** cada item com título/origem (bug/melhoria/ideia)/impacto. Regra: nada do backlog entra em dev durante testes, exceto bug que impede o teste. Ideias novas esperam.

## 9.4 Roadmap por ondas
- **Onda 2 (foco do trimestre):** App Atleta BR — F10, F16, F17, F18, F19, motor viral (F43), esteira 14 dias.
- **Onda 3:** App Guardião + Modo Cuidador (F20) + relatórios sazonais (F23) + ciclo/menopausa (F44).
- **Onda 4 (Fase 2 B2B):** 2FA (F25), logs_acesso ativos (F28/S5), prescrição por papel (F26), Garmin Training API em produção, deep links WhatsApp (F27), F42 completo. **Meta: primeiros 10 nutricionistas/treinadores pagantes.**
- **Fase 3 (seguradoras): ⛔ HOLD.**
- **Pré-lançamento público:** política de privacidade + termos, RIPD, parecer ANVISA/LGPD, revisão de segurança humana (S9), análise de CAC, validação primária, monitorar gatilho de CNPJ.

---

# PARTE 10 — EXECUÇÃO COM CLAUDE CODE + POLÍTICA DE MODELOS

## 10.1 Ferramentas
Execução no **Claude Code** (docs: https://docs.claude.com/en/docs/claude-code/overview). Planejamento/geração de prompts pode ser em qualquer chat de fronteira (recomendado Gemini 3.1 Pro pelo contexto longo), mas os prompts são escritos para o Claude Code executar.

## 10.2 Política de modelos (custo-benefício) — informar SEMPRE no cabeçalho do prompt
- **Padrão: Claude Sonnet** (~80% das tarefas: telas, CRUD, integrações documentadas, testes, refactors médios).
- **Trivial: Claude Haiku** (copy, i18n, renomeações, scripts simples).
- **Crítico: modelo topo de linha (Opus/superior)** (RLS, segurança, tokens/biometria, pipeline RAM, OAuth Garmin, criptografia, arquitetura).
- Verificar modelos vigentes com `/model` e docs.claude.com. Economia: sessões curtas, `/clear` entre tarefas, apontar arquivos específicos.

## 10.3 Template de prompt (usar sempre)
```
[MODELO RECOMENDADO: Sonnet | Haiku | Topo de linha — com 1 linha de justificativa]
[CONTEXTO]: Parte 0 deste documento + seções relevantes à tarefa.
[TAREFA]: objetivo único (1 tarefa por sessão).
[ARQUIVOS]: caminhos exatos.
[RESTRIÇÕES]: holds (Parte 4); segurança (Parte 6); UX (Parte 8); server-side por padrão; GRANT em migração; sem segredos; sem force push.
[CRITÉRIO DE ACEITE]: como o fundador (não-dev) testa, passo a passo, em linguagem simples.
[ENTREGÁVEL]: código + explicação simples + commit em branch própria + instrução de PR.
```

## 10.4 Ritual do fundador
1 tarefa/sessão → Claude Code implementa e explica → fundador testa pelo aceite → commit/PR → merge em main protegida. Quebrou: `git revert` (nunca force push). Dúvida: pedir explicação simples antes de aprovar.

---

# PARTE 11 — REGISTRO DE DECISÕES (LOG IMUTÁVEL)

## 11.1 Decisões estratégicas e de produto
| Data | Decisão | Motivo |
|---|---|---|
| Jul/2026 | Fase 3 (score seguradoras) EM HOLD | Políticas HealthKit/Health Connect + LGPD + cálculo no cliente |
| Jul/2026 | "Custo zero" → "custo mínimo controlado"; Gemini só API paga | Free tiers incompatíveis com dado de saúde |
| Jul/2026 | "Anonimizado" → "pseudonimizado" | LGPD: dado vinculável é pessoal pleno |
| Jul/2026 | Cenoura do dia 7 = "Projeção de Hábitos e Consistência" (sem exames no B2C) | RDC 657/2022: finalidade define SaMD |
| Jul/2026 | B2B = prioridade comercial; B2C = engajamento/aquisição | CAC B2C imprevisível; canal B2B identificável |
| Jul/2026 | Beachhead = nutri esportivo/treinador + pacientes Garmin (marketing), leque técnico aberto | Menor fricção; diferencial máximo; concorrente fraco |
| Jul/2026 | Regra server-side para toda lógica sensível | Cliente é manipulável |
| Jul/2026 | Ranking público de localidade só com N≥30 | Reidentificação em cidades pequenas |
| Jul/2026 | CPF com gatilho de CNPJ (50 assinantes OU campanha) | Responsabilidade ilimitada + carnê-leão vs Simples |
| Jul/2026 | Categoria validada globalmente; somos "organizador de dados", não "plataforma de diagnóstico" | Refina fosso + reforça blindagem SaMD |
| Jul/2026 | Preços B2B R$97/R$167 fixo por faixa; B2C R$179,90/ano + R$34,90 âncora | Ancoragem competitiva |
| Jul/2026 | Dicionário de biomarcadores = núcleo brasileiro (reconhecimento, não painel próprio) | PDFs de labs BR; extensível |
| Jul/2026 | F31 Índice de Bem-Estar como bem-estar (não diagnóstico) | Gancho de marketing dentro do enquadramento |
| Jul/2026 | Multi-profissional: vínculo = unidade de slot/faturamento; múltiplos pagadores | SaaS multi-assento |
| Jul/2026 | Leitura uniforme (todos veem tudo) + prescrição por papel (treino=personal, cardápio=nutri, médico vê tudo) | Valor no cruzamento; simplifica F37 |
| Jul/2026 | Ciclo menstrual FORA da leitura uniforme (opt-in separado) | Privacidade sensível; exceção explícita |
| Jul/2026 | Carência/bloqueio por ausência de QUALQUER acesso ativo; bloqueio preserva dados e pausa chama | Reaproveita usuário; não pune; LGPD |
| Jul/2026 | Dados de saúde em múltiplas tabelas (exames EAV, coleta_diaria EAV, diárias coluna, alta freq. coluna FIFO 3d, anomalias permanente) | Cada natureza na modelagem correta |
| Jul/2026 | Consolidação de alta freq. no device, lote noturno; bruto não sobe | Custo/UX/segurança apontam device |
| Jul/2026 | Anomalia = desvio do baseline do próprio usuário, sem interpretação clínica ao usuário | Limiar absoluto caracterizaria dispositivo médico |
| Jul/2026 | Autorrelato opt-in, toque único, recompensado, desvinculado da ofensiva | Coleta sem matar retenção |
| Jul/2026 | App único de paciente; Guardião separável no futuro (gatilho: dados de aquisição) | Backend único + fundador solo |
| Jul/2026 | Motor viral: 3 momentos (dia 1/dia 7/mensal) + pontos sociais + loop PDF B2B | Viralidade nos picos de orgulho; loop entrega lead na persona compradora |
| Jul/2026 | Ciclo/menopausa: previsão de calendário sim, previsão de fertilidade não | Mantém enquadramento de bem-estar |
| 16/Jul/2026 | Consolidação em v5.0 (documento único) no marco pré-teste-de-campo | Três documentos conflitantes = risco/custo para agentes |

## 11.2 Decisões técnicas (auditoria + Etapa 0.5 + estrutura B2B — logs 12–16/Jul/2026)
| Data | Decisão | Motivo |
|---|---|---|
| 12/Jul | Auditoria rebaixou F03/F06/F08/F09/F10/F21 (✅→⚠️) | Roteamento desconectado, Edge Functions Gemini inexistentes, lógica no cliente |
| 12/Jul | Etapa 0.5 (Faxina e Fiação) antes do v4.0 | Não empilhar tabelas complexas sobre roteador quebrado |
| 12/Jul | Rotas religadas + ProfileSelectionPage | Evitar beco sem saída no cadastro Atleta/Guardião |
| 12/Jul | Remoção de tabelas órfãs (metricas_saude, ciclo_menstrual) | Higiene; ciclo volta redesenhado (F44) |
| 12/Jul | Modo Recuperação (F21) → stub server-side (HTTP 501) | Lógica sensível estritamente server-side |
| 12/Jul | Criptografia de e-mail client-side em perfis_usuarios | (revisada — ver D2 em 11.3) |
| 12/Jul | Trial server-side atrelado a auth.users.created_at | Antifraude de data (revisar penalização — R3) |
| 13/Jul | resultados_exames refatorada in-place para EAV | Preservar dados da Onda 1.5 (G.1) |
| 13/Jul | Sem RLS de INSERT em vinculos (só Edge Function de faturamento) | Antifraude B2B de slots |
| 13/Jul | faixa_referencia nula (usa faixa do PDF do lab) | Mitigação SaMD |
| 13/Jul | RLS validado em 6 cenários (isolamento via vínculos) | Zero Trust confirmado |
| 13/Jul | GRANT explícito para authenticated em toda migração | Supabase retirou privilégios default |
| 13/Jul | GRANTs com exclusões (garmin_conexoes, Caixa Preta só INSERT, Trial só SELECT) | Engenharia defensiva |
| 13/Jul | View perfis_pacientes_vinculados sem security_invoker | Profissional vê perfis via view (contorna base) — ver risco R1 |
| 13/Jul | RLS unificado de métricas/anomalias sob vinculos (fonte única) | Exige Edge Function de vínculos + backfill |
| 13/Jul | Vínculos nascem pendentes (aceitar_vinculo pelo paciente) | LGPD Zero Trust |
| 13/Jul | Backfill de prescrições legadas → vínculos ativos | Preservar B2B legado (exceção de teste — ver R4) |
| 13/Jul | Testes Deno exigem flag --config (deno.json) | Execução isolada de funções |
| 13/Jul | View perfis_profissionais_vinculados (B2C) | Nickname do profissional no card de convite (contorna criptografia) |
| 13/Jul | Recusa de convite → encerrar_vinculo (pendente→encerrado) | Reaproveita Edge Function |
| 13/Jul | Tela de Gestão de Convites (ConfiguracoesPerfilPage) | Consentimento explícito LGPD no app |
| 13/Jul | resolver_usuario_id_por_email restrita à service_role | Convite por e-mail sem quebrar criptografia; anti-injeção |
| 13/Jul | Modal/Toast B2B em React puro/Tailwind | Frontend leve; respeita Design System; bloqueio p/ seguradoras |
| 14/Jul | Correção de race condition no onAuthStateChange (signOut explícito) | Conflito signup×login |
| 14/Jul | Bypass de validação clínica para is_admin | Admin acessa backoffice sem atributos clínicos |
| 16/Jul | seed_cloud.ts via Admin API (substitui seed.sql na nuvem) | Supabase bloqueia INSERT direto em auth.users |
| 16/Jul | DashboardLayout + Sidebar (render condicional por papel) | Navegação Admin×Profissional (bug responsividade mobile pendente) |
| 16/Jul | Reativação do Email provider; sensibilidades do Auth documentadas | Falhas 400/422/email_provider_disabled |
| 16/Jul | Contas de teste segregadas (não híbridas) | Roteamento de menor privilégio (Blast Radius) |
| 16/Jul | Git: stacked branches | Evitar "git hell"; preservar atualizações acumuladas |
| 16/Jul | Playwright headless (375/1280px) como validação visual | DOM real, não só leitura de código |

## 11.3 Decisões abertas resolvidas em 16/Jul/2026
| ID | Decisão | Motivo |
|---|---|---|
| D1 | Consentimento fica BINÁRIO (débito F37-fase2 pós-teste, rebaixado); microcopy honesta no convite; ciclo menstrual como exceção opt-in | Leitura uniforme reduz necessidade de granularidade; LGPD cumprida; não bloquear F10 |
| D2 | Migrar criptografia de PII de client-side (E2E) para **server-side em repouso** antes do teste de campo | Complexidade operacional do E2E = risco p/ fundador solo (view-contorno já nasceu disso); e-mail já está plano no auth.users; métricas de saúde já usam repouso+RLS — coerência. CryptoStorageService segue p/ tokens (S1/F04) |
| D3 | Permissões: leitura uniforme + prescrição por papel (ver 7.4/7.5) | Valor no cruzamento; simplifica F37 |

---

# PARTE 12 — RISCOS CARREGADOS (ACOMPANHAR)

- **R1 (alto):** view `perfis_pacientes_vinculados` sem security_invoker → o WHERE é a única barreira. Prioridade da revisão S9 + criar 7º cenário de teste de isolamento específico para a view.
- **R2 (resolvido por D2):** estratégia de criptografia de PII → migrar para server-side antes de dado real.
- **R3 (médio):** trial por `created_at` penaliza quem demora a ativar → avaliar "primeira ativação significativa" (server-side).
- **R4 (médio):** backfill de legado nasce ativo × consentimento pendente → regra: em produção, backfill nasce pendente.
- **R5 (médio):** F42 (aprovação de profissionais) sem spec formal (critério CRM/CRN, fluxo de rejeição, quem aprova) → risco de cada agente implementar diferente.
- **R6 (alto/rápido):** Service Role Key usada em .env temporário do seed → confirmar que não foi commitada e **rotacionar** (S8).
- **R7 (baixo):** responsividade mobile da sidebar B2B pendente.
- **R8 (bloqueador de produto):** F10 (pipeline Gemini) inexistente — sem ele nem o teste fake exercita o diferencial.
- **R-E4 (médio):** configurações do painel Supabase não versionadas → checklist de paridade homolog×prod (9.2).
- **R-E5 (baixo):** seed grava PII fake em metadados do auth.users (não criptografados) e não exercita o caminho real de escrita criptografada → após D2, revalidar seed contra o novo modelo.
- **F15 pendência:** seed não confirma exames EAV variados + anomalias na Caixa Preta → completar.

---

# PARTE 13 — GLOSSÁRIO DE ENTIDADES (referência rápida para agentes)
- **perfil_uso:** tag que define a interface (atleta / exames_puro / foto_assincrono).
- **vinculos_profissional_paciente:** unidade central B2B (relação + slot + faturamento + consentimento).
- **Zero Storage Pipeline:** captura por câmera → bytes em RAM → Gemini extrai JSON → destrói mídia. Nada em disco.
- **Caixa Preta (eventos_anomalias_saude):** eventos de desvio do baseline, append-only, permanente.
- **Carga Inicial:** resgate de 30 dias históricos do Health Connect no 1º acesso (alimenta a Retrospectiva de Boas-Vindas).
- **Cenoura:** teaser borrado do dia 7, renomeado "Projeção de Hábitos e Consistência".
- **Blast Radius:** princípio de menor privilégio (admin travado fora de dados clínicos).
- **EAV:** Entidade-Atributo-Valor (formato longo, 1 linha por medição).
- **FIFO 3 dias:** janela de retenção do dado bruto de alta frequência no device.

*Fim do Documento Mestre v5.0. Para continuidade: cole este arquivo em qualquer nova sessão de IA. Evolua por adendo/log durante fases ativas; consolide numa v6.0 no próximo marco. Atualize a Matriz (Parte 3.3) e os Logs (Parte 11) a cada entrega.*
