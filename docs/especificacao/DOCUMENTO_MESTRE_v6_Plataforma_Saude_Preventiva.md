# DOCUMENTO MESTRE v6.0 — PLATAFORMA DE SAÚDE PREVENTIVA COM IA
## Ecossistema Unificado B2C/B2B (Single-Backend / Multi-App)

**Data:** 30 de Julho de 2026
**Status:** FONTE ÚNICA DE VERDADE E AUTOSSUFICIENTE. Este documento consolida e substitui integralmente: Documento Mestre v5.0, Adendo v5.1 (Pipeline/Governança), Adendo v5.2 (Dashboards/Widgets), os Relatórios de Fim de Tarefa de 17–29/Jul/2026 e a lista de Melhorias de 24/Jul/2026. Qualquer IA que receba este arquivo deve conseguir assumir o projeto sem contexto adicional.

**Precedência:** este documento (v6.0) prevalece sobre todos os anteriores.

**Documento-anexo vigente (não substituído):** PLANO DE MARCA, MARKETING E LANÇAMENTO v1.0 (22/Jul/2026). Em decisões de produto/técnica, este Mestre prevalece; em marketing, o Plano prevalece. As decisões daquele plano estão registradas no Log (11.5).

### Documentos históricos (apenas consulta — NÃO usar para execução)
Documento Mestre v3.0/v5.0; Adendos v4.0/v5.1/v5.2; logs de execução até 29/Jul/2026.

---

# PARTE 0 — INSTRUÇÕES DE OPERAÇÃO PARA O ASSISTENTE DE IA

Se você é uma IA recebendo este documento, siga em ordem de precedência:

1. **NUNCA implemente, expanda ou corrija** itens EM HOLD (Parte 4).
2. **Antes de escrever código novo**, verifique a Matriz de Status (Parte 3) e **investigue o código real antes de presumir** — a experiência registrada mostra que specs de tarefa frequentemente presumem errado (arquivos que já existem, tabelas que já existem, bugs com outra causa). O padrão comprovado é: auditar primeiro, reportar o achado, então agir. "Declarado-implementado" (✅) = relatado por sessão anterior; ⚠️ e ✅ são não-verificados-por-humano até auditar.
3. **Requisitos de segurança (Parte 6) são bloqueadores de release.**
4. **Diretrizes de UX (Parte 8) prevalecem** sobre qualquer default visual.
5. **Regra de arquitetura inegociável:** toda lógica sensível (pontos, streaks, scores, elegibilidade, trial, prescrição, criação de vínculos, validação de leituras de OCR) é server-side (Edge Functions/Cron). O cliente apenas exibe.
6. **Regra de dados inegociável:** nenhum dado real de usuário em IA de tier gratuito ou com cláusula de treinamento. Zero mídia persistida (pipeline RAM volátil).
7. **Git:** proibido force push; branch main protegida; PRs obrigatórios; zero segredos/chaves/IDs em código; stacked branches.
8. **Perfil do fundador:** não-desenvolvedor, solo, usando IA para 100% do código. Explique em linguagem simples, uma tarefa por vez, sempre diga como testar.
9. **Ferramenta de execução:** Claude Code (Parte 10 traz política de modelos e template de prompt).
10. **Toda migração de banco** = RLS habilitado + policy vinculada a `auth.uid()`/vínculo + **GRANT explícito** para o papel `authenticated` (e, quando um processo servidor precisar de DML, GRANT explícito também para `service_role` — precedente aberto em `cache_sinonimos_alimentos`).
11. **Idioma:** português brasileiro. i18n em pt/en/es (pt é a fonte).
12. **Não gerar novos documentos** exceto quando o fundador pedir explicitamente ("consolida"/"gera"). Evolução por adendo/log; consolidação em marcos.
13. **Relatório de fim de tarefa obrigatório:** ao concluir qualquer tarefa, o agente reporta em formato registrável (para o fundador colar no adendo/log): decisões de infraestrutura/ambiente/configuração/arquitetura tomadas; entidades novas criadas; desvios da spec; pendências e riscos abertos. (Regra do v5.1, comprovada em uso — evitou nova perda de histórico.)
14. **"Validação = completa funcionalmente, crua visualmente":** tela de validação é feia, não capenga. Toda funcionalidade existe e funciona; só o acabamento visual fica para depois. Nenhum agente interpreta "validação" como licença para omitir funcionalidade.
15. **Erro de app nunca se disfarça de erro de servidor:** em homolog/debug, toda tela exibe a classe/mensagem real do erro (sem dado sensível) além de logar; mensagens genéricas ("servidor ocupado") só para erros de rede/HTTP reais. Regra nascida do episódio de 24-29/Jul, que custou dias de diagnóstico errado.

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
**Marketing** mira nutricionistas esportivos + treinadores de corrida e seus pacientes usuários de Garmin — nicho onde a dor é aguda, o diferencial é máximo (telemetria + prescrição no relógio) e os concorrentes são fracos. **Beachhead de marketing, leque técnico aberto:** a tecnologia (Health Connect/HealthKit) atinge do smartwatch de R$ 200 ao Apple Watch — restringe-se a mensagem de entrada, não o produto.

## 1.5 Mercado
- Global de apps saúde/fitness: US$ 13,8–14,6 bi → projeção > US$ 33 bi (CAGR > 13,5%).
- Validadores globais: Cal AI (visão por foto, ARR US$ 30-35M, vendida ~US$ 50M), Whoop (US$ 3,6 bi), Strava (US$ 2,2 bi), MyFitnessPal (US$ 310M/ano).
- **Categoria "exames+wearables+nutrição" já validada nos EUA:** InsideTracker, OneTwenty, Function Health (~US$ 300M captados), Superpower; Whoop e Oura adicionaram exames via Quest — consolidação em curso; timing importa.
- **Distinção regulatória crítica:** esses players **são as testadoras** (CLIA/FDA). Nós **não**: o usuário já possui o exame; nós lemos o PDF, extraímos e organizamos a série temporal. Somos **organizador de dados que o usuário já possui**, não plataforma de diagnóstico. Base da blindagem SaMD (Parte 5).
- Cenário nacional: Wellhub não faz inteligência de dados; Desrotulando é ferramenta isolada; Dietbox/Nutrium têm apps de paciente fracos. **Concorrentes B2B diretos a monitorar:** DietSystem (R$ 79,90/mês; extração de exames por IA + análise de foto + app + WhatsApp) e SimpleDiet (R$ 27,90/mês; extração de PDF). Nenhum tem telemetria contínua de wearables nem o loop prescrição→relógio.

## 1.6 Fosso defensável (combinação que nenhum player reúne)
(1) Brasil-first (PDF de labs locais, idioma, preço, TACO); (2) telemetria contínua de wearables cruzada a exames e nutrição; (3) motor de retenção gamificado; (4) captura por foto de aparelhos analógicos (glicosímetro/pressão do sênior sem wearable caro); (5) loop completo profissional→prescrição→relógio Garmin; (6) base longitudinal que aumenta de valor e custo de troca com o tempo.

## 1.7 Lacunas não-técnicas (pendências)
1. **Análise de CAC** antes de investir em divulgação paga (o Plano de Marketing v1.0 adota orgânico-primeiro; CAC pago só entra em pauta se o orgânico estagnar após 3 meses de execução consistente).
2. **Resposta competitiva** (Samsung/Google podem embutir foto grátis; fosso real = base longitudinal + B2B).
3. **Validação primária:** 20 nutricionistas + 20 usuários-alvo antes do lançamento público.

## 1.8 Unit economics
- B2C anual R$ 179,90 (herói do funil) ≈ R$ 142 líquidos/ano após loja 15% + imposto 6%. **Teto de CAC = R$ 142; meta ≤ R$ 47.**
- B2B margem > 80% (custo IA agregado R$ 0,30–0,60/carteira/mês).
- Premissa realista: conversão trial→pago 1–2,5%; retenção 30 dias de mercado 5–10%.
- Premissa corrigida: **"custo mínimo controlado"**, não "custo zero".
- **Terceira linha de receita (v5.2):** créditos de Análise Complexa Nível 3 (Parte 2.4).

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
| Domínio .com.br | ~R$ 40/ano | Fase 0 do Plano de Marketing |
| Registro de marca INPI (ME/EPP) | ~R$ 142–355 | Recomendado antes do lançamento público |

## 1.10 Situação jurídico-fiscal
Operação em CPF na fase de teste e primeiras vendas (carnê-leão; rendimento do exterior até 27,5%). **MEI não permitido** → ME/Simples. Responsabilidade ilimitada no CPF → gatilho de CNPJ (50 assinantes OU campanha pública) é mandatório. LGPD aplica-se desde o 1º usuário real.

---

# PARTE 2 — PREÇOS

## 2.1 B2B — pacote por profissional, valor FIXO por faixa
- **Essencial (sem Garmin, até 15 pacientes): R$ 97/mês.**
- **Performance (com Garmin, até 40 pacientes): R$ 167/mês.**
- **Fundadores:** primeiros 10–20 profissionais, desconto vitalício (~R$ 67) por feedback + depoimento.
- Margem > 80%. Teto de slots do pacote **ainda não implementado** no motor de vínculos (fica ilimitado até o faturamento existir — TODO documentado no código).

## 2.2 B2C — usuário individual
- **Anual (herói): R$ 179,90/ano** (≈ R$ 15/mês).
- **Mensal (âncora, não para vender): R$ 34,90/mês.**
- Não lançar B2C com desconto; se precisar de tração, estender trial (21 dias), nunca cortar preço.

## 2.3 Relação entre pagadores
Paciente que entra **via profissional não paga** e **não recebe gatilho de venda**. Cobrança B2C só quando o próprio usuário opta pelo plano individual. Múltiplos profissionais podem pagar pelo mesmo paciente (cada um consome 1 slot do seu pacote).

## 2.4 Terceira linha de receita — créditos de Análise Complexa (Nível 3, v5.2)
Adicional aos pacotes fixos. Profissional compra créditos/execuções; cada análise complexa (IA sob demanda, Parte 7.7) debita créditos; resultado fica gravado permanentemente (releitura sem custo). Calibração de preço por crédito: a definir (levantar custo real do Gemini por execução antes de precificar).

---

# PARTE 3 — ARQUITETURA TÉCNICA E MATRIZ DE STATUS

## 3.1 Stack
- **Backend:** Supabase (PostgreSQL + Auth + Edge Functions Deno/TS + Cron). RLS em todas as tabelas + GRANT explícito. Extensão **pgvector** habilitada (schema `extensions`).
- **Mobile:** Flutter (Feature-First), i18n pt/en/es. UI dinâmica por `perfil_uso` sem reinício. **Roteador enxuto (5 rotas):** login, cadastro, profile-selection, home (`MainNavigationPage`, que decide Atleta×Sênior internamente via `uiProfileSwitcher`) e definir-nova-senha (alcançável só via redirect de recuperação). Telas secundárias via `Navigator.push` (padrão do projeto). Projeto Android na main (v2 embedding; correção cirúrgica file_picker/AGP9; workmanager 0.9.x).
- **Web B2B:** React + TypeScript + Vite, code splitting, deploy Cloudflare Pages. Sidebar/DashboardLayout responsivo com render condicional por papel (Admin vs Profissional).
- **IA:** Google Gemini via **API paga**, chamada exclusivamente pelo servidor. **Família 2.5 DEPRECADA pelo Google (bloqueada para contas novas — episódio 24-29/Jul).** Nome do modelo vem SEMPRE da secret `GEMINI_MODEL_NAME` (troca sem redeploy); valor vigente: `gemini-3.1-flash-lite`. Nunca fixar modelo em código. Chaves só em secrets do servidor (`GEMINI_API_KEY`).
- **Wearables:** leitura LOCAL via pacote `health` (Health Connect / HealthKit), **estritamente READ-only** (permissões WRITE removidas do manifest — o app nunca escreve de volta no health store). Sync: oportunista + background 1x/dia (WorkManager). Carga inicial: 30 dias.
- **Garmin:** Edge Function `garmin-gateway/` (OAuth 1.0a HMAC-SHA1) server-to-server. Tokens em `garmin_conexoes` (isolada de GRANTs do app).

## 3.2 Legenda de status
✅ Declarado-implementado (não verificado por humano) · 🔍 Verificado (auditado/testado pelo fundador) · ⚠️ Parcial/desconectado · 🔲 Pendente · ⛔ Em Hold

## 3.3 MATRIZ DE STATUS (consolidada em 30/Jul/2026)

| # | Funcionalidade | Status | Nota |
|---|---|---|---|
| F01 | Esquema de dados + RLS em todas as tabelas | 🔍 | RLS validado em 6 cenários; schema B2B formalizado em git (slices 1-7) |
| F02 | Caixa Preta (eventos_anomalias_saude) | ⚠️ | Tabela existe; lógica de detecção pendente |
| F03 | Login social + OTP | ⚠️ | OAuth existe (signInWithOAuth); cadastro social NÃO grava campos de perfil (cai em ProfileSelectionPage) — ver R14. Login Google/Apple no painel web: backlog |
| F04 | Keystore/Keychain + biometria (CryptoStorageService) | ⚠️ | Mantido para tokens; **solicitação de biometria não está sendo habilitada no app** (apontamento 24/Jul) — auditar |
| F05 | Suíte de testes de segurança | ⚠️ | Revisar cobertura real |
| F06 | Cadastro adaptativo BR (ViaCEP) + Cadastro Dinâmico | ✅ | Religado e validado visualmente em aparelho: perfil de uso, switch profissional (especialidade+registro), idade/peso, ViaCEP ok. Correções pedidas em 24/Jul pendentes: **data de nascimento no lugar de idade (R13), telefone com DDI p/ WhatsApp, número/complemento no endereço, e-mail de confirmação** |
| F07 | Sync wearables (30 dias + oportunista + background) | ✅ | READ-only; leituras dedicadas de FC (🔍 testada pelo fundador) e Peso/Fitdays (✅, teste físico pendente); leitura geral "não está lendo" relatada em 24/Jul — diagnosticar com F49 |
| F08 | Dashboard modular drag-and-drop | ✅ | MainNavigationPage religada às rotas (grid reordenável, 4 abas, cards de câmera/balança/pressão) |
| F09 | Esteira 14 dias + "Projeção de Hábitos e Consistência" | ✅ | calculate-recovery-mode implantada (deixou de ser stub 501); e-mail do perfil sai cifrado |
| F10 | Gateway Gemini + Zero Storage Pipeline | ⚠️ | **Passos 1-2 PRONTOS no backend:** Edge Function `extract-metric-photo` ACTIVE (endpoint único; header `X-Tipo-Aparelho`: glicosimetro/pressaoArterial/balanca/pratoRefeicao); tubulação Zero Storage; gate determinístico do glicosímetro (20–600 mg/dL, confiança ≥0,70, HTTP 422 ilegível); prato→TACO com cálculo determinístico. **Passo 3 = BLOQUEADOR ATUAL: app não tem modelo de dados nem tela para o resultado nutricional do prato** (HealthPayloadModel só serve aparelhos). Pendentes: persistência em coleta_diaria (F34), antifraude foto-de-tela em modo bloqueio, extratores rótulo/balança refinados, PDF de exame |
| F11 | Painel React B2B | ✅ | Convite por e-mail, sala de espera/aprovação Admin, sidebar responsiva (R7 resolvido), PatientList/Details lendo de vínculos (fonte Zero Trust correta) |
| F12 | Filtragem seguradoras no painel | ⛔ | HOLD (Parte 4) |
| F13 | Garmin Training API Gateway (OAuth 1.0a) | ✅ | Depende de aprovação Garmin p/ teste real; construir com mock |
| F14 | Motor de sinistralidade | ⛔ | HOLD (Parte 4) |
| F15 | Seed de dados (seed_cloud.ts via Admin API) | ✅ parcial | 10 pacientes + 6 meses de métricas; 10 vínculos ativos. **Falta:** exames EAV variados + 2-3 anomalias na Caixa Preta |
| F16 | Exportação de dados (PDF+CSV, LGPD) | 🔲 | Onda 2; loop viral B2B (PDF com marca+QR) |
| F17 | Alerta de Tendência não-clínico | 🔲 | Onda 2/3, server-side |
| F18 | Widget de tela inicial (streak+anel) | 🔲 | Onda 2 |
| F19 | Válvula de proteção alimentar | 🔲 | Onda 2 |
| F20 | Modo Cuidador/Familiar | 🔲 | Onda 3 |
| F21 | Modo Recuperação Humano | ⚠️ | Infra server-side existe (esteira); lógica/UX do modo pendente |
| F22 | Registro de medicamentos + push local + missão | ⚠️ | Auditar implementação real |
| F23 | Relatórios sazonais macro | 🔲 | Onda 3 |
| F24 | Revogação instantânea de acesso do profissional | ⚠️ | Via aceitar/encerrar vínculo; auditar |
| F25 | 2FA no painel web profissional | 🔲 | Onda 4 (bloqueador Fase 2) |
| F26 | Prescrição ativa (cardápio + treino) | 🔲 | Onda 4; prescrição por papel |
| F27 | Deep linking WhatsApp | 🔲 | Onda 4 |
| F28 | logs_acesso append-only | 🔲 | Criar schema já; popular na Fase 2 |
| F29 | Requisitos de segurança S1–S9 | 🔲 | Bloqueadores de release |
| F30 | Telas no design system (Parte 8) | 🔲 | Fase de acabamento (após validação funcional) |
| F31 | Índice de Bem-Estar (bem-estar, não diagnóstico) | 🔲 | Server-side |
| F32 | marcadores_referencia (dicionário i18n, 34 marcadores) | ✅ | Formalizado em migração na main; faixa_referencia NULA (usa faixa do PDF do lab) |
| F33 | resultados_exames refatorada p/ EAV | ✅ | Na main (slice 1) |
| F34 | coleta_diaria (EAV, origem/confiança) | 🔲 | **Próxima peça do F10:** o campo `confianca` já chega do servidor, pronto para gravar |
| F35 | Alta frequência bruta + FIFO 3 dias + consolidação no device | 🔲 | Ver G.4 |
| F36 | vinculos_profissional_paciente | ✅ | Motor completo na main + produção: criar (pendente)/aceitar/encerrar (+30d carência); convite por paciente_email via função SECURITY DEFINER; sem teto de slots ainda |
| F37 | Escopo de consentimento por vínculo | ⚠️ | Aceite BINÁRIO implementado com UI de consentimento no app (aviso de privacidade explícito). Granularidade = débito F37-fase2 |
| F38 | Liga por profissional + desafios | 🔲 | Onda 2/4 |
| F39 | Mensagens de ciclo de vida do vínculo | 🔲 | i18n |
| F40 | Bifurcação de paywall por pagador | 🔲 | Suprime venda p/ via-profissional |
| F41 | Verificação server-side de "acesso ativo" no login/refresh | 🔲 | Carência por ausência de QUALQUER acesso ativo |
| F42 | Onboarding e aprovação de profissionais | ⚠️ | Sala de espera + /admin (is_admin) + trigger anti-autopromoção FUNCIONANDO no painel. **Spec formal ainda pendente:** critério de aprovação (CRM/CRN?), fluxo de rejeição (R5) |
| F43 | Motor viral (retrospectivas + cartões + pontos sociais) | 🔲 | Bloco detalhado na Parte 7.3 |
| F44 | Ciclo menstrual e menopausa | 🔲 | Onda 3; opt-in separado |
| F45 | alimentos_referencia (TACO/USDA) + medidas caseiras | ✅ | Tabelas na main e no banco; 8 alimentos seed (5 TACO originais + pão de queijo, refrigerante, whey); scripts idempotentes. **Carga completa da TACO pendente** |
| F46 | Nutrição semântica (pgvector + cache de sinônimos) | ⚠️ | Coluna `embedding vector(768)` + `cache_sinonimos_alimentos` + semeadeira `seed_food_embeddings.ts` (batch 20, RETRIEVAL_DOCUMENT) prontos. **Pendentes:** aplicar/decidir a migração no remoto, rodar a semeadeira (GEMINI_API_KEY no .env local), Edge Function de busca vetorial (RETRIEVAL_QUERY), índice hnsw/ivfflat quando houver volume |
| F47 | Recuperação de senha ponta a ponta | ✅ | RecuperarSenhaPage (anti-enumeração) + deep link Android + AuthRecoveryController + rota travada definir-nova-senha. Teste com e-mail real no aparelho pendente |
| F48 | Leituras dedicadas Health Connect (validação de cano) | ✅ | TesteFrequenciaCardiacaPage (🔍 validada fisicamente) + TestePesoPage (janela 30d, Fitdays; teste físico pendente) em Configurações |
| F49 | Diagnóstico de coleta de dados (tela de saúde da integração) | 🔲 | Pedido 24/Jul; detalhar spec (liga/desliga da interface de saúde em Configurações + visão do que está/não está chegando) |
| F50 | Widget único de câmera (5 botões: Alimentação, Rótulo, Pressão, Glicosímetro, Balança) | 🔲 | Pedido 24/Jul; não excluir widgets individuais — usuário escolhe o que fica na tela. Glicosímetro disponível também no perfil Atleta |
| F51 | Dashboards configuráveis + análise em 3 níveis (v5.2) | 🔲 | Nível 1 na Onda 4 (painel básico); Níveis 2/3 pós-validação. Schema na Parte 3.6 |

## 3.4 Entidades de banco (schema real consolidado)
**Tabelas:** `perfis_usuarios` (PII; criptografia — ver D2; + colunas `idade`, `peso_kg`, `registro_profissional`, `is_admin`, `eh_profissional`, `tipo_profissional` [enum `tipo_profissional_saude`], `status_aprovacao`), `anonymous_users.profile_data` (guarda `perfil_uso` — é de onde UiProfileSwitcher/roteador leem), `garmin_conexoes`, Trial/assinatura (server-side, GRANT só SELECT), `vinculos_profissional_paciente` (pendente/ativo/em_carencia/encerrado; pagador; tipo_produto), `marcadores_referencia` (34 marcadores i18n), `resultados_exames` (EAV), `metricas_saude_diarias`, `eventos_anomalias_saude` (append-only), `alimentos_referencia` (TACO/USDA; nome, aliases, macros/100g, `fonte`, coluna `embedding vector(768)` nullable), `alimentos_medidas_caseiras` (conversão medida→gramas), `cache_sinonimos_alimentos` (termo_buscado único, alimento_id FK, contagem_hits; GRANT explícito a service_role).
**Views:** `perfis_pacientes_vinculados` (B2B, SEM security_invoker — risco R1), `perfis_profissionais_vinculados` (B2C).
**Funções SQL:** `resolver_usuario_id_por_email` (SECURITY DEFINER, restrita à service_role).
**Edge Functions (3, todas ACTIVE em produção):** `extract-metric-photo` (F10; verify_jwt=true; só anon key — menor privilégio; secrets GEMINI_API_KEY + GEMINI_MODEL_NAME), `manage-professional-link` (criar/aceitar/encerrar vínculo; suporte a paciente_email), `calculate-recovery-mode` (esteira 14 dias).
**Scripts administrativos (web_painel/scripts):** `seed_cloud.ts`, `seed_teste_alimentos.ts`, `seed_food_embeddings.ts` (todos idempotentes; rodam com tsx; .env local com VITE_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY + GEMINI_API_KEY).
**Estrutura JSON de `auth.users.user_metadata` no cadastro:** `perfil_uso`, `eh_profissional`, `tipo_profissional`, `registro_profissional`, `idade`, `peso_kg` (chaves omitidas quando não se aplicam; nome/telefone/endereço NUNCA aqui — só no caminho cifrado de `perfis_usuarios`). Dupla persistência deliberada (metadata + tabela).
**Removidas:** `metricas_saude`, `ciclo_menstrual` (DROP formalizado em migração; volta redesenhada em F44).

## 3.5 ARQUITETURA DE DADOS DE SAÚDE — MODELO FINAL
- **G.1 `resultados_exames` — EAV (pontual/laboratorial).** Normalização de unidade na entrada guardando a original. Glicose de exame vive aqui.
- **G.2 `coleta_diaria` — EAV (frequente; device/OCR/manual).** `origem` obrigatório; `confianca` (score do OCR — já produzido pelo servidor no F10). Pressão, SpO2, glicose de dedo, peso, temperatura, autorrelatos. 🔲 pendente de criação (próxima peça do F10).
- **G.3 `metricas_saude_diarias` — COLUNAS FIXAS (agregado de wearable).** 1 linha/usuário/dia.
- **G.4 Alta frequência bruta — device + FIFO 3 dias; consolidação noturna em lote; bruto nunca sobe.**
- **G.5 `eventos_anomalias_saude` — Caixa Preta.** Anomalia = desvio do baseline do próprio usuário, nunca limiar clínico. Sem interpretação clínica ao usuário.
- **G.6 Leitura pela IA:** resumos textuais curtos pré-consolidados pelo Cron; nunca tabelas brutas.
- **G.7 Pipeline nutricional (F10/F45/F46) — "IA traduz, backend calcula":** Gemini identifica alimentos em **medidas caseiras** + score de confiança (JSON puro); backend cruza com `alimentos_referencia` por casamento **léxico determinístico** (normalização + exato→substring; item não-casado vai para `itens_nao_reconhecidos` com resposta 200 — o usuário decide na tela de confirmação); conversão medida→gramas→macros por regra de três sobre a TACO. Camada semântica (F46) entra como resolução de sinônimos via embedding + cache, mantendo o cálculo determinístico.

## 3.6 Schema dos Dashboards Configuráveis (v5.2 — construir na Onda 4; Nível 1 primeiro)
- **`catalogo_widgets`** (fonte de verdade de todo widget): `widget_codigo` PK, `escopo` (paciente/profissional), nomes i18n, `nivel` (1/2/3), `periodos_suportados`, `fonte_calculo` (sql_direto/cron_agregado/gemini_sob_demanda), `categoria`. Novo widget = nova linha, não código novo.
- **`configuracao_dashboard`**: usuario_id, escopo, widget_codigo FK, periodo_escolhido, posicao, ativo. Mesmo widget 2x com períodos distintos = linhas distintas.
- **`resultados_analise_nivel2`** (cache de correlações do Cron do fechamento de período; observações por template determinístico, sem IA na maioria). Índice `(paciente_id, widget_codigo, periodo, data_referencia DESC)`.
- **`analises_complexas_nivel3`** (execuções pagas, permanentes; prompt_usado p/ auditoria; NUNCA acessível pelo app do paciente; alimenta logs S5).
- **`creditos_profissional`** (saldo + histórico).
- Segurança herdada: GRANT explícito; RLS via `vinculos_profissional_paciente`; busca por nome/CPF/e-mail via função server-side (nunca índice em texto plano sobre campo criptografado).
- **Arquitetura em 3 níveis:** N1 = SQL direto em tempo real (sem custo); N2 = pré-calculado por Cron no fechamento do período; N3 = IA sob demanda paga, exclusiva do painel profissional (blindagem ANVISA: interpretação clínica só via CRM/CRN).
- **Dashboard do profissional:** widget = nome+período; clique → **lista de pacientes** (drill-down para ação/contato — diferencial contra Dietbox/Nutrium). Períodos: diário (dia anterior), semanal (última semana fechada seg-dom), mensal (mês anterior). Catálogo inicial de widgets: ver Adendo v5.2 Seções C/D (arquivado; catálogo vira seed de `catalogo_widgets`).
- **Tela individual do paciente:** cabeçalho fixo + sub-abas Dashboard / Telemetria / Alimentação / Exames / Insights (N2) / Análises Complexas (N3). Busca incremental por nome/CPF/e-mail (server-side).

---

# PARTE 4 — ITENS EM HOLD (PROIBIDO IMPLEMENTAR)

## 4.1 Score Atuarial / Sinistralidade para Seguradoras — ⛔ EM HOLD (F14, F12)
Congela: `sinistralidade_engine`, espelho TS, indicador "Redução de Sinistralidade", login administrativo de operadoras, venda/exibição de score a terceiros.
Motivos: (1) políticas Health Connect/HealthKit proíbem uso atuarial → risco de banimento; (2) cálculo estava no cliente; (3) LGPD exige base legal + consentimento destacado + RIPD inexistentes.
Retomada só sob TODAS as condições listadas no v5.0 (redesenho sem dados de health stores + consentimento revogável com benefício ao titular + server-side auditado + parecer LGPD/SUSEP + verificação das políticas das lojas). Se encontrar o código: não expandir/corrigir/integrar; manter atrás de feature flag desligada.

## 4.2 Fora de escopo sem nova revisão
Chat aberto de IA sobre saúde; SDKs proprietários de wearables além dos agregadores nativos; feed social estilo Strava; expansão internacional antes do PMF no Brasil.

---

# PARTE 5 — BLINDAGEM JURÍDICA E REGULATÓRIA

## 5.1 LGPD
- Dado de saúde = sensível (art. 11): consentimento específico/destacado; política de privacidade pública; direitos de exclusão e portabilidade (F16).
- **Pseudonimização ≠ anonimização.** Nunca usar "anônimo" em termos/marketing.
- Ranking público de localidade só com N ≥ 30.
- Proibido dado real em IA de tier gratuito/com treinamento.
- Incidente: 3 dias úteis à ANPD (S7). RIPD antes do lançamento público.
- **Consentimento de vínculo:** vínculos nascem **pendentes**; aceite do paciente libera a RLS. UI de consentimento no app com aviso de privacidade explícito ("este profissional terá acesso aos seus exames"). Em produção, backfills nascem pendentes (R4).
- Recuperação de senha com mensagem neutra anti-enumeração de contas (padrão implementado — manter).

## 5.2 ANVISA (RDC 657/2022) — classificação pela FINALIDADE
- Somos **organizador de dados que o usuário já possui**. App B2C não cruza exames com telemetria para predições clínicas individuais; correlações clínicas só no painel do profissional. Análises Nível 3 EXCLUSIVAS do painel (nunca ao leigo).
- Cenoura do dia 7 = "Projeção de Hábitos e Consistência".
- `faixa_referencia` NULA por padrão (usa a faixa do PDF do lab; sem faixa → não exibir).
- IA proibida de laudo/diagnóstico ao usuário. O pipeline "IA traduz, backend calcula" reforça o enquadramento: o app calcula por regra determinística sobre tabela pública (TACO), não "a IA achou".
- Gate determinístico de leituras (glicose 20–600 mg/dL etc.): **em saúde, não gravar > gravar errado** — rejeição por regra, nunca palavra final do LLM.
- Parecer jurídico formal antes do lançamento público.

## 5.3 Lojas e Health Connect
- Play: Data Safety + **Declaração de Apps de Saúde do Health Connect** (revisão manual, semanas — protocolar JÁ). Internal Testing imediato (até 100 testadores); produção exige teste fechado de 14 dias.
- **Garmin Developer Program:** maior lead time — protocolar JÁ. Sem aprovação, Training API via mock; leitura via Health Connect não depende da Garmin.
- **applicationId ainda é `com.example.atleta_gamificacao`** (placeholder) — trocar por id definitivo ANTES de qualquer build de loja (R10; depende do naming do Plano de Marketing).

## 5.4 Permissões de dados (minimização)
Pedir só o que uma feature visível usa. **Estado atual: Health Connect estritamente READ** (WRITE removido do manifest e do código — redução real de permissão, revogada automaticamente em updates). Métodos de leitura pontual pedem só o tipo necessário (ex.: teste de FC pede só HEART_RATE). Tratar estados vazios graciosamente (nem todo aparelho tem HRV/SpO2; balança sem sincronização = "nenhum registro em 30 dias" é estado esperado, não bug).

---

# PARTE 6 — REQUISITOS DE SEGURANÇA (BLOQUEADORES DE RELEASE)

Complementam TLS 1.3 + SSL pinning, Keystore/Keychain + biometria, RLS + GRANT e Zero Storage.
- **S1. Sessão server-side:** refresh token com rotação; "Desconectar todos os aparelhos"; revogação <60s. Race condition do onAuthStateChange corrigida (signOut explícito — também aplicado no fluxo "solicitar acesso" do painel).
- **S2. Proteção de tela:** FLAG_SECURE nas rotas clínicas; exceção: telas de gamificação permitem screenshot.
- **S3. Root/jailbreak:** detectar, avisar sem bloquear, flag `dispositivo_comprometido`.
- **S4. Rate limiting + teto financeiro:** máx. 30 análises de imagem/dia/usuário; alerta de billing US$ 10/dia; circuit breaker global. (Backlog relacionado: retry com backoff para 503 do Gemini dentro da Edge Function — 2 tentativas, 1-2s — e fallback de modelo; só implementar se o 503 virar bloqueador de teste.)
- **S5. logs_acesso append-only:** criar já; popular na Fase 2. Análises Nível 3 alimentam este log.
- **S6. Backup testado:** ritual mensal de restauração em staging.
- **S7. Plano de resposta a incidente:** `INCIDENT_RESPONSE.md` no repo privado.
- **S8. Higiene de repositório:** main protegida; PRs; varredura de segredos; zero chaves em código; Service Role Key SEM prefixo VITE_. **Pendências ativas: rotacionar a Service Role Key (R6 — ela segue viva no .env local do painel, usada pelos scripts de seed) e tratar a duplicação da GEMINI_API_KEY no .env local (R15).** Anon key pode ir no app (--dart-define) — RLS protege, não o sigilo dela.
- **S9. Revisão humana sênior antes do 1º release público:** RLS, tokens/biometria, pipeline RAM, e prioritariamente a view `perfis_pacientes_vinculados` sem security_invoker (R1).
- **Menor privilégio comprovado em Edge Functions:** `extract-metric-photo` roda só com anon key (não lê/escreve tabela); manter o padrão — service_role só quando a função realmente precisa de DML.
- **Contas de teste segregadas** (nunca híbridas admin+profissional). Usuários/artefatos de teste são apagados ao fim da tarefa (padrão dos relatórios: screenshots, contas via Admin API, branches temporárias).
- **Método de validação visual:** Playwright headless (375/1280px) no web; screenshots via ADB no aparelho físico para o app.
- **Segurança "tipo banco" (apontamento 24/Jul):** dúvida do fundador sobre a implementação real (biometria de abertura + FLAG_SECURE + timeout de sessão) — auditar como pacote com F04/S2.

---

# PARTE 7 — REGRAS DE NEGÓCIO

## 7.1 Gamificação e retenção (base)
- **Streak diário:** Condição 1 (1 foto de refeição OU, até 2x/semana, registro rápido sem foto) + Condição 2 (treino Garmin OU 8.000 passos). Quebra zera a chama e −100 pts. Server-side.
- **Rankings:** ligas de amigos/cidade/estado/país; cache noturno; N≥30 para localidade pública.
- **Esteira 14 dias:** Dia 1 carga de 30 dias; dias 1–6 missões de upload de exames; dia 7 desbloqueio + teaser; conversão dia 14. Trial atrelado a `auth.users.created_at` (revisar — R3). Backend `calculate-recovery-mode` implantado.
- **Modo Recuperação Humano (F21):** voluntário, congela ofensivas, paleta calma. Lógica/UX pendentes.
- **Medicamentos:** dose/horário, push local, missão diária (+10 pts).

## 7.2 Autorrelato (regra de ouro)
Opt-in, toque único, recompensado, DESVINCULADO da ofensiva. Máx. 1 pergunta/dia rotativa.

## 7.3 MOTOR VIRAL (F43) — três momentos + pontos sociais + loop B2B
(Detalhamento integral preservado do v5.0 — resumo operacional:)
- **(a) Retrospectiva de Boas-Vindas (dia 1):** 5 cartões stories calculados no device durante a Carga Inicial; degradação graciosa (14+ dias completa / 3-13 curta / <3 pula e promete no dia 7); anti-vergonha. Métrica-norte: partilha do cartão 5.
- **(b) Cartão da Primeira Semana (dia 7):** celebração ANTES do cadeado; chama de 7 dias como herói visual; percentil (nunca posição absoluta); variantes 7/7 dourado / progresso / recomeço; legenda com deep link de convite.
- **(c) Retrospectiva Mensal:** dia 1 às 19h para todos (Cron da madrugada pré-calcula); 5 cartões com setas de evolução; push também para dormentes (ressurreição); cartão 4 nunca expõe nomes de amigos.
- **Pontos sociais (server-side, nunca alimentam a ofensiva):** convite +10 (teto 3/dia); aceito +50 (anti-farming: instalou+conta+1º dia); liga 3+ +100 (1x); desafio +20; partilha de cartão +15 (teto 2/dia) +10 por plataforma distinta.
- **(d) Loop B2B (o mais valioso):** exportação PDF (F16) com capa/marca + QR "profissional: acompanhe seus pacientes assim".
- Regras transversais: partilha opt-in por ação; cartões públicos só com dados de atividade/gamificação (nunca clínicos); visual do design system é pré-requisito.

## 7.4 Modelo multi-profissional
- **Duas portas:** via profissional (sem gatilho de venda) e individual.
- **Vínculo = unidade central:** criado só via `manage-professional-link` (sem RLS de INSERT = antifraude de slot); nasce pendente; aceitar só pelo paciente; encerrar por qualquer lado com carência +30 dias; convite por e-mail via `resolver_usuario_id_por_email` (service_role). Teto de slots pendente (entra com faturamento).
- **Permissões:** **leitura uniforme** (todo vínculo aceito vê tudo) + **prescrição por papel** (treino=personal→Garmin; cardápio=nutricionista; médico vê tudo, prescrição a definir), checada server-side. **Exceção:** ciclo menstrual FORA por padrão (opt-in separado da mulher).
- **Consentimento (F37):** binário, com microcopy honesta. Granularidade = débito F37-fase2.
- **Carência (F41):** por ausência de QUALQUER acesso ativo; 30 dias; bloqueio preserva dados e pausa chama.
- **Aprovação de profissionais (F42):** Admin×Profissional com trava Blast Radius; sala de espera + /admin funcionando; trigger anti-autopromoção no banco. Spec pendente (R5).

## 7.5 Prescrição por papel (Onda 4)
Leitura: todos veem tudo. Escrita: treino→personal (+Garmin); cardápio→nutricionista; médico→leitura total.

## 7.6 Ciclo menstrual e menopausa (F44 — Onda 3)
Bem-estar/autoconhecimento; previsão de calendário sim, fertilidade NÃO; opt-in separado; nunca em ranking; recuo automático em ciclos irregulares; menopausa como vertente do Guardião.

## 7.7 Análises em 3 níveis (v5.2 — regras de negócio)
- N1 tempo real sem custo; N2 pré-calculado por Cron; N3 IA sob demanda **paga por execução**, resultado permanente (releitura grátis; nova execução = novo débito), exclusiva do painel profissional.
- Widget "Janela de queda de engajamento" e "Pacientes inativos" = alerta precoce para o profissional agir antes do abandono (objetivo de negócio: acompanhamento ativo demonstrável).

---

# PARTE 8 — DESIGN SYSTEM E UX (PREVALECE SOBRE DEFAULTS DE IA)

## 8.1 Proibições ("tiques de IA")
Gradiente roxo/índigo; glassmorphism generalizado; sombras difusas em cascata; emoji como ícone; paleta creme+serifa+terracota default; fundo quase-preto com verde-ácido; placeholders; microcopy traduzida do inglês; dois estilos de componente para a mesma função.

## 8.2 Identidades por superfície
- **Atleta (escuro competitivo):** base grafite #0E1114; UM acento de energia; números tabulares condensados; assinatura = anel de HealthScore segmentado.
- **Guardião (claro clínico-acolhedor):** off-white quente; corpo ≥18pt; toque ≥48dp; AA/AAA; assinatura = linha do tempo vertical. **Escala de fonte do tema Sênior via `_escalarTextTheme`** (tamanhos oficiais M3 como base) — NUNCA `TextStyle.apply(fontSizeFactor:)` sobre estilos sem fontSize (crash comprovado no Flutter 3.44.5; correção com 3 testes de regressão).
- **B2B Web:** densidade alta, hairlines, zero ornamento, Recharts sóbrio.

## 8.3 Tokens (fonte única)
Grade 8pt; um raio global + chips 999; escala tipográfica única (12/14/16/18/22/28/34); ícones outline 1 peso; cores só via tokens semânticos, zero hex em widget; motion 150/250ms, reduce-motion respeitado.

## 8.4 Padrões de tela
Estados vazios projetados; skeletons; **erros com direção e com causa distinta** (regra 0.15: rede ≠ parse ≠ dado ausente ≠ inesperado; detalhe técnico visível em debug/homolog; nunca stack trace em produção); 1 número-herói por tela; acessibilidade AA como piso; texto escalável a 130%.

## 8.5 Microcopy pt-BR nativo
Sentence case; verbos que dizem o que acontece; nomes estáveis; tons por superfície; glossário fixo no i18n (pt é a fonte). Títulos contextuais por tipo de captura na câmera ("Fotografar Refeição" vs "Tirar Foto do Visor do Aparelho").

## 8.6 Checklist por tela
(1) objetivo + número-herói; (2) checar 8.1; (3) só tokens 8.3; (4) validação Playwright 375/1280px com palavras longas pt-BR.

---

# PARTE 9 — ETAPAS DE EXECUÇÃO E PLANO DE TESTE

## 9.1 Prioridade imediata (ordem obrigatória, 30/Jul/2026)
1. **F10 Passo 3 — Modelo de dados + tela de confirmação do prato de comida** (funcionalmente completa, crua): lista de alimentos identificados em medidas caseiras, [+]/[−], adicionar/remover item, recálculo determinístico TACO na hora, score de confiança visível, itens_nao_reconhecidos tratados. É o bloqueador atual: sem ela, a foto do prato responde 200 e o app não tem onde exibir.
2. **F34 `coleta_diaria`** + persistência das leituras confirmadas (glicose já chega com `confianca` do servidor; comida grava no diário alimentar após confirmação).
3. **D2 — Migração da criptografia de PII para server-side em repouso** antes de qualquer dado real. Modelo topo de linha.
4. **Build Android de homolog + rodada de teste fake completa** (roteiro 9.3).
Em paralelo (lead time externo, iniciar/verificar JÁ): Play Console, Declaração Health Connect, Garmin Developer, naming/handles (Plano de Marketing Fase 0).
Rápidos de alto valor na fila: rotacionar Service Role Key (R6); rodar semeadeira de embeddings (F46); F15 completar seed (exames+anomalias); teste físico de peso (F48) e de recuperação de senha (F47).

## 9.2 Ambientes (homolog × produção)
- **Alvo:** dois projetos Supabase (`homolog` free + `prod` Pro). **Estado real (R-E4 ampliado):** existe UM projeto cloud (`xtipphglpqqrjguxcajn`), tratado nos relatórios ora como homolog ora como "produção". Antes de dado real: criar o projeto prod separado e aplicar o checklist de paridade (secrets GEMINI_*, verify_jwt, providers de Auth, GRANTs, config.toml).
- **Git:** fluxo-alvo develop→homolog / main→prod. **Prática atual:** trabalho direto sobre main protegida com merges fast-forward por tarefa — aceitável na fase solo/fake; reavaliar ao entrar dado real.
- **Migrações:** via CLI, versionadas; histórico remoto reconciliado (17 migrations local=remoto após `migration repair` da 20260722). **Regra nova:** ao detectar schema drift, rodar `db pull/diff` e formalizar — nunca conviver com drift silencioso (R9).
- **Rodar o app:** `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` (sem credenciais o app agora mostra tela de erro clara em vez de travar na splash). Sugestão pendente: `--dart-define-from-file` com arquivo fora do git.
- **Cloudflare Pages:** preview por branch.
- **Checklist de subida a produção:** migração testada em homolog + smoke test + backup + registro do que mudou + paridade de configuração.

## 9.3 Plano de teste (sequência)
Web fake (pronto; sidebar corrigida) → app fake (após F10 passo 3) → correções → **zerar** → teste real do fundador 1 semana com diário → amigos com Garmin/Android via loja (CPF) → iOS depois (Mac em casa; esposa/filho com Garmin).
- Envio de treino Garmin: mock até aprovação.
- **Backlog disciplinado:** nada do backlog entra em dev durante testes, exceto bug que impede o teste. Backlog atual consolidado na Parte 9.5.

## 9.4 Roadmap por ondas
- **Onda 2 (foco):** App Atleta BR — F10 completo, F16, F17, F18, F19, F43, esteira.
- **Onda 3:** Guardião + F20 + F23 + F44.
- **Onda 4 (Fase 2 B2B):** F25, F28/S5, F26, Garmin em produção, F27, F42 completo, **F51 Nível 1 (widgets simples)**. Meta: primeiros 10 profissionais pagantes.
- **Pós-validação:** F51 Níveis 2/3 (sob demanda comprovada).
- **Fase 3 (seguradoras): ⛔ HOLD.**
- **Pré-lançamento público:** política de privacidade + termos, RIPD, parecer, S9, CAC, validação primária, CNPJ, marca (Plano de Marketing Fase 3).

## 9.5 BACKLOG CONSOLIDADO (origem 24/Jul + relatórios; itens sem número próprio)
**Cadastro/Auth:** data de nascimento no lugar de idade (R13 — decidir migração); telefone com DDI/formato WhatsApp; endereço com número/complemento; e-mail de confirmação; login Google/Apple no painel web; campos de perfil no cadastro social (R14); teste físico do deep link de recuperação.
**App:** biometria de abertura não habilitada (F04); auditoria "segurança tipo banco"; F49 diagnóstico de coleta + liga/desliga Health Connect; F50 widget único de câmera; glicosímetro no perfil Atleta (parcialmente atendido — botão existe no dashboard Guardião/Sênior; estender ao Atleta); apagar `isInDebugMode` do background_sync_manager (deprecado, no-op).
**Custo de IA:** modelo distinto por tipo de captura via configuração (visores/PDF em tier mais capaz; comida no lite) — evolução natural da secret GEMINI_MODEL_NAME para um mapa por `tipo_captura`.
**Infra/Flutter:** migração futura Built-in Kotlin (4 plugins: device_info_plus, file_picker, health, workmanager_android) — quando migrarem, ligar `android.builtInKotlin=true` e remover o bloco cirúrgico do file_picker; retry/backoff 503 na Edge Function; limpar código morto (`GeminiGatewayService.processarImagemVisorPrato`, `IntelligenceController.analisarFotoVisor`).
**F46:** aplicar migração semântica, rodar semeadeira, Edge Function de busca (RETRIEVAL_QUERY), índice vetorial com volume.

---

# PARTE 10 — EXECUÇÃO COM CLAUDE CODE + POLÍTICA DE MODELOS

## 10.1 Ferramentas
Execução no **Claude Code**. Planejamento/prompts em chat de fronteira (Gemini 3.1 Pro como gerente de projeto; Claude como consultor estratégico/revisor; GPT segunda opinião). Documento Mestre = memória oficial.

## 10.2 Política de modelos — informar SEMPRE no cabeçalho do prompt
- **Padrão: Claude Sonnet** (~80% das tarefas).
- **Trivial: Claude Haiku** (copy, i18n, renomeações).
- **Crítico: topo de linha** (RLS, segurança, tokens/biometria, pipeline RAM, OAuth Garmin, criptografia, arquitetura).
- Economia: sessões curtas, /clear entre tarefas, apontar arquivos específicos.

## 10.3 Template de prompt (usar sempre)
```
[MODELO RECOMENDADO: Sonnet | Haiku | Topo de linha — com 1 linha de justificativa]
[CONTEXTO]: Parte 0 do Documento Mestre v6.0 + seções relevantes à tarefa.
[TAREFA]: objetivo único (1 tarefa por sessão).
[ARQUIVOS]: caminhos exatos a criar/alterar (o agente DEVE investigar se já existem equivalentes antes de criar).
[RESTRIÇÕES]: holds (Parte 4); segurança (Parte 6); UX (Parte 8); server-side por padrão; GRANT explícito em toda migração; sem segredos em código; sem force push; "validação = completa funcionalmente, crua visualmente" (Parte 0.14); erros nunca disfarçados (Parte 0.15).
[CRITÉRIO DE ACEITE]: como o fundador (não-dev) testa, passo a passo, em linguagem simples.
[ENTREGÁVEL]:
  1. Código + explicação simples do que foi feito.
  2. Commit em branch própria + instrução de PR (ou merge, se explicitamente autorizado).
  3. RELATÓRIO DE FIM DE TAREFA (obrigatório):
     - Decisões técnicas/arquiteturais (decisão | motivo) para o Log (Parte 11).
     - Mudanças de infra/ambiente/config NÃO visíveis no código (secrets, config.toml, providers, GRANTs, manifest nativo).
     - Entidades novas (tabelas, views, funções, Edge Functions, telas, chaves i18n) — para sincronizar a Parte 3.4.
     - Desvios da spec (o que ficou diferente e por quê).
     - Pendências e riscos deixados em aberto.
```

## 10.4 Ritual do fundador
1 tarefa/sessão → implementação + explicação → teste pelo aceite → commit/PR → merge. Quebrou: `git revert`. O fundador cola o Relatório de Fim de Tarefa no adendo/log corrente; consolidação no próximo marco (v7.0).

---

# PARTE 11 — REGISTRO DE DECISÕES (LOG IMUTÁVEL)

## 11.1 Decisões estratégicas e de produto (até 16/Jul — preservadas do v5.0)
| Data | Decisão | Motivo |
|---|---|---|
| Jul/2026 | Fase 3 (score seguradoras) EM HOLD | Políticas health stores + LGPD + cálculo no cliente |
| Jul/2026 | "Custo zero" → "custo mínimo controlado"; Gemini só API paga | Free tiers incompatíveis com dado de saúde |
| Jul/2026 | "Anonimizado" → "pseudonimizado" | LGPD |
| Jul/2026 | Cenoura do dia 7 = "Projeção de Hábitos e Consistência" | RDC 657/2022 |
| Jul/2026 | B2B = prioridade comercial; B2C = engajamento/aquisição | CAC B2C imprevisível |
| Jul/2026 | Beachhead = nutri esportivo/treinador + pacientes Garmin (marketing) | Menor fricção; diferencial máximo |
| Jul/2026 | Server-side para toda lógica sensível | Cliente é manipulável |
| Jul/2026 | Ranking público só com N≥30 | Reidentificação |
| Jul/2026 | CPF com gatilho de CNPJ (50 assinantes OU campanha) | Responsabilidade ilimitada |
| Jul/2026 | "Organizador de dados", não "plataforma de diagnóstico" | Blindagem SaMD |
| Jul/2026 | Preços B2B R$97/R$167; B2C R$179,90/ano + R$34,90 âncora | Ancoragem |
| Jul/2026 | Multi-profissional: vínculo = unidade de slot/faturamento | SaaS multi-assento |
| Jul/2026 | Leitura uniforme + prescrição por papel; ciclo menstrual fora (opt-in) | Valor no cruzamento; privacidade |
| Jul/2026 | Carência/bloqueio por ausência de qualquer acesso ativo | Reaproveita usuário; LGPD |
| Jul/2026 | Dados de saúde em múltiplas tabelas por natureza | Modelagem correta |
| Jul/2026 | Consolidação de alta freq. no device; bruto não sobe | Custo/UX/segurança |
| Jul/2026 | Anomalia = desvio do baseline próprio, sem interpretação clínica | Limiar absoluto = dispositivo médico |
| Jul/2026 | Autorrelato opt-in, desvinculado da ofensiva | Coleta sem matar retenção |
| Jul/2026 | App único de paciente; Guardião separável no futuro | Backend único + fundador solo |
| Jul/2026 | Motor viral: 3 momentos + pontos sociais + loop PDF B2B | Viralidade nos picos de orgulho |
| Jul/2026 | Ciclo: previsão de calendário sim, fertilidade não | Enquadramento de bem-estar |
| 16/Jul/2026 | D1 consentimento binário + microcopy honesta; D2 criptografia PII server-side antes de dado real; D3 leitura uniforme + prescrição por papel | Ver v5.0 11.3 |

## 11.2 Decisões técnicas 12–16/Jul (auditoria + Etapa 0.5 + estrutura B2B — preservadas do v5.0)
(Tabela integral preservada por referência histórica: rebaixamentos da auditoria; Etapa 0.5; remoção de tabelas órfãs; trial por created_at; EAV in-place; vínculos sem RLS de INSERT; faixa_referencia nula; RLS 6 cenários; GRANTs com exclusões; views de contorno; resolver_usuario_id_por_email; race condition; seed via Admin API; contas segregadas; stacked branches; Playwright.)

## 11.3 Decisões do Adendo v5.1 (16/Jul)
| Decisão | Motivo |
|---|---|
| Pipeline de comida: "IA traduz (medidas caseiras + confiança), backend calcula (TACO/USDA)" | Evita alucinação matemática; número reproduzível/auditável |
| TACO primária + USDA fallback (alimentos_referencia) | Brasil-first; gratuito |
| Resolução de imagem por tipo_captura (comida ~512px; visores/PDF alta) | Errar dígito de saúde é pior que gastar token |
| Padrão UX "IA estima + usuário edita" (nada salva automático) | Credibilidade + baixo atrito |
| Regra "validação = completa funcionalmente, crua visualmente" | Evolução vira re-skin |
| Relatório de fim de tarefa obrigatório | Atacar causa raiz da perda de histórico |
| Sequência F10: tubulação → extrator simples → comida → tela → demais → PDF | Provar cérebro antes de UI |

## 11.4 Decisões técnicas 17–29/Jul (execução F10 + integração + fundação Android/Auth)
| Data | Decisão | Motivo |
|---|---|---|
| ~17/Jul | Edge Function única `extract-metric-photo` para todos os tipos de foto, diferenciada por header `X-Tipo-Aparelho` (NÃO criar analyze-meal/gemini-vision) | App já apontava para o endpoint; tubulação única + extratores incrementais (A.8); evitar duas inteligências divergentes |
| ~17/Jul | Gate determinístico `avaliarLeitura` no servidor: glicose fora de 20–600 mg/dL, sem número ou confiança <0,70 → HTTP 422 "não consegui ler" | "Não gravar > gravar errado"; rejeita erro de dígito e mmol/L confundido |
| ~17/Jul | Função roda só com anon key (sem service_role) | Menor privilégio — não acessa tabela |
| ~17/Jul | Antifraude foto-de-tela = flag `possivel_foto_de_tela` propagada sem bloquear (bloqueio duro = débito p/ teste de campo) | Necessário para testar com imagem na tela do PC |
| ~18/Jul | Prato: casamento alimento/medida léxico determinístico (normalização + exato→substring), nunca fuzzy/IA; não-casado → `itens_nao_reconhecidos` com 200 | Só o backend decide; auditável; usuário resolve na confirmação |
| ~18/Jul | Resolução de comida via ResolutionPreset.low da câmera (sem decode/resize manual) | Zero dependência nova; frame grande nunca materializa na RAM |
| ~18/Jul | alimentos_referencia/medidas_caseiras no padrão marcadores_referencia (RLS + só SELECT; curadoria só por migration) | Dado público do produto |
| ~19/Jul | Correção cirúrgica file_picker (compilar Kotlin só nesse subprojeto); NÃO ligar builtInKotlin global | AGP9 + 4 plugins incompatíveis (testado: quebraria health/workmanager/device_info) |
| ~19/Jul | Splash congelada → `runApp(_MissingSupabaseCredentialsApp)` em vez de throw pré-runApp | Falha visível sem enfraquecer a recusa de boot |
| ~20/Jul | Cadastro Dinâmico: dupla persistência (user_metadata + perfis_usuarios); PII cifrada nunca em user_metadata; perfil_uso em anonymous_users.profile_data | Consistência pré/pós confirmação de e-mail; é de lá que o roteador lê (confirmado no código) |
| 22/Jul | Roteador reescrito para 4 rotas reais (login/cadastro/profile-selection/home=MainNavigationPage); stubs Athlete/Clinical removidos | Rotas nunca conectadas eram a causa de "features construídas não aparecem" |
| 22/Jul | Esteira: calculate-recovery-mode implantada (fim do stub 501); e-mail sai cifrado do app | Lógica sensível server-side |
| 22/Jul | DROP formal de metricas_saude/ciclo_menstrual (IF EXISTS, após confirmar zero referências e ausência em prod) | Alinhar git e produção |
| 22/Jul | GEMINI_MODEL_NAME como secret (modelo nunca hardcoded) | Troca de modelo sem redeploy — prevenção da classe de bug |
| 24/Jul | **Família Gemini 2.5 bloqueada para contas novas (404 do Google); gemini-1.5 já removido do catálogo; secret atualizada para gemini-3.1-flash-lite** | Deprecação externa; alias/env var absorve a próxima aposentadoria |
| 24-29/Jul | "Servidor ocupado" mascarava: resposta do prato não encaixa no HealthPayloadModel (não era exceção); mensagens diferenciadas por classe de erro + detalhe técnico só em kDebug/homolog + catch genérico final | Erro de app nunca se disfarça de erro de servidor (vira regra 0.15) |
| ~25/Jul | Crash Sênior: `.apply(fontSizeFactor:)` sobre TextTheme M3 com fontSize null → helper `_escalarTextTheme` com tamanhos oficiais M3 | Assertion do Flutter 3.44.5; derrubava todo o perfil Sênior |
| ~26/Jul | Health Connect estritamente READ (WRITE removido de código e manifest) | App nunca escreve no health store; minimização real |
| ~26/Jul | Métodos de leitura dedicados por sinal (FC 24h; Peso 30 dias) + telas de teste irmãs | Janela e semântica diferentes; não regredir tela já validada |
| ~27/Jul | PatientList/PatientDetails migrados de planejamento_clinico para vínculos | Fonte de autorização Zero Trust única; paciente aceito sem prescrição aparecia invisível |
| ~28/Jul | pgvector: estender alimentos_referencia (NÃO criar alimentos_taco) + cache_sinonimos_alimentos; 1º GRANT explícito a service_role | Evitar catálogo duplicado/órfão; ACL real para processo servidor |
| ~28/Jul | Semeadeira: REST puro (sem SDK @google/genai), batchEmbedContents 20/lote + 2s, taskType RETRIEVAL_DOCUMENT (busca futura usa RETRIEVAL_QUERY), idempotente por embedding IS NULL, vetor como string literal pgvector | Uma só convenção de acesso ao Gemini; retomável sem estado externo |
| ~29/Jul | migration repair 20260722 (marcada applied após confirmar colunas+GRANT vivos) | Efeito já existia; drift era só de histórico |
| ~29/Jul | Seeds idempotentes com verificação de duplicata por nome | Tabela não estava vazia como a spec presumia; evitar catálogo duplicado |
| 30/Jul | Consolidação em v6.0 no marco pós-F10-backend | Múltiplos adendos + ~20 relatórios dispersos = risco de perda |

## 11.5 Decisões do Adendo v5.2 e do Plano de Marketing (22/Jul)
| Decisão | Motivo |
|---|---|
| Widgets em 3 níveis (SQL direto / Cron / IA paga sob demanda) | Dezenas de widgets sem explodir custo |
| Nível 3 exclusivo do painel profissional | Blindagem ANVISA |
| Nível 3 por crédito/execução; resultado permanente | 3ª linha de receita |
| Dashboards via catálogo central (não hardcoded) | Novo widget = nova linha |
| Widget do profissional = nome+período; clique → lista de pacientes | Acompanhamento ativo como diferencial |
| Nível 1 na Onda 4; 2/3 pós-validação | Construir sob demanda comprovada |
| Marketing 100% orgânico; 60% B2B / 30% B2C / 10% PR | Custo zero real; B2B é o coração |
| Assessorias de corrida como canal-âncora B2B | 1 fechamento = 1 Performance + dezenas de alunos Garmin |
| Identidade de marca = Design System da Parte 8 (sem agência) | Coerência produto-marketing |
| Waitlist viral na própria stack (Cloudflare + Supabase) | Custo zero; reusa indicação |
| Lançamento público condicionado a F10 + parecer + CNPJ + marca | Gatilhos registrados |
| Naming com filtros INPI/domínio/handles/sem termo clínico | Risco ANVISA no nome |
| Restrições legais de marketing como bloqueadores de peça | Coerência regulatória |

---

# PARTE 12 — RISCOS CARREGADOS (ACOMPANHAR)

- **R1 (alto):** view `perfis_pacientes_vinculados` sem security_invoker → WHERE é a única barreira. Prioridade S9 + 7º cenário de teste de isolamento.
- **R3 (médio):** trial por `created_at` penaliza quem demora a ativar → avaliar "primeira ativação significativa".
- **R4 (médio):** em produção, backfill de legado nasce pendente (o de teste nasceu ativo).
- **R5 (médio):** F42 sem spec formal (critério CRM/CRN, fluxo de rejeição, quem aprova).
- **R6 (alto/rápido):** Service Role Key viva no .env local do painel (scripts de seed/embeddings a usam) → rotacionar (S8) e definir manuseio (arquivo fora do git já; rotação pendente).
- **R8 (bloqueador de produto, reduzido):** F10 backend pronto; bloqueador atual = tela de confirmação do prato + persistência (F34). Sem eles, o "uau" não fecha.
- **R9 (médio, novo):** schema drift recorrente entre git e banco (is_admin/status_aprovacao fora de migração; 20260722 sem histórico; extract-metric-photo que só existia em branch) → política: `db pull/diff` ao detectar; nunca conviver com drift.
- **R10 (médio, novo):** applicationId/namespace `com.example.*` — trocar por id definitivo (depende do naming) ANTES de qualquer build de loja.
- **R11 (baixo, novo):** dívida Built-in Kotlin (4 plugins) — versões futuras do Flutter recusarão o modo antigo; plano de migração registrado na Parte 9.5.
- **R12 (baixo, novo):** projeto Supabase free tier pode ser pausado por inatividade — se o app "travar", checar o painel antes de suspeitar de código.
- **R13 (médio, novo):** colunas `idade`/`peso_kg` criadas como número simples × pedido de 24/Jul de **data de nascimento** (idade envelhece; data não). Decidir migração (data_nascimento já existe para outro propósito — reconciliar) antes de dado real.
- **R14 (médio, novo):** cadastro social (Google/Apple) não coleta perfil/papéis — usuário cai em ProfileSelectionPage sem eh_profissional definido; fluxo profissional via social inexistente.
- **R15 (médio, novo):** GEMINI_API_KEY duplicada em secret + .env local (semeadeira) — mesma chave em dois lugares; incluir na rotação/manuseio do R6.
- **R-E4 (alto, ampliado):** separação homolog×produção ainda não materializada (um projeto só, chamado das duas formas nos relatórios) — criar prod separado + checklist de paridade ANTES de dado real.
- **F15:** seed sem exames/anomalias — limita a demonstração B2B (abas Exames/Insights vazias).

---

*Fim do Documento Mestre v6.0. Para continuidade: cole este v6.0 (+ o Plano de Marketing v1.0 quando o assunto for marca/lançamento) em qualquer nova sessão. Evolução por adendo/log; próxima consolidação (v7.0) no próximo marco — sugerido: fim da rodada de teste fake do app.*
