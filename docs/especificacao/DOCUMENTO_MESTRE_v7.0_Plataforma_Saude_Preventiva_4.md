# DOCUMENTO MESTRE v7.0 — PLATAFORMA DE SAÚDE PREVENTIVA COM IA
## Ecossistema Unificado B2C/B2B (Single-Backend / Multi-App) — Marco: Nutrição v1.0

**Data:** 7 de Agosto de 2026
**Status:** FONTE ÚNICA DE VERDADE E AUTOSSUFICIENTE. Consolida e substitui integralmente o DOCUMENTO MESTRE v6.0 e o ADENDO v6.1, incorporando as decisões da rodada de consultoria estratégica de 07/Ago/2026 (frente Nutrição v1.0). Qualquer IA que receba este arquivo deve conseguir assumir o projeto sem contexto adicional.
**Precedência:** v7.0 > v6.1 > v6.0 > anteriores.
**Documento-anexo vigente (NÃO substituído, NÃO revisado neste marco):** PLANO DE MARCA, MARKETING E LANÇAMENTO v1.0 (22/Jul/2026). Em produto/técnica, este Mestre prevalece; em marketing, o Plano prevalece. *Pendência conhecida, fora deste marco:* o Plano trata o motor viral (F43) como "já construído" — ele NÃO está; ajustar na próxima revisão do Plano.
**Documentos históricos (apenas consulta — NÃO usar para execução):** Mestre v3.0/v5.0/v6.0; Adendos v4.0/v5.1/v5.2/v6.1; logs de execução até 01/Ago/2026.

---

# PARTE 0 — INSTRUÇÕES DE OPERAÇÃO PARA O ASSISTENTE DE IA

Se você é uma IA recebendo este documento, siga em ordem de precedência:

1. **NUNCA implemente, expanda ou corrija** itens EM HOLD (Parte 4 e Parte BL).
2. **Antes de escrever código novo**, verifique o estado real (Parte 2) e a Matriz (Parte 3), e **investigue o código real antes de presumir** — specs de tarefa frequentemente presumem errado (arquivos/tabelas que já existem; bugs com outra causa). Padrão comprovado: auditar → reportar o achado → agir. "Declarado-implementado" ≠ verificado por humano até auditar.
3. **Segurança (Parte 6) é bloqueador de release.**
4. **UX (Parte 8) prevalece** sobre qualquer default visual.
5. **Arquitetura inegociável:** toda lógica sensível (pontos, streaks, scores, elegibilidade, trial, prescrição, criação de vínculos, cálculo metabólico, validação de leituras de OCR) é **server-side**. O cliente apenas exibe.
6. **Dados inegociável:** nenhum dado real de usuário em IA de tier gratuito ou com cláusula de treinamento. Zero mídia persistida (pipeline RAM volátil).
7. **Git:** proibido force push; main protegida; PRs obrigatórios; zero segredos/chaves/IDs em código; stacked branches.
8. **Perfil do fundador:** não-desenvolvedor, solo, IA para 100% do código. Explicar em linguagem simples, uma tarefa por vez, sempre dizer como testar.
9. **Ferramenta de execução:** Claude Code (Parte 10 traz política de modelos e template de prompt).
10. **Toda migração** = RLS habilitado + policy vinculada a `auth.uid()`/vínculo + **GRANT explícito** para `authenticated` (e `service_role` quando um processo servidor precisar de DML).
11. **Idioma:** pt-BR. i18n em pt/en/es (pt é a fonte).
12. **Não gerar novos documentos** exceto quando o fundador pedir ("consolida"/"gera"). Evolução por adendo/log; consolidação em marcos.
13. **Relatório de fim de tarefa obrigatório** (ver 17): decisões de infra/config/arquitetura; entidades novas; desvios da spec; pendências e riscos.
14. **"Validação = completa funcionalmente, crua visualmente":** tela de validação é feia, não capenga. Nenhum agente interpreta "validação" como licença para omitir funcionalidade.
15. **Erro de app nunca se disfarça de erro de servidor:** em homolog/debug, exibir a classe/mensagem real (sem dado sensível); genéricas ("servidor ocupado") só para erros de rede/HTTP reais.
16. **Anti-hardcode (reforçado, 07/Ago):** valores que mudam comportamento **nunca** ficam fixos no código. Vêm de secret ou tabela configurável. Casos vigentes: nome do modelo Gemini (`GEMINI_MODEL_NAME`) **e do modelo de embedding** (`EMBEDDING_MODEL_NAME`); threshold da busca semântica; faixas de validação; lista de papéis; ordem de confiabilidade das fontes de alimento; peso típico por alimento (vai para tabela, não no código da função).
17. **Governança de log de desenvolvimento (07/Ago):** ao fim de cada tarefa, o Claude Code grava um log de máquina em `/docs/log_dev/AAAAMMDD_SSSS.md` (SSSS = sequência de 4 dígitos por dia, reiniciada diariamente; o agente lê o último número do dia antes de gravar), com cabeçalho fixo (`data, seq, tarefa, branch, merge_sugerido, status`) e seções (Resumo · Entregue · Decisões técnicas|motivo · Desvios da spec · **Problemas encontrados** · **Riscos mapeados** · Como testar · Como tratou performance · Estado das branches). Mantém também `/docs/log_dev/INDICE.md` append-only (uma linha por tarefa). **Regra anti-alucinação:** o log registra só o que foi feito **e verificado**; `pronto-para-teste` ≠ `testado`. O relatório humano longo continua no fim do output do prompt; o log de máquina é para o Gemini e o consultor lerem barato.
18. **Avaliação de merge ao fim de cada bloco:** o Claude Code avalia o estado das branches (o que está pronto, dependências, ordem de merge) e **sugere** o merge quando seguro — **nunca mescla na main sem autorização explícita** do fundador.
19. **Sincronização dos 3 prompts:** toda alteração de comportamento/prioridade exige revisão sincronizada dos três artefatos de prompt (consultor, Gemini, Claude Code) na mesma sessão — evita deriva entre prompts (mesma classe do schema drift, R9).
20. **Modelo de embedding:** o seed de embeddings e a busca em runtime usam **o mesmo** modelo (vindo de secret). Trocar o modelo obriga a re-semear; vetores de modelos diferentes não são comparáveis.
21. **Performance como critério de GERAÇÃO (não só de correção):** o código nasce com atenção a custo/latência — evitar busca linear onde cabe índice/`Map`, não repetir trabalho dentro de laços, paginar/limitar consultas, cuidar do caminho quente (loops, I/O, chamadas de IA). **Precedente real (Parte 12):** a leitura de alimento por imagem precisou de correção de performance *depois* de pronta (busca O(n) em ~8.000 itens + normalização repetida por comparação) — a regra é prevenir na geração, não remediar. Toda tarefa com laço sobre volume, consulta a tabela grande ou pipeline de IA deve declarar no relatório de fim de tarefa como tratou performance.

---

# PARTE 1 — VISÃO DE NEGÓCIO E ESTRATÉGIA

## 1.1 Problema
Fragmentação das healthtechs (apps isolados de calorias, prontuário ou wearable), baixa retenção crônica de diários manuais, perda do histórico clínico de longo prazo pelo paciente.

## 1.2 Solução
Backend único (Supabase) + múltiplas interfaces por nicho: **App Atleta** (B2C gamificado), **App Guardião Clínico** (B2C sênior/crônico/feminino), **Painel Web B2B** (nutricionistas, treinadores, médicos). Um único app mobile de paciente com perfil dinâmico (`perfil_uso`); Guardião separável no futuro (decisão de marketing, não de engenharia).

## 1.3 Decisão estratégica central
**O B2B (profissionais) é o coração comercial.** O B2C é engajamento e canal de aquisição, não a aposta principal de receita — B2B é identificável e previsível; B2C viral é loteria estatística.

## 1.4 Beachhead
**Marketing** mira nutricionistas esportivos + treinadores de corrida e seus pacientes com Garmin. **Beachhead de marketing, leque técnico aberto:** a tecnologia atinge do smartwatch de R$ 200 ao Apple Watch — restringe-se a mensagem de entrada, não o produto.

## 1.5 Mercado
Global de apps saúde/fitness US$ 13,8–14,6 bi → > US$ 33 bi (CAGR > 13,5%). Validadores: Cal AI, Whoop, Strava, MyFitnessPal. Categoria "exames+wearables+nutrição" já validada nos EUA (InsideTracker, Function Health, Superpower). **Distinção regulatória crítica:** esses players são testadores (CLIA/FDA); nós **não** — o usuário já possui o exame, nós lemos/organizamos. Somos **organizador de dados que o usuário já possui** (base da blindagem SaMD, Parte 5).

## 1.6 Fosso defensável (combinação que nenhum player reúne)
(1) Brasil-first (PDF de labs locais, idioma, preço, TACO); (2) telemetria contínua de wearables cruzada a exames e nutrição; (3) motor de retenção gamificado; (4) captura por foto de aparelhos analógicos (glicosímetro/pressão do sênior); (5) loop completo profissional→prescrição→relógio Garmin; (6) base longitudinal que aumenta de valor e custo de troca com o tempo.

## 1.7 Concorrência atualizada (07/Ago/2026) — o fosso estreitou; saber disso é vantagem
A régua subiu desde o v6. Concorrentes brasileiros atuais já entregam parte do que era diferencial:
- **VibeFit** — ecossistema personal + nutricionista (treino, nutrição, hábitos, desafios, visão compartilhada; grátis até 3 alunos; múltiplas bases alimentares). É o concorrente mais próximo da tese B2B.
- **Health Compass** — análise de risco, adesão, fadiga e **identificação precoce de abandono** com relatórios automáticos (o "card de paciente sumindo" já existe no mercado).
- **Nutrio** — lê PDF de exame com IA e transcreve a consulta extraindo hábitos/metas.
- **DietSystem** (R$ 79,90/mês) e **SimpleDiet** (R$ 27,90/mês) — extração de exames/PDF por IA.
- **AIA Longeva, Longevital, Viva Longevidade (Bradesco)** — paisagem de longevidade a monitorar.
**O que permanece nosso (verificado):** a **telemetria contínua do wearable dentro do painel** cruzada à nutrição (nos concorrentes vive no app do relógio, separado); a captura por foto de aparelho analógico; e a retenção gamificada no lado do paciente. **Implicação de produto:** "gerar valor a mais" não é ter mais gráficos — é o **cruzamento telemetria×nutrição** e o loop Garmin. Por isso ele foi puxado para a v1.0 (ver Parte V1), à frente do roadmap original.

## 1.8 Lacunas não-técnicas
Análise de CAC (orgânico-primeiro; pago só se orgânico estagnar após 3 meses); resposta competitiva (Samsung/Google podem embutir foto grátis — fosso real = base longitudinal + B2B); validação primária (20 nutricionistas + 20 usuários antes do lançamento público).

## 1.9 Unit economics
B2C anual R$ 179,90 ≈ R$ 142 líquidos/ano (loja 15% + imposto 6%). **Teto de CAC = R$ 142; meta ≤ R$ 47.** B2B margem > 80% (IA R$ 0,30–0,60/carteira/mês). Premissas: conversão trial→pago 1–2,5%; retenção D30 de mercado 5–10%. **"Custo mínimo controlado"**, não "custo zero". Terceira linha (v5.2): créditos de Análise Complexa Nível 3.

## 1.10 Custos reais reconhecidos
Gemini API paga (~R$ 0,012/usuário/mês, 1º real); Supabase Pro (~US$ 25/mês, 1º real); Play Console (US$ 25 único, agora); Apple Developer (US$ 99/ano, beta iOS); CNPJ + contador (R$ 200–400/mês, gatilho); parecer ANVISA/LGPD (R$ 5–15 mil, antes do lançamento); revisão de segurança sênior (R$ 2–5 mil, antes do lançamento); domínio (~R$ 40/ano); marca INPI (~R$ 142–355).

## 1.11 Situação jurídico-fiscal
Operação em CPF na fase de teste/primeiras vendas (carnê-leão). **MEI não permitido** → ME/Simples. Responsabilidade ilimitada no CPF → **gatilho de CNPJ (50 assinantes OU campanha pública) é mandatório.** LGPD aplica-se desde o 1º usuário real.

## 1.12 Preços
- **B2B Essencial** (sem Garmin, até 15 pacientes): R$ 97/mês. **B2B Performance** (com Garmin, até 40 pacientes): R$ 167/mês. **Fundadores:** 10–20 profissionais, vitalício ~R$ 67. Teto de slots ainda não implementado (ilimitado até existir faturamento — TODO no código).
- **B2C Anual (herói):** R$ 179,90/ano (~R$ 15/mês). **Mensal (âncora):** R$ 34,90/mês. Não lançar B2C com desconto; se precisar de tração, estender trial (21 dias).
- **Relação entre pagadores:** paciente via profissional **não paga** e **não recebe gatilho de venda**. Cobrança B2C só quando o próprio usuário opta. Múltiplos profissionais podem pagar pelo mesmo paciente (1 slot cada).
- **Terceira linha (créditos de Análise Complexa N3):** adicional aos pacotes; débito por execução; resultado gravado (releitura sem custo). Preço por crédito a definir.

## 1.13 Definição de cliente final (07/Ago) — governa permissão, cobrança e trava ANVISA
- **Cliente avulso:** usuário que comprou o app na loja, **sem vínculo** com profissional. Meta gerada pelo sistema no enquadramento de **bem-estar**; **edita a própria meta 1×/mês** (ou prazo escolhido, possível < 30 dias); sujeito à trava clínica (condição declarada → sistema não personaliza, orienta profissional). Relação comercial é com a loja.
- **Cliente profissional (cliente do profissional):** usuário **vinculado** a um profissional que prescreve. **Não edita a própria meta** (só o profissional). A relação comercial/mensalidade é com o profissional, não com a loja. Ao **desvincular**, passa automaticamente à regra do avulso (histórico preservado; se um dia revincular, o profissional vê todo o histórico).

---

# PARTE 2 — ESTADO REAL DO PROJETO (07/Ago/2026)

> **Por que esta Parte vem cedo e é a mais importante deste marco.** A consolidação do v6.0 passou a "afirmar como pronto" itens que não existiam, o que quase levou o ecossistema a reconstruir código existente e a testar em campo um núcleo que falharia em silêncio. Esta Parte separa, com honestidade, **o que está construído**, **o que o v6 afirmava errado** e **o que ainda não existe**. Regra herdada (Parte 0.2): "declarado-implementado" ≠ "verificado por humano" — só vira ✅ verdadeiro após auditoria no código real.

## 2.1 Legenda de status
- **[PRONTO/nv]** — construído e relatado por sessão anterior, **não verificado por humano** (rebuild/teste em campo pendente).
- **[PRONTO/testado]** — verificado pelo fundador.
- **[BRANCH]** — existe em branch, **não mesclado na main**.
- **[NÃO EXISTE]** — o v6 sugeria existir; **não existe**.
- **[CORRIGIR]** — existe, mas fere uma regra (ex.: hardcode) e precisa refação.

## 2.2 O que está efetivamente construído
**Pipeline de foto / nutrição (núcleo do F10):**
- Edge Function `extract-metric-photo` ACTIVE, endpoint único diferenciado pelo header `X-Tipo-Aparelho`; tubulação Zero Storage (RAM volátil) validada no celular. **[PRONTO/testado]**
- Glicosímetro com gate determinístico (20–600 mg/dL, confiança ≥0,70, HTTP 422 se ilegível). **[PRONTO/testado]**
- Prato → TACO com cálculo determinístico ("IA traduz, backend calcula"). **[PRONTO/nv]**
- Tela de confirmação do prato (`confirmacao_prato_page`) com "IA estima + usuário edita", edição de peso, recálculo de macros, aviso honesto de estimativa. **[BRANCH]** `feature/f10-step3-meal-confirmation`
- Correção do cálculo de alimentos órfãos: peso típico (~50 alimentos), suporte a líquidos (ml + tamanho de copo), aviso seletivo. Deployado na Edge Function. **[PRONTO/nv]** — porém as tabelas de peso típico/líquidos estão **hardcoded no código da função**. **[CORRIGIR]**

**Persistência:**
- Tabela `coleta_diaria` (F34) + repositório + método de confirmação. **[BRANCH]** `feature/f34-coleta-diaria-persistence` (depende do F10 Passo 3)
- Migração da criptografia de PII para server-side em repouso (D2), via pgcrypto + Vault. **[BRANCH]** `d2-pii-criptada` (depende do F34)

**Fundação Android / Auth / painel:**
- `applicationId` migrado de `com.example.*` para `br.com.atleta.app` (R10); estrutura Kotlin realinhada; APK debug compila. **[PRONTO/nv]** — *nota:* "atleta" reflete o nome antigo; pode mudar quando o naming for decidido.
- Chaves (Service Role, Gemini) **removidas do `.env` do repositório** para `.env.local` (R6/R15). **[PRONTO/nv]** — **rotação/backup ainda não ritualizados.**
- Recuperação de senha ponta a ponta (web + app). **[PRONTO/nv]** — teste físico do deep link pendente.
- Painel web B2B: sidebar corrigida, convite por e-mail, admin, sala de espera. **[PRONTO/nv]**
- App: roteador enxuto (5 rotas), cadastro dinâmico validado no aparelho, Health Connect READ-only (FC validada; Peso pendente de teste físico F48). **[PRONTO parcial]**
- `alimentos_referencia` (~8.000 itens) + busca léxica determinística. **[PRONTO/nv]**

## 2.3 Correções de fatos — o que o v6 afirmava e a realidade (crítico)
| # | O v6 afirmava | Realidade (fonte) | Consequência |
|---|---|---|---|
| C1 | Carga Inicial de 30 dias implantada | **[NÃO EXISTE]** (confirmado pelo fundador) | A Retrospectiva do dia 1 e o cruzamento dependem dela → vira requisito da v1.0 |
| C2 | Health Connect READ validado (Peso pendente) | Lê, mas **NENHUMA gravação** — a leitura foi só teste; o diálogo não persiste (confirmado pelo fundador) | Persistência da telemetria vira requisito da v1.0 |
| C3 | Rodar semeadeira de embeddings (F46) — feito | Semeados **23 alimentos com embedding MOCK** (vetor falso por hash MD5, chave sem permissão na época); runtime depois passou a usar `gemini-embedding-001` real; modelo trocado 4× (relatórios 30/Jul e 01/Ago) | **Busca semântica provavelmente quebrada** (vetores falsos × consulta real). Re-semear TUDO com o modelo real, sobrescrevendo os 23, + travar em secret → requisito crítico da v1.0 |
| C4 | F10 Passo 3 = "bloqueador atual / próxima tarefa" | **Já construído**, em branch | O "bloqueador" registrado já foi feito; risco de mandar reconstruir |
| C5 | F34 `coleta_diaria` pendente | **Criada e aplicada**, em branch | Reusar, não reconstruir |
| C6 | Papéis: modelo booleano (`eh_profissional` + `tipo_profissional` + `is_admin`) | Insuficiente para "um usuário, vários papéis" | **Decisão v7.0:** migrar para `usuario_perfis` (M:N) — ver Parte V1 |
| C7 | Peso típico corrige o cálculo | Corrige, mas **hardcoded na Edge Function** | Fere a regra anti-hardcode → mover para `alimentos_referencia`/tabela de config |
| C8 | (Bloco 2, 30/Jul) população 19–65 | Contradiz o backend (Mifflin vale ≥18 incl. idosos) e a marca (sênior) | **Corrigido:** ≥18 incluindo idosos; excluir crianças/adolescentes/gestantes/lactantes |

## 2.4 Estado de merge (pilha de branches)
Três branches empilhadas, **nenhuma mesclada**, ordem obrigatória:
`feature/f10-step3-meal-confirmation` → `feature/f34-coleta-diaria-persistence` → `d2-pii-criptada`.
Mesclar fora de ordem quebra. Além delas: `chore/r10-r6-r15-build-prep` (commit `ba6ecf5`).
**Observação de ambiente:** mudanças de Edge Function foram **deployadas direto** no projeto Supabase (não via merge), enquanto o cliente que as consome está em branch — e o projeto é **único** (homolog = produção). Ver R-E4 (Parte 12).

## 2.5 O que NÃO existe ainda (e o v6 não deixava claro)
- Carga Inicial de 30 dias (C1).
- Persistência diária da telemetria em `metricas_saude_diarias` (C2).
- Tela de consulta da telemetria/histórico no app.
- Busca semântica funcional de verdade (C3).
- Modelo de papéis M:N (C6).
- Motor viral / gamificação (F43) — o Plano de Marketing o supõe pronto; **não está**.
- Ambiente de produção separado do de homolog (R-E4).

## 2.6 O que foi testado pelo fundador vs. não
- **Testado:** pipeline Zero Storage no celular; gate do glicosímetro; leitura (não gravação) do Health Connect (FC).
- **NÃO testado em aparelho:** todo o fluxo de registro de refeição (a tela do prato existia em branch, mas o app "não tinha as chamadas" — sem persistência não havia o que testar); recuperação de senha (deep link físico); Peso via Health Connect (F48).

> **Conclusão da Parte 2.** O núcleo de captura existe e é bom; a lacuna real da v1.0 está em **persistir** (telemetria + diário), **reconciliar** (mesclar a pilha, re-semear embeddings, tirar hardcode) e **construir o que faltou** (Carga Inicial, dashboards, cruzamento, papéis M:N, telas de manutenção). A especificação executável está na **Parte V1**; o que foi adiado, na **Parte BL**.

---

# PARTE 3 — ARQUITETURA TÉCNICA E MATRIZ DE STATUS

## 3.1 Stack
- **Backend:** Supabase (PostgreSQL + Auth + Edge Functions Deno/TS + Cron). RLS em todas as tabelas + GRANT explícito. Extensão **pgvector** (schema `extensions`).
- **Mobile:** Flutter (Feature-First), i18n pt/en/es. UI dinâmica por `perfil_uso` sem reinício. Roteador enxuto (5 rotas): login, cadastro, profile-selection, home (`MainNavigationPage`), definir-nova-senha (só via redirect). Telas secundárias via `Navigator.push`.
- **Web B2B:** React + TypeScript + Vite, code splitting, Cloudflare Pages. Sidebar/DashboardLayout responsivo com render condicional por papel.
- **IA:** Google Gemini via **API paga**, só pelo servidor. Família 2.5 DEPRECADA. Nome do modelo SEMPRE via secret `GEMINI_MODEL_NAME` (vigente `gemini-3.1-flash-lite`); **modelo de embedding via secret `EMBEDDING_MODEL_NAME`** (seed e runtime no mesmo modelo — regra 20). Nunca fixar modelo em código. Chaves só em secrets do servidor.
- **Wearables:** leitura LOCAL via pacote `health` (Health Connect/HealthKit), **estritamente READ-only**. Sync oportunista + background 1×/dia (WorkManager). Carga inicial 30 dias (**a construir** — Parte 2 C1).
- **Garmin:** Edge Function `garmin-gateway/` (OAuth 1.0a HMAC-SHA1) server-to-server. Tokens em `garmin_conexoes`.

## 3.2 Legenda de status
✅ Declarado-implementado (não verificado por humano) · 🔍 Verificado pelo fundador · ⚠️ Parcial/desconectado · 🔲 Pendente · ⛔ Em Hold · 🔀 Em branch (não mesclado)
**Precedência:** onde esta matriz conflitar com a Parte 2 (Estado Real), **a Parte 2 prevalece** (ela é mais recente e auditada).

## 3.3 Matriz de status (reconciliada 07/Ago/2026)
| # | Funcionalidade | Status | Nota |
|---|---|---|---|
| F01 | Esquema de dados + RLS | 🔍 | RLS em 6 cenários; schema B2B em git |
| F02 | Caixa Preta (`eventos_anomalias_saude`) | ⚠️ | Tabela existe; detecção pendente |
| F03 | Login social + OTP | ⚠️ | OAuth existe; cadastro social não grava perfil (R14) — resolver na v1.0 (papel na entrada) |
| F04 | Keystore/biometria | ⚠️ | Tokens ok; biometria de abertura não habilitada (backlog) |
| F05 | Suíte de testes de segurança | ⚠️ | Revisar cobertura |
| F06 | Cadastro adaptativo BR + Dinâmico | ✅ | Validado em aparelho. **v1.0:** data de nascimento (R13), telefone WhatsApp/DDI, e-mail de confirmação → entram; endereço → BL |
| F07 | Sync wearables | ⚠️ | READ testado (FC); **NÃO grava** (Parte 2 C2). Persistência = requisito v1.0 |
| F08 | Dashboard modular | ✅ | MainNavigationPage religada |
| F09 | Esteira 14 dias + Projeção | ⚠️🔲 | Backend `calculate-recovery-mode` existe, mas **não testado nem visualizado pelo fundador** (correção 07/Ago). É a "cenoura do dia 7/14" |
| F10 | Gateway Gemini + Zero Storage | ⚠️🔀 | Passos 1-2 PRONTOS; Passo 3 (tela do prato) 🔀 em branch (Parte 2 C4). Peso típico corrige cálculo mas hardcoded (C7) |
| F11 | Painel React B2B | ✅ | Convite, sala de espera, sidebar, PatientList por vínculos |
| F12 | Filtragem seguradoras | ⛔ | HOLD |
| F13 | Garmin Gateway | ✅ | Depende de aprovação Garmin; mock |
| F14 | Motor de sinistralidade | ⛔ | HOLD |
| F15 | Seed de dados | ✅ parcial | 10 pacientes + métricas; falta exames EAV + anomalias (BL) |
| F16 | Exportação PDF+CSV (LGPD) | 🔲 | BL (Onda 2; loop viral B2B) |
| F17 | Alerta de Tendência não-clínico | 🔲 | BL (Onda 2/3) |
| F18 | Widget streak+anel | 🔲 | BL (gamificação) |
| F19 | Válvula anti-culpa alimentar | 🔲 | BL (Onda 2) |
| F20 | Modo Cuidador/Familiar | 🔲 | BL (Onda 3) |
| F21 | Modo Recuperação Humano | ⚠️ | BL |
| F22 | Registro de medicamentos | ⚠️ | **BL** (decisão 07/Ago: fora da v1.0 de nutrição) |
| F23 | Relatórios sazonais macro | 🔲 | BL (Onda 3) |
| F24 | Revogação de acesso do profissional | ⚠️ | Via vínculo; auditar |
| F25 | 2FA no painel profissional | 🔲 | BL (Onda 4, bloqueador Fase 2) |
| F26 | Prescrição ativa (cardápio+treino) | 🔲 | **Nutrição: cardápio/meta entra na v1.0** (Parte V1 F); treino → BL |
| F27 | Deep linking WhatsApp | 🔲 | BL (Onda 4) |
| F28 | `logs_acesso` append-only | 🔲 | BL (criar schema já; popular Fase 2) |
| F29 | Segurança S1–S9 | 🔲 | Bloqueadores de release (Parte 6) |
| F30 | Telas no design system | 🔲 | Acabamento pós-validação (camadas, Parte 8) |
| F31 | Índice de Bem-Estar | 🔲 | BL |
| F32 | `marcadores_referencia` | ✅ | 34 marcadores i18n |
| F33 | `resultados_exames` EAV | ✅ | Na main |
| F34 | `coleta_diaria` | ✅🔀 | Criada, **em branch** (Parte 2 C5) |
| F35 | Alta freq. + FIFO 3 dias | 🔲 | BL |
| F36 | `vinculos_profissional_paciente` | ✅ | Motor completo; sem teto de slots |
| F37 | Consentimento por vínculo | ⚠️ | Aceite BINÁRIO com UI; granularidade = BL (F37-fase2). **v1.0: consentimento é bloqueador jurídico** |
| F38 | Liga por profissional + desafios | 🔲 | BL (gamificação) |
| F39 | Mensagens de ciclo do vínculo | 🔲 | BL (i18n) |
| F40 | Paywall por pagador | 🔲 | BL |
| F41 | "Acesso ativo" no login/refresh | 🔲 | BL |
| F42 | Onboarding/aprovação de profissional | ⚠️ | Sala de espera + trigger anti-autopromoção OK. **v1.0:** spec de aprovação + CRN/CRM/CREF (Parte V1 A) |
| F43 | Motor viral / gamificação | 🔲 | **BL — Bloco 5** (entre teste solo e beta). *Marketing supõe pronto: NÃO está* |
| F44 | Ciclo menstrual/menopausa | 🔲 | BL (Onda 3; opt-in) |
| F45 | `alimentos_referencia` (TACO/USDA) | ✅ | ~8.000 na base. **v1.0:** novas colunas + carga TACO completa (Parte V1 B/H) |
| F46 | Nutrição semântica (pgvector) | ⚠️ | **Embeddings MOCK, 23 alimentos (Parte 2 C3)** → re-semear TUDO com modelo real + índice = requisito crítico v1.0 |
| F47 | Recuperação de senha | ✅ | Web+app; teste físico do deep link pendente |
| F48 | Leituras dedicadas Health Connect | ✅ | FC 🔍; Peso teste físico pendente |
| F49 | Diagnóstico de coleta | 🔲 | BL |
| F50 | Widget único de câmera | 🔲 | BL |
| F51 | Dashboards configuráveis 3 níveis | 🔲 | **Nível 1 puxado para a v1.0** (Parte V1 L), à frente do roadmap (Onda 4); N2/N3 = BL |

### 3.3.1 Itens NOVOS da Nutrição v1.0 (decididos 07/Ago — detalhe na Parte V1)
Códigos `N##` = funcionalidades que **não existiam** no v6 e entram na v1.0. Índice único; o detalhe executável e o critério de aceite estão na Parte V1 (letra indicada).

| # | Item | Parte V1 | Nota |
|---|---|---|---|
| N01 | Papéis M:N (`usuario_perfis`) + admin único via banco (bootstrap; constraint) | A | Migração definitiva; sem hardcode de e-mail |
| N02 | Aprovação de profissional pelo admin + CRN/CRM/CREF | A | Fila/card; sem número não prescreve |
| N03 | Data de nascimento derivando idade + refação de telas | A | R13 deixa de ser backlog |
| N04 | Consentimento de vínculo profissional↔paciente | A | **Bloqueador jurídico** (LGPD/F37) |
| N05 | Campos de cadastro: telefone WhatsApp/DDI + e-mail de confirmação | A | Endereço → BL |
| N06 | Telas de manutenção no painel (usuário, profissional, prof×usuário, atividades físicas, alergias, alimentos, configurações) | B | Via RPC de decifra (D2) |
| N07 | Motor Metabólico (fatia): Mifflin + Katch/Cunningham (só c/ massa magra) + PAL/decomposto + macros | C | Anti-double-count do TEF |
| N08 | Motor de Exceções (fatia): gates + trava clínica ANVISA + faixas (alerta, não bloqueio) | D | População ≥18 incl. idosos |
| N09 | Anamnese nutricional (self-service + profissional, versionada) | E | Alimenta o cálculo |
| N10 | Objetivo alimentar do profissional (metas, único/por dia, vencimento+7 dias, cards, copiar último, histórico) | F | FC-001/FC-002 + versionamento |
| N11 | Meta do usuário sem acompanhamento (bem-estar, 1×/mês) | G | Trava ANVISA |
| N12 | Registro de refeição completo (foto/texto/favoritas; medida caseira; editar unidade+qtd; card consumo×meta) | H | Evolui a tela existente |
| N13 | Favoritas por tipo + manutenção no perfil | H | Salva com medida customizada |
| N14 | Peso típico: mover de hardcode → tabela `alimentos_referencia` | H | Correção C7 |
| N15 | Persistência de aparelho por foto (glicosímetro/pressão/balança → `coleta_diaria`) | I | Sem interpretação clínica ao avulso |
| N16 | **Hidratação:** registro em ml/copo (padrão 200 ml, configurável) + histórico diário + widget | I | Entra nas análises |
| N17 | Persistência diária da telemetria (upsert idempotente em `metricas_saude_diarias`) | J | Não existe (C2) |
| N18 | Carga Inicial de 30 dias | J | Não existe (C1); habilita retrospectiva |
| N19 | Tela de consulta da telemetria/histórico no app | J | Não existe |
| N20 | Re-seed de embeddings com modelo REAL (sobrescrever os 23 mock) + índice vetorial + secret | K | Correção crítica C3 |
| N21 | Dashboards v1.0 (usuário bem-estar / paciente acompanhado / profissional) via `catalogo_widgets` | L | Reusa motor existente |
| N22 | **Cruzamento telemetria×nutrição** (saldo energético + linha do tempo — Versão A) | L | Diferencial pesado; à frente do roadmap |
| N23 | Resumo semanal/mensal no app do usuário | L | Simples na v1.0; relatório rico/sazonal (F23) → BL |
| N24 | Onboarding "valor antes de fricção" (30s, progressive profiling) | M | Reordena telas existentes |
| N25 | Governança de log `/docs/log_dev` + índice + avaliação de merge | Parte 10 | Regras 17/18 |
| N26 | Merge da pilha F10→F34→D2 (em ordem) | Parte 9 Fase 0 | Desbloqueio inicial |

## 3.4 Entidades de banco (schema real + alterações da v1.0)
**Existentes (herdadas do v6):** `perfis_usuarios` (PII cifrada — D2), `anonymous_users.profile_data` (`perfil_uso`), `garmin_conexoes`, trial/assinatura, `vinculos_profissional_paciente`, `marcadores_referencia`, `resultados_exames` (EAV), `metricas_saude_diarias` (colunas fixas, 1 linha/usuário/dia), `eventos_anomalias_saude` (append-only), `alimentos_referencia` (macros/100g, `fonte`, `embedding vector(768)`), `alimentos_medidas_caseiras`, `cache_sinonimos_alimentos`.
**Views:** `perfis_pacientes_vinculados` (SEM `security_invoker` — R1), `perfis_profissionais_vinculados`.
**Funções:** `resolver_usuario_id_por_email` (SECURITY DEFINER, service_role).
**Edge Functions ACTIVE:** `extract-metric-photo` (F10), `manage-professional-link`, `calculate-recovery-mode`, `search-food` (F46, deployada).

**Alterações e NOVAS tabelas da v1.0 (detalhe na Parte V1):**
- `usuario_perfis` **(NOVA, M:N)** — `usuario_id`, `papel`, `status`, `data_concessao`, `concedido_por`. Substitui os booleanos `eh_profissional`/`tipo_profissional`/`is_admin` de `perfis_usuarios` (migração definitiva). **Índice único parcial** garante **um único** `admin` ativo. Papéis vêm de tabela de referência (sem enum no código). Ativos na v1.0: nutri-prescreve, paciente, individual.
- `perfis_usuarios` — **`data_nascimento`** substitui `idade` (idade passa a ser derivada); admin deixa de ser `is_admin` booleano.
- `alimentos_referencia` — colunas revisadas: valores **por 100 pela unidade** (grama **ou** ml, sem "g" no nome), **`acucares_100`**, medida caseira (gramas/ml por medida), **`peso_tipico`** (recebe o que hoje é hardcoded na função — C7), flag **`revisao`** (sim/não).
- `atividades_fisicas` **(NOVA)** — nome, `gasto_kcal_30min_masc`, `gasto_kcal_30min_fem` (base 70 kg), `fonte`. (Fonte confiável a definir e carregar — Parte V1 B.)
- `alergias_alimentares` **(NOVA)** — nome, descrição, alimentos/ingredientes proibidos, `fonte`.
- `objetivos_alimentares` **(NOVA)** — `usuario_id`, `profissional_id` (nulo p/ avulso), tipo (único **ou** por dia da semana), metas por nutriente (kcal/carbo/proteína/gordura), `data_inicio`, `data_fim`, `ativo`, controle de vencimento/revalidação. Mesma tabela serve avulso e acompanhado (regra do `Adendo_Nutrição`).
- `anamnese_nutricional` **(NOVA, versionada)** — self-service e profissional; alimenta o cálculo metabólico.
- `coleta_diaria` (F34) — passa a receber também as leituras de aparelho por foto (glicose/pressão/peso) e a refeição confirmada.

## 3.5 Arquitetura de dados de saúde — modelo final (herdado)
- **G.1 `resultados_exames` — EAV** (pontual/laboratorial; normaliza unidade guardando original).
- **G.2 `coleta_diaria` — EAV** (frequente; device/OCR/manual; `origem` obrigatório, `confianca` do OCR).
- **G.3 `metricas_saude_diarias` — colunas fixas** (agregado de wearable; 1 linha/usuário/dia) — **alvo da persistência da telemetria da v1.0**.
- **G.4 Alta frequência bruta** — device + FIFO 3 dias; consolidação noturna; bruto nunca sobe.
- **G.5 `eventos_anomalias_saude`** — anomalia = desvio do baseline próprio, sem interpretação clínica.
- **G.6 Leitura pela IA** — resumos textuais curtos pré-consolidados pelo Cron; nunca tabelas brutas.
- **G.7 Pipeline nutricional "IA traduz, backend calcula"** — Gemini identifica alimentos em medidas caseiras + confiança (JSON); backend cruza com `alimentos_referencia` (léxico determinístico → semântico F46 para sinônimos); conversão medida→gramas→macros por regra de três sobre a TACO. Cálculo sempre determinístico e auditável.

## 3.6 Dashboards configuráveis (motor de geração — reusar, não reconstruir)
- **`catalogo_widgets`** (fonte de verdade de todo widget): `widget_codigo` PK, `escopo` (paciente/profissional), nomes i18n, `nivel` (1/2/3), `periodos_suportados`, `fonte_calculo`, `categoria`. **Novo widget = nova linha, não código novo.**
- **`configuracao_dashboard`**, **`resultados_analise_nivel2`** (cache Cron), **`analises_complexas_nivel3`** (pagas, nunca no app do paciente), **`creditos_profissional`**.
- **3 níveis:** N1 = SQL direto em tempo real (v1.0); N2 = Cron no fechamento (BL); N3 = IA sob demanda paga, só painel profissional (blindagem ANVISA).
- **Dashboard do profissional:** widget → clique → **lista de pacientes** (drill-down — diferencial contra Dietbox/Nutrium). **v1.0 usa este motor**, semeando só os widgets de bem-estar/nutrição + o cruzamento telemetria×nutrição (Parte V1 L). N2/N3 = BL.

---

# PARTE 4 — ITENS EM HOLD (PROIBIDO IMPLEMENTAR)

## 4.1 Score Atuarial / Sinistralidade para Seguradoras — ⛔ EM HOLD (F14, F12)
Congela: `sinistralidade_engine`, espelho TS, indicador "Redução de Sinistralidade", login de operadoras, venda/exibição de score a terceiros. Motivos: (1) políticas Health Connect/HealthKit proíbem uso atuarial → risco de banimento; (2) cálculo estava no cliente; (3) LGPD exige base legal + consentimento destacado + RIPD inexistentes. Retomada só sob TODAS as condições do v5.0 (redesenho sem dados de health stores + consentimento revogável com benefício ao titular + server-side auditado + parecer LGPD/SUSEP + verificação das lojas). Se encontrar o código: não expandir/corrigir/integrar; manter atrás de feature flag desligada.

## 4.2 Fora de escopo sem nova revisão
Chat aberto de IA sobre saúde; SDKs proprietários de wearables além dos agregadores nativos; feed social estilo Strava; expansão internacional antes do PMF no Brasil.

---

# PARTE 5 — BLINDAGEM JURÍDICA E REGULATÓRIA

## 5.1 LGPD
Dado de saúde = sensível (art. 11): consentimento específico/destacado; política de privacidade pública; direitos de exclusão e portabilidade (F16). **Pseudonimização ≠ anonimização** — nunca "anônimo" em termos/marketing. Ranking público só com N ≥ 30. Proibido dado real em IA de tier gratuito/com treinamento. Incidente: 3 dias úteis à ANPD (S7). RIPD antes do lançamento público. **Consentimento de vínculo:** vínculos nascem **pendentes**; aceite do paciente libera a RLS; UI com aviso explícito. Recuperação de senha com mensagem neutra anti-enumeração.

## 5.2 ANVISA (RDC 657/2022) — classificação pela FINALIDADE
- Regência: **RDC 657/2022** (em vigor desde 01/07/2022). O gatilho de SaMD é a **finalidade** (diagnóstico/tratamento/decisão clínica), não o tema. Software sem finalidade clínica é excluído. **A ANVISA avalia rotulagem E marketing** para determinar a finalidade real — marketing com claim clínico pode reclassificar o produto.
- Somos **organizador de dados que o usuário já possui**. App B2C não cruza exames com telemetria para predições clínicas individuais; correlações clínicas só no painel do profissional; Análises Nível 3 exclusivas do painel (nunca ao leigo).
- IA proibida de laudo/diagnóstico ao usuário. O pipeline "IA traduz, backend calcula" reforça o enquadramento.
- Gate determinístico de leituras (glicose 20–600 etc.): **não gravar > gravar errado** — rejeição por regra, nunca palavra final do LLM.
- **Regra de bem-estar × clínico (v1.0, decidida 07/Ago):** o caminho **sem acompanhamento** é só bem-estar (manter/perder/ganhar peso); o número é **estimativa editável** com disclaimer; **se o usuário declarar condição clínica, o sistema NÃO auto-calcula meta adaptada — orienta procurar profissional** (trava clínica, usando o Motor de Exceções). Toda carga clínica mora no **caminho profissional** (responsável técnico). Vocabulário sem claim: organizar, acompanhar, entender padrões, bem-estar.
- **Faixas de validação = alerta/confirmação, não rejeição automática** (para exceções clínicas) no caminho profissional; no caminho sem acompanhamento, gate duro.
- Parecer jurídico formal ANVISA/LGPD antes do lançamento público (continua sendo o gate; este documento serve para construir seguro e briefar o advogado, não o substitui).

## 5.3 Lojas e Health Connect
Play: Data Safety + **Declaração de Apps de Saúde do Health Connect** (revisão manual, semanas — protocolar JÁ). Internal Testing imediato (até 100 testadores); produção exige teste fechado de 14 dias. **Garmin Developer Program:** maior lead time — protocolar JÁ; sem aprovação, Training API via mock. `applicationId` = `br.com.atleta.app` (pode mudar com o naming).

## 5.4 Permissões de dados (minimização)
Pedir só o que uma feature visível usa. **Health Connect estritamente READ** (WRITE removido). Leituras pontuais pedem só o tipo necessário. Estados vazios tratados como esperados, não bug.

---

# PARTE 6 — REQUISITOS DE SEGURANÇA (BLOQUEADORES DE RELEASE)
Complementam TLS 1.3 + SSL pinning, Keystore/Keychain + biometria, RLS + GRANT e Zero Storage.
- **S1. Sessão server-side:** refresh com rotação; "Desconectar todos"; revogação <60s. Race condition do onAuthStateChange corrigida.
- **S2. Proteção de tela:** FLAG_SECURE nas rotas clínicas; gamificação permite screenshot.
- **S3. Root/jailbreak:** detectar, avisar sem bloquear, flag `dispositivo_comprometido`.
- **S4. Rate limiting + teto financeiro:** máx. 30 análises de imagem/dia/usuário; alerta de billing US$ 10/dia; circuit breaker. (Backlog: retry/backoff 503 do Gemini.)
- **S5. `logs_acesso` append-only:** criar já; popular na Fase 2.
- **S6. Backup testado:** ritual mensal de restauração em staging. **v1.0: inclui rotação/backup da chave do Vault (D2) — antes de abrir aos amigos.**
- **S7. Plano de resposta a incidente:** `INCIDENT_RESPONSE.md`.
- **S8. Higiene de repositório:** main protegida; PRs; varredura de segredos; zero chaves em código; Service Role sem `VITE_`. **Pendências: rotacionar Service Role Key (R6) e tratar duplicação da GEMINI_API_KEY (R15).**
- **S9. Revisão humana sênior antes do 1º release público:** RLS, tokens/biometria, pipeline RAM, e a view `perfis_pacientes_vinculados` sem `security_invoker` (R1).
- **Menor privilégio em Edge Functions** (extract-metric-photo só com anon key); **contas de teste segregadas**; artefatos de teste apagados ao fim; validação visual Playwright (web) + ADB (app).

---

# PARTE 7 — REGRAS DE NEGÓCIO

## 7.1 Gamificação e retenção (base) — **BL na v1.0 (Bloco 5)**
- **Streak diário:** Condição 1 (1 foto de refeição OU registro rápido até 2×/semana) + Condição 2 (treino Garmin OU 8.000 passos). Quebra zera a chama e −100 pts. Server-side.
- **Rankings:** ligas de amigos/cidade/estado/país; cache noturno; N≥30 para localidade pública.
- **Esteira 14 dias:** dia 1 carga de 30 dias; dias 1–6 missões; dia 7 desbloqueio; dia 14 conversão. (F09 não verificado — Parte 2.)
- **Novos pontos da nutrição (quando a gamificação for construída):** registro de refeição (mín. 3/dia), registro de peso (1/semana), revisão mensal do plano (só se houver modificação real). *Registrados aqui para não se perderem; implementação no Bloco 5.*

## 7.2 Autorrelato (regra de ouro)
Opt-in, toque único, recompensado, DESVINCULADO da ofensiva. Máx. 1 pergunta/dia rotativa.

## 7.3 Motor viral (F43) — **BL na v1.0; NÃO está construído** (o Plano de Marketing supõe que sim)
Três momentos (Retrospectiva de Boas-Vindas dia 1 — depende da Carga Inicial N18; Cartão da Primeira Semana dia 7; Retrospectiva Mensal) + pontos sociais (server-side, nunca alimentam a ofensiva) + loop B2B (PDF com marca+QR). Detalhamento integral preservado do v5.0. **A Retrospectiva de Boas-Vindas é insight do dia 1** (não gamificação) e cabe no passo de insights, mas depende da Carga Inicial.

## 7.4 Modelo multi-profissional
- **Duas portas:** via profissional (sem gatilho de venda) e individual (definições em 1.13).
- **Vínculo = unidade central:** criado só via `manage-professional-link` (sem RLS de INSERT = antifraude de slot); nasce pendente; aceite só pelo paciente; encerrar por qualquer lado com carência +30 dias. Teto de slots pendente (entra com faturamento).
- **Permissões (D3, detalhada na v1.0 — Parte V1 A):** **leitura uniforme** + **prescrição por papel** (treino=personal→Garmin; cardápio=nutricionista; médico vê tudo). Ciclo menstrual FORA por padrão (opt-in).
- **Consentimento (F37):** binário, microcopy honesta. **Bloqueador jurídico da v1.0** (N04).
- **Aprovação de profissionais (F42→N02):** Admin×Profissional com trava Blast Radius; trigger anti-autopromoção; **CRN/CRM/CREF na v1.0**.

## 7.5 Análises em 3 níveis (v5.2)
N1 tempo real sem custo (v1.0); N2 pré-calculado por Cron (BL); N3 IA sob demanda paga por execução, permanente, exclusiva do painel profissional (BL). Widgets "queda de engajamento" e "pacientes inativos" = alerta precoce (concorrentes já têm — o diferencial é a telemetria alimentando).

## 7.6 Ciclo menstrual e menopausa (F44) — **BL (Onda 3)**
Bem-estar; previsão de calendário sim, fertilidade NÃO; opt-in separado; nunca em ranking.

---

# PARTE 8 — DESIGN SYSTEM E UX (PREVALECE SOBRE DEFAULTS DE IA)

## 8.1 Proibições ("tiques de IA")
Gradiente roxo/índigo; glassmorphism generalizado; sombras difusas; emoji como ícone; creme+serifa+terracota default; quase-preto com verde-ácido; placeholders; microcopy traduzida do inglês; dois estilos para a mesma função.

## 8.2 Identidades por superfície
- **Atleta (escuro competitivo):** grafite #0E1114; UM acento de energia; números tabulares; assinatura = anel de HealthScore segmentado.
- **Guardião (claro clínico-acolhedor):** off-white quente; corpo ≥18pt; toque ≥48dp; AA/AAA; assinatura = linha do tempo vertical. Escala de fonte via `_escalarTextTheme` (nunca `fontSizeFactor` sobre estilos sem fontSize — crash comprovado).
- **B2B Web:** densidade alta, hairlines, zero ornamento, Recharts sóbrio.

## 8.3 Tokens e camadas de interface (v6.1 C)
Grade 8pt; um raio global + chips 999; escala tipográfica única (12/14/16/18/22/28/34); ícones outline 1 peso; cores só via tokens semânticos, zero hex em widget; motion 150/250ms. **Camadas com datas:** (1) tema/tokens no ThemeData central — **JÁ**, faz telas cruas nascerem com cara do produto; (2) componentes definitivos — pós-teste fake; (3) assinaturas visuais (anel HealthScore, ilustrações, animações) — **antes do beta de amigos** (matéria-prima dos vídeos de marketing).

## 8.4 Padrões de tela e microcopy
Estados vazios projetados; skeletons; **erros com causa distinta** (rede ≠ parse ≠ dado ausente ≠ inesperado; nunca stack trace em produção); 1 número-herói por tela; AA como piso; texto escalável a 130%. Microcopy pt-BR nativa (sentence case; verbos que dizem o que acontece; títulos contextuais por tipo de captura). Checklist por tela: objetivo+número-herói → 8.1 → só tokens 8.3 → Playwright 375/1280px com palavras longas pt-BR.

---

# PARTE 9 — EXECUÇÃO E PLANO DE TESTE

## 9.1 Fila de execução da Nutrição v1.0 (ordem por dependência)
O caminho crítico é **Fundação → Telemetria → Cálculo → Registro → Dashboards**. Fases 1 e 2 são as mais pesadas e menos glamourosas — é onde o projeto *parece* não andar, mas sustenta o resto.

**FASE 0 — Higiene e desbloqueio (antes de construir novo)**
- N26: mesclar F10 Passo 3 → F34 → D2, testando entre cada uma.
- N20: re-semear embeddings com o modelo real (sobrescrevendo os 23 mock) + índice vetorial + secret `EMBEDDING_MODEL_NAME`; semear TACO completa (~8.000).
- Segurança que destrava: rotacionar Service Role Key (R6), tratar GEMINI_API_KEY (R15), threshold configurável.
- N25: ligar governança de log `/docs/log_dev` + índice; sincronizar os 3 prompts.

**FASE 1 — Fundação de identidade e dados**
- N01 papéis M:N + admin único; N02 aprovação de profissional + CRN/CRM/CREF; N03 data de nascimento (deriva idade) + refação de telas; N05 campos de cadastro (telefone/e-mail); N06 telas do painel admin (via RPC de decifra D2); N04 consentimento de vínculo; matriz de permissões (D3 detalhada).

**FASE 2 — Telemetria (o cano que alimenta cálculo e cruzamento)**
- N17 persistência (upsert diário idempotente em `metricas_saude_diarias`); N18 Carga Inicial de 30 dias; N19 tela de consulta no app. *(Verificar/confirmar que grava ao longo do tempo — pendência C2.)*

**FASE 3 — Motor de cálculo**
- N07 Motor Metabólico (fatia); N08 Motor de Exceções (fatia + trava clínica); N09 anamnese (self-service + profissional); N10/N11 geração de meta (individual bem-estar e profissional prescrição, FC-001/FC-002).

**FASE 4 — Registro completo (núcleo diário)**
- N12 registro (foto/texto/favoritas; medida caseira; editar unidade+qtd; card consumo×meta); N13 favoritas; N14 mover peso típico para tabela; N15 persistência de aparelho por foto; N16 hidratação.

**FASE 5 — Dashboards + diferencial**
- N21 `catalogo_widgets` (semear widgets bem-estar/nutrição) + 3 dashboards; N22 cruzamento descritivo telemetria×nutrição (saldo energético + linha do tempo); N23 resumo semanal/mensal no app; N24 onboarding "valor antes de fricção".

**→ MARCO: TESTE SOLO DO FUNDADOR (1 semana, com diário).** Valida cálculo, gravação, cruzamento, fluxo. **Gamificação não é necessária aqui.**
**Depois do solo, antes dos amigos:** correções → **Bloco 5 (gamificação: levantar + especificar + desenvolver, F43)** → separar homolog×prod (R-E4) + backup/rotação da chave Vault (S6) + view R1 → zerar dados → build de homolog → abrir para amigos (Internal Testing).
**Em paralelo (lead time externo, desde já):** Play Console + Declaração Health Connect + Garmin Developer + naming/domínio/landing (Plano de Marketing Fase 0).

## 9.2 Ambientes (homolog × produção)
**Alvo:** dois projetos Supabase (homolog free + prod Pro). **Estado real (R-E4):** existe UM projeto (`xtipphglpqqrjguxcajn`). Antes de dado real (aqui = antes dos amigos; o fundador aceitou conscientemente rodar o teste solo no projeto único): criar prod separado + checklist de paridade (secrets, verify_jwt, Auth providers, GRANTs, config.toml). **Git:** develop→homolog / main→prod (alvo); prática atual = main protegida com merges por tarefa (aceitável na fase solo). **Migrações:** via CLI, versionadas; ao detectar drift, `db pull/diff` (R9).

## 9.3 Plano de teste
Web fake (pronto) → app fake (após a fila) → correções → **zerar** → teste real do fundador 1 semana com diário → amigos com Garmin/Android via loja (CPF) → iOS depois. **Backlog disciplinado:** nada do backlog entra em dev durante testes, exceto bug que impede o teste.

---

# PARTE 10 — EXECUÇÃO COM CLAUDE CODE + POLÍTICA DE MODELOS + GOVERNANÇA DE LOG

## 10.1 Ferramentas e papéis
Execução no **Claude Code**. Planejamento em chat de fronteira: **Gemini 3.1 Pro** (gerente de projeto/sequenciador), **Claude** (consultor estratégico/revisor), **GPT** (segunda opinião). Este Mestre = memória oficial.

## 10.2 Política de modelos (informar SEMPRE no cabeçalho do prompt)
Padrão **Sonnet** (~80%); trivial **Haiku** (copy, i18n, renomeações); crítico **topo de linha** (RLS, segurança, tokens/biometria, pipeline RAM, OAuth Garmin, criptografia, arquitetura). Economia: sessões curtas, /clear entre tarefas, apontar arquivos específicos.

## 10.3 Governança de log de desenvolvimento (regras 17/18)
- Ao fim de cada tarefa, o Claude Code grava `/docs/log_dev/AAAAMMDD_SSSS.md` (SSSS sequência de 4 dígitos por dia; ler o último antes de gravar), cabeçalho fixo (`data, seq, tarefa, branch, merge_sugerido, status`) + seções (Resumo · Entregue · Decisões técnicas|motivo · Desvios da spec · **Problemas encontrados** · **Riscos mapeados** · Como testar · Como tratou performance · Estado das branches).
- Mantém `/docs/log_dev/INDICE.md` append-only (uma linha por tarefa) — lido primeiro pelo Gemini e pelo consultor (economia de token).
- **Anti-alucinação:** registra só o que foi feito **e verificado**; `pronto-para-teste` ≠ `testado`.
- Ao fim de cada bloco, o Claude Code avalia branches e **sugere merge** (nunca mescla sem ok).
- O relatório humano longo continua no fim do output do prompt (para o fundador não-dev).

## 10.4 Template de prompt (usar sempre)
`[MODELO]` · `[CONTEXTO]` Parte 0 + seções relevantes (para nutrição: Parte V1 + Parte 0) · `[TAREFA]` objetivo único · `[ARQUIVOS]` caminhos exatos (investigar existentes antes de criar) · `[RESTRIÇÕES]` HOLD (4/BL); segurança (6); UX (8); server-side; GRANT explícito; sem segredos; sem hardcode (regra 16); performance na geração (regra 21); "validação completa/crua"; erro nunca disfarçado · `[ACEITE]` como o fundador testa, passo a passo · `[ENTREGÁVEL]`:
  1. Código + explicação simples do que foi feito.
  2. Commit em branch própria + instrução de PR (ou merge, se autorizado).
  3. **Relatório de fim de tarefa** (no log de máquina 10.3 **e** no relatório humano), com estes campos **obrigatórios**:
     - Decisões técnicas/arquiteturais (decisão | motivo) — para o Log (Parte 11).
     - Mudanças de infra/ambiente/config não visíveis no código (secrets, config.toml, providers, GRANTs, manifest nativo) — para a Parte 3.4.
     - Entidades novas (tabelas, views, funções, Edge Functions, telas, chaves i18n).
     - Desvios da spec (o que ficou diferente e por quê).
     - **Problemas encontrados** — o que a investigação do código real revelou e a spec não previa (arquivo/tabela que já existia, bug com outra causa, premissa errada). **Se não houve, escrever "nenhum"** (a ausência é uma afirmação consciente, não um silêncio).
     - **Riscos mapeados** — o que fica de pé como risco após a tarefa (débito técnico, pendência, algo que pode quebrar depois) + sugestão de mitigação. Alimenta a Parte 12.
     - Como o fundador testa (passo a passo, linguagem simples).
     - Como tratou performance (regra 21), quando houver laço sobre volume/consulta grande/pipeline de IA.
     - Estado das branches / ordem de merge sugerida.

## 10.5 Ritual do fundador
1 tarefa/sessão → implementação + explicação → teste pelo aceite → commit/PR → merge. Quebrou: `git revert`. O log de máquina substitui o copia-e-cola manual; consolidação no próximo marco.

---

# PARTE 11 — REGISTRO DE DECISÕES (LOG IMUTÁVEL)

## 11.1–11.5 Decisões históricas (preservadas do v6.0)
Preservadas na íntegra por referência (v6.0 Partes 11.1–11.5): decisões estratégicas até 16/Jul (HOLD seguradoras; custo mínimo; pseudonimização; B2B coração; server-side; organizador de dados/SaMD; preços; multi-profissional; D1/D2/D3); técnicas 12–29/Jul (Edge Function única `extract-metric-photo` por header; gate determinístico; menor privilégio; casamento léxico; dupla persistência; roteador 4 rotas; GEMINI_MODEL_NAME secret; família 2.5 morta → gemini-3.1-flash-lite; erro nunca disfarçado; `_escalarTextTheme`; Health Connect READ; pgvector estende `alimentos_referencia`; semeadeira RETRIEVAL_DOCUMENT); Adendo v5.2 + Plano de Marketing (widgets 3 níveis; N3 exclusivo do painel; catálogo central; orgânico 60/30/10; waitlist na própria stack). *Digest mantido para autossuficiência operacional; auditoria linha a linha no v6.0 arquivado.*

## 11.6 Decisões do Adendo v6.1 (30/Jul)
Papéis acrescidos (Growth/SaaS, Designer de Produto, Engenheiro de UI); prompts revisados p/ v6.0 (primeira ação do Gemini corrigida p/ F10 Passo 3); revisão sincronizada dos 3 prompts; metáfora de marca = a árvore; naming inventado 2-3 sílabas, filtrar Registro.br antes do INPI, radical latino de vida proibido; camadas de interface (tokens JÁ; componentes pós-fake; assinaturas antes do beta); gamificação viva antes do beta; onboarding valor-antes-de-fricção; Fase 0 de marketing; AIA Longeva monitorado.

## 11.7 Decisões desta consolidação (v7.0 — 07/Ago/2026)
| # | Decisão | Motivo |
|---|---|---|
| 1 | Meta = Nutrição v1.0 rodando e comercializável, com dashboard de usuário e de profissional | Frente que paga a conta |
| 2 | Dashboard do profissional = fluxo inteiro do Adendo_Nutrição (prescrição B2B real) | É o coração comercial (beachhead) |
| 3 | Dashboard do usuário = núcleo de bem-estar (peso, consumo, meta) + hidratação; clínico → BL | Coerência regulatória + escopo |
| 4 | Banco: muitos-para-muitos definitivo (`usuario_perfis`), tudo configurável, sem hardcode | Alicerce certo uma vez; evita retrabalho |
| 5 | Papéis ativos na v1.0 = prescreve + paciente + individual; demais depois | Fatiar sem inflar |
| 6 | Papel na entrada; profissional aprovado pelo admin; admin único via banco (não por e-mail no código) | Segurança + anti-hardcode |
| 7 | Data de nascimento substitui idade; refazer telas | Idade envelhece; cálculo metabólico precisa |
| 8 | ANVISA: sem acompanhamento = só bem-estar; número é estimativa editável; trava clínica se declarar condição; carga clínica só no profissional; faixas = alerta | Blindagem SaMD sem travar o produto |
| 9 | Módulo Clínico, Motor de Qualidade, Motor Adaptativo, Indicadores clínicos, Protocolos, IA Clínica → BL | Fatia mínima sólida > canivete meia-boca |
| 10 | Diferencial pesado na v1.0 = cruzamento descritivo telemetria×nutrição (Versão A) | O que os concorrentes não têm num lugar só |
| 11 | Insight interpretativo (Versão B) → BL (e só profissional) | É Motor Adaptativo + risco ANVISA ao avulso |
| 12 | Fórmulas: Mifflin padrão + Katch/Cunningham só com massa magra real | EX-005; massa magra via Health Connect/digitação |
| 13 | Massa magra/% gordura na interface Health Connect + digitação do profissional | Habilita Katch/Cunningham |
| 14 | TDEE em dois modos (PAL / decomposto estático), nunca misturados; trava anti-double-count do TEF | Decomposição sem religar o Motor Adaptativo |
| 15 | População v1.0 = adultos ≥18 incluindo idosos; excluir criança/adolescente/gestante/lactante | Corrige o 19-65; Mifflin vale p/ idoso; marca cobre sênior |
| 16 | Persistência de aparelho por foto (glicosímetro/pressão/balança) puxada para a v1.0 | Insumo do cruzamento; diferencial do sênior |
| 17 | Hidratação (ml/copo 200 configurável + histórico + widget) na v1.0 | Faltava; alimenta análises |
| 18 | Telemetria: persistência + Carga Inicial + tela de consulta = requisitos da v1.0 (construção nova) | O v6 afirmava pronto; não estava |
| 19 | Re-semear embeddings com modelo real (sobrescrever os 23 mock) + secret + índice | Busca semântica provavelmente quebrada |
| 20 | Peso típico sai do hardcode para tabela | Regra anti-hardcode |
| 21 | Governança de log `/docs/log_dev` (formato + índice + anti-alucinação) + avaliação de merge ao fim de bloco | Fim do copia-e-cola manual; evita deriva |
| 22 | Performance como critério de geração (regra 21) | Precedente da leitura de alimento |
| 23 | Resumo semanal/mensal no app (simples) na v1.0; relatório rico/sazonal → BL | Alimenta hábito; barato sobre dado existente |
| 24 | Definição avulso × profissional (1.13) | Governa permissão, cobrança e trava ANVISA |
| 25 | Campos de cadastro: telefone + e-mail de confirmação na v1.0; endereço → BL | Canal WhatsApp + higiene de conta |
| 26 | Medicamentos → BL | Não é núcleo de nutrição |
| 27 | v1.0 antecipa trabalho de Onda 4 (dashboards F51/cruzamento) conscientemente | É o diferencial; decisão explícita do fundador |
| 28 | Consolidar em v7.0 com v1.0 e backlog como Partes do Mestre; marketing segue separado | Documento separado = deriva |

---

# PARTE 12 — RISCOS CARREGADOS (ACOMPANHAR)

**Herdados do v6 (ainda válidos):**
- **R1 (alto):** view `perfis_pacientes_vinculados` sem `security_invoker` → WHERE é a única barreira. S9 + 7º cenário de isolamento. Antes dos amigos.
- **R3 (médio):** trial por `created_at` penaliza quem demora a ativar.
- **R4 (médio):** em produção, backfill de legado nasce pendente.
- **R5 (médio):** F42 sem spec formal → **resolvido na v1.0** (N02: CRN/CRM/CREF, fluxo de aprovação/rejeição).
- **R6 (alto/rápido):** Service Role Key viva no .env local → rotacionar (Fase 0).
- **R9 (médio):** schema drift git×banco → `db pull/diff` ao detectar.
- **R10 (médio):** `applicationId` = `br.com.atleta.app` (resolvido o `com.example`; pode mudar com o naming).
- **R11 (baixo):** dívida Built-in Kotlin (4 plugins).
- **R12 (baixo):** projeto Supabase free pode ser pausado por inatividade.
- **R13 (médio):** idade × data de nascimento → **resolvido na v1.0** (N03).
- **R14 (médio):** cadastro social sem perfil/papéis → **tratado na v1.0** (papel na entrada).
- **R15 (médio):** GEMINI_API_KEY duplicada → rotacionar junto do R6.
- **R-E4 (alto):** homolog×produção é um projeto só → separar antes dos amigos (o teste solo roda no projeto único, risco aceito conscientemente).
- **F15:** seed sem exames/anomalias → limita demo B2B.

**Novos (07/Ago):**
- **R16 (alto):** **embeddings mock** — 23 alimentos semeados com vetor falso × runtime com modelo real → busca semântica provavelmente quebrada. Mitigação: N20 (re-seed com modelo real + secret + índice) na Fase 0. É o risco nº1 do núcleo de nutrição.
- **R17 (médio):** **peso típico e listas de líquidos hardcoded** na Edge Function → fere anti-hardcode e dificulta manutenção. Mitigação: N14 (mover para tabela).
- **R18 (médio):** **telemetria sem persistência** — a leitura funciona mas não grava; a decomposição, o cruzamento e o NEAT dependem do histórico. Mitigação: N17/N18.
- **R19 (médio):** **escopo da v1.0 à frente do roadmap** (dashboards/cruzamento eram Onda 4) → risco de cronograma. Aceito conscientemente (diferencial). Acompanhar fôlego do fundador solo.
- **R20 (médio):** **threshold semântico 0,55** (baixado de 0,68) aumenta risco de casar alimento errado → caloria errada. Mitigação: configurável + o aviso honesto + edição do usuário compensam; monitorar.
- **R21 (baixo/precedente):** **performance tratada tarde** (leitura de alimento: busca O(n) em ~8.000 + normalização repetida) → vira regra 21 (performance na geração).
- **R22 (médio):** **F09 (esteira/projeção) não verificado** — declarado pronto, nunca visto. Auditar antes de contar com ele para a retenção.

---

*Continua na Parte V1 (especificação executável da Nutrição v1.0) e na Parte BL (backlog consolidado).*

---

# PARTE V1 — ESPECIFICAÇÃO DE EXECUÇÃO DA NUTRIÇÃO v1.0

> Esta Parte é o **coração executável**. Cada bloco (A–M) traz o que construir e **como o fundador testa** (critério de aceite em linguagem simples). Referência cruzada com os códigos `N##` da Parte 3.3.1. Ordem de construção = Parte 9.1.

## A. Identidade, papéis e acesso (N01–N05)
- **Papéis M:N (`usuario_perfis`):** um usuário pode ter vários papéis. Papéis existem em tabela de referência (sem enum no código). Ativos na v1.0: **nutri-prescreve, paciente (acompanhado), individual (avulso)**. Migração **definitiva** de `perfis_usuarios` (booleanos) → `usuario_perfis` (snapshot do banco antes; não há dado real). Aceite: criar um usuário, atribuir dois papéis pelo sistema, ver os dois ativos.
- **Admin único via banco:** papel `admin` em `usuario_perfis` (nunca `if email==...`). **Constraint de unicidade** (índice único parcial) recusa um segundo admin ativo. Primeiro admin entra por **migração de bootstrap** (o trigger anti-autopromoção F42 impede auto-concessão). Conta admin **segregada** (nunca também profissional/paciente). Aceite: tentar criar segundo admin → banco recusa.
- **Papel na entrada + aprovação de profissional (N02):** no cadastro a pessoa declara se é profissional; se sim, conta entra **pendente** (não prescreve) e cai numa **fila no painel do admin** (card com contador). Captura **CRN (nutri) / CRM (médico) / CREF (educação física)**; sem número, não prescreve. Admin aprova/recusa (conferência manual na v1.0). Aceite: cadastrar como profissional → aparece na fila → admin aprova → só então prescreve.
- **Consentimento de vínculo (N04 — bloqueador jurídico):** vínculo profissional↔paciente nasce **pendente**; o paciente aceita no app (aviso de privacidade explícito) antes de o profissional ver qualquer dado. Aceite: profissional vincula → paciente não aparece até aceitar.
- **Data de nascimento (N03):** substitui `idade` em todo o sistema; idade passa a ser **derivada**. Refazer telas de cadastro, perfil/alterar dados e onde a idade alimenta o cálculo. Habilita a faixa etária (bloco D). Aceite: cadastrar com data → idade aparece calculada; mudar o ano do sistema não muda a data.
- **Campos de cadastro (N05):** telefone (WhatsApp/DDI) + e-mail de confirmação na v1.0. Endereço → BL.
- **Matriz de permissões (D3 detalhada):** fórmula metabólica e meta = só profissional (paciente acompanhado não edita a própria meta); usuário individual edita a própria meta 1×/mês; peso/massa magra/% gordura = o próprio usuário ou o profissional; diagnóstico/exames = fora da v1.0.

## B. Painel web — telas de manutenção (N06)
Sob Administração → Configurações (só admin, via **RPC de decifra** do D2 — a lista mostra nickname/UUID; o dado pessoal só é decifrado no detalhe):
- **Manutenção de usuário** (tabela sem dados sigilosos; clicar abre detalhe; botão para disparar o link de redefinição de senha pelo fluxo neutro existente).
- **Manutenção de profissional** (mesmo formato e funções).
- **Profissional × usuário** (consultar quais usuários estão com cada profissional e vice-versa; incluir/retirar vínculo).
- **Manutenção de atividades físicas** (nome, gasto kcal/30min para 70 kg, masc e fem — *buscar fonte confiável e apresentar opções ao fundador antes de carregar*).
- **Manutenção de alergia alimentar** (nome, descrição, alimentos/ingredientes proibidos — *idem, fonte confiável*).
- **Manutenção de alimentos** (`alimentos_referencia`): valores por 100 pela unidade (grama/ml, sem "g" no nome), `acucares_100`, medida caseira, `peso_tipico` (recebe o que era hardcode), flag `revisao` (sim/não). Mantém a busca semântica desenhada.
Aceite: admin abre cada tela, edita um registro, vê refletir.

## C. Motor Metabólico (N07)
- **Fórmulas:** Mifflin-St Jeor (padrão/obrigatória); **Katch-McArdle e Cunningham disponíveis só quando há massa magra real** (Health Connect `LeanBodyMass`/`BodyFat` ou digitação do profissional; nunca inventar; EX-005). Escolha de fórmula = só do profissional. Catálogo de fórmulas extensível (FM-101+ inativas).
- **TDEE em dois modos, nunca misturados** (trava anti-double-count): **PAL** (TDEE = TMB × PAL; TEF e NEAT embutidos) **ou** **decomposto estático** (TMB + NEAT + EAT + TEF, calculado pelo profissional com os dados do momento; TEF explícito 10%). Nível de atividade por dia da semana.
- **Macros:** profissional escolhe % das calorias **ou** g/kg de peso (g/kg de massa magra só com composição corporal); usuário avulso recebe padrão único conservador. Protocolos (low carb/ceto/DASH…) → BL. Tudo configurável.
- **População:** adultos **≥18 incluindo idosos**; fora da faixa → não gera meta, orienta profissional.
Aceite: profissional monta meta nos dois modos e o total bate; sem massa magra, Katch/Cunningham não aparecem.

## D. Motor de Exceções (fatia) + trava clínica (N08)
Gates antropométricos (peso/altura/data de nascimento/sexo), objetivo obrigatório, EX-005 (massa magra). **Trava clínica ANVISA:** se o usuário **sem acompanhamento** declarar condição clínica (lista de exceções), o sistema **não** gera meta adaptada — mostra estimativa genérica de bem-estar e recomenda profissional. **Faixas de validação = alerta/confirmação** no caminho profissional; **gate duro** no sem-acompanhamento. Catálogo de exceções extensível, semeado só com o da v1.0. Aceite: avulso declara "diabetes" → sistema não personaliza, orienta profissional.

## E. Anamnese nutricional (N09, versionada)
- **Self-service** (avulso): obrigatória para liberar o registro; ao final o sistema sugere o consumo diário (meta de bem-estar).
- **Profissional:** puxa peso/altura/sexo/data já cadastrados; objetivo (manter/ganhar/perder — seleção); observação livre; atividade física (sim/não → dias da semana → atividades da tabela, intensidade pequena/média/alta, duração, opção "outras"); alergias (lista completa, múltiplas). Opcional para o profissional (pode ver a anamnese que o paciente já respondeu no app).
Aceite: responder anamnese → meta sugerida aparece; nova anamnese gera nova versão.

## F. Objetivo alimentar do profissional (N10)
Buscar paciente (CPF/e-mail/nome; só os seus). Definir metas por nutriente (kcal/carbo/proteína/gordura). **Único** para todo o período **ou** **por dia da semana** (profissional escolhe). Data início/fim. **Um ativo por vez.** **Vencimento:** vencido → **7 dias para revalidar** → senão expira. **Cards no painel:** planos vencidos / a vencer em 30 dias / a vencer em 7 dias (clicar → nomes → plano do paciente). **Copiar último plano** (só ajusta o que mudar); traz médias de consumo por dia da semana + TMB. Histórico de objetivos + detalhe por período. FC-001 (primeira prescrição) + FC-002 (retorno/nova versão) + versionamento. Aceite: criar objetivo, ver card de vencimento contar, copiar último e revisar.

## G. Meta do usuário sem acompanhamento (N11)
Anamnese libera o registro; meta = TMB + gasto por atividade (bem-estar). **Meta única** (não por dia). Revisão **1×/mês** ou prazo escolhido (pode ser < 30 dias) + 7 dias de revalidação. Não editável quando acompanhado (só o profissional). Ao **desvincular**, entra na regra do avulso; histórico preservado; anamnese válida não repete. Mesma tabela (`objetivos_alimentares`) do acompanhado. Aceite: avulso gera meta, edita 1×/mês, e ao vincular o profissional vê o histórico.

## H. Registro de refeição + alimentos (N12–N14)
- **Card de registro:** por **foto**, **digitando**, ou **buscar nas favoritas**. Favoritas por tipo (café/almoço/jantar/lanche), múltiplas; marcar como favorita ao registrar (seleciona o tipo); manutenção no perfil (excluir/trocar tipo). Favorita salva **com a medida customizada** e volta pronta.
- **Card por alimento:** nome popular/alias + descrição TACO + quantidade pela unidade de medida; calcula nutrientes pela quantidade. Usuário pode **alterar unidade de medida E quantidade** (hoje só edita gramas) → recálculo determinístico.
- **Peso típico (N14):** sai do hardcode da função → tabela `alimentos_referencia`; mantém o aviso honesto de estimativa + edição.
- **Card consumo × meta:** ao longo do dia, quanto falta / quanto passou.
- Persiste em `coleta_diaria`. Aceite: registrar prato por foto, editar medida, salvar favorita, ver consumo×meta atualizar.

## I. Aparelho por foto + hidratação (N15–N16)
- **Aparelho por foto (N15):** glicosímetro (gate 20–600 pronto), pressão, balança → **gravar** em `coleta_diaria` (o diálogo hoje não grava). Grava o número que o aparelho deu, **sem interpretação clínica** ao avulso. Vira insumo do cruzamento (bloco L).
- **Hidratação (N16):** tela de registro de água em **ml, por copo (padrão 200 ml, configurável)**; histórico diário por usuário; widget no dashboard; entra nas análises. `coleta_diaria` (`atributo = "agua_ml"`). Aceite: registrar 2 copos → histórico mostra 400 ml no dia; widget atualiza.

## J. Telemetria (N17–N19)
- **Persistência (N17):** ao abrir o app, puxar as últimas 24–48h e gravar por **upsert idempotente** (chave = data+tipo) em `metricas_saude_diarias`: relógio, passos, sono, FC, FC repouso, gasto energético, peso, **massa magra/% gordura**.
- **Carga Inicial de 30 dias (N18):** construir (não existe); habilita a Retrospectiva do dia 1.
- **Tela de consulta (N19):** o usuário vê a própria telemetria/histórico no app.
Aceite: abrir o app dois dias seguidos → `metricas_saude_diarias` tem uma linha por dia, sem duplicar.

## K. Alimentos e busca semântica (N20)
Re-semear **todos** os ~8.000 alimentos com o **modelo real** (via `EMBEDDING_MODEL_NAME`), **sobrescrevendo os 23 mock**; seed e runtime no mesmo modelo; criar índice vetorial (ivfflat/hnsw). Threshold configurável (0,55). Aceite: fotografar comida comum não cadastrada por nome → busca semântica encontra o alimento certo com similaridade coerente.

## L. Dashboards + diferencial + resumos (N21–N23)
- **Motor:** `catalogo_widgets` (reusar), semear widgets de bem-estar/nutrição.
- **Dashboard do usuário (bem-estar):** peso, consumo × meta, hidratação, passos/atividade, evolução no tempo. Sem indicador clínico.
- **Dashboard do paciente acompanhado:** o acima + a prescrição do profissional.
- **Dashboard do profissional:** lista de pacientes + drill-down (peso, consumo×meta, adesão, telemetria).
- **Cruzamento telemetria×nutrição (N22 — diferencial, Versão A):** saldo energético (consumo `coleta_diaria` × gasto `metricas_saude_diarias`) + linha do tempo sobreposta (peso, passos, sono, horário das refeições, glicemia/pressão). **Sem previsão e sem "porquê" clínico** ao avulso. Insight interpretativo (Versão B) = BL.
- **Resumo semanal/mensal no app (N23):** resumo simples do próprio usuário (o rico/sazonal F23 = BL).
Aceite: no dashboard, ver o saldo energético do dia e a linha do tempo com nutrição + telemetria juntas.

## M. Onboarding "valor antes de fricção" (N24)
Tela 0 (~5s): frase de valor + "Começar" + cadastro mínimo. Bifurcação (~10s): "Usa relógio?" → Sim: conectar Health Connect → Carga Inicial → primeiro cartão; Não: "Fotografe seu prato ou o visor do aparelho" → resultado. Só após o primeiro "uau": pedir o resto do perfil (progressive profiling), streak e convite. Custo: reordenar telas existentes + adiar campos. Aceite: usuário novo sente o valor antes de qualquer formulário longo.

---

# PARTE BL — BACKLOG CONSOLIDADO

> Regra: **tudo que não entra na v1.0 aparece aqui** — nada some. Cada item traz **origem · motivo do adiamento · gatilho de retomada**. HOLD referenciado (proibido implementar — Parte 4).

## BL.1 Frente de nutrição/produto adiada nesta conversa
| Item | Origem | Motivo do adiamento | Gatilho de retomada |
|---|---|---|---|
| Módulo Clínico (anamnese clínica versionada, diagnósticos, condições, medicamentos, suplementação, exames, avaliações corporais, evolução, protocolos clínicos) | Módulo 6 (doc novo) | Plataforma clínica ≠ nutrição v1.0; peso regulatório | Após validação da v1.0; quando entrar o público clínico |
| Motor de Qualidade dos Dados (Score Global, completude, consistência) | back_end Módulo 3 | Só serve de insumo ao Motor Adaptativo | Junto do Motor Adaptativo |
| Motor Adaptativo (recalibração/aprendizado que reajusta metas) | back_end Módulo 4 | Item mais caro; recalibração é disparada pelo profissional; risco ANVISA ao avulso | Pós-validação; só caminho profissional |
| Decomposição **adaptativa** do TDEE (reaprende sozinha) | Bloco 2 desta conversa | = Motor Adaptativo | Idem acima |
| Insight interpretativo automático (Versão B do cruzamento) | Bloco 1 desta conversa | Inferência = apoio à decisão clínica; ANVISA | Pós-validação; só profissional |
| Motor de Indicadores clínicos (HbA1c, lipídico, renal, HRV, VO₂ — IND clínicos) | Módulo 7 (doc novo) | Fora do bem-estar; duplica `catalogo_widgets` | Com o Módulo Clínico |
| Motor de Protocolos Clínicos (Módulo 8 proposto) | observações_importantes | Protocolo é preenchido pelo profissional fora do sistema por ora | Quando houver demanda de protocolos parametrizados |
| Motor de IA Clínica (Módulo 9 proposto) | observações_importantes | Concentra IA clínica; separar por conformidade | Pós Módulo Clínico |
| Protocolos de macro (low carb, cetogênica, DASH, mediterrânea, plant-based, hiperproteica) | back_end §Macros | v1.0 usa % e g/kg | Quando o profissional pedir protocolos nomeados |
| Fórmulas FM-101+ (Harris-Benedict, Owen, Schofield, Henry, IOM…) | BOFM §3 | v1.0 = Mifflin/Katch/Cunningham | Quando surgir população/necessidade específica |
| Granularidade do consentimento (F37-fase2) | v6 F37 | v1.0 usa consentimento binário | Quando exigir escopo por tipo de dado |
| Endereço no cadastro (número/complemento) | v6 F06 / decisão 07/Ago | v1.0 de nutrição não usa endereço | Com faturamento/CNPJ |
| Relatório rico/sazonal | v6 F23 | v1.0 traz resumo simples | Pós-validação |
| Mapa de modelo por `tipo_captura` (visores/PDF em tier capaz; comida no lite) | v6 §custo IA | Otimização de custo | Quando o custo de IA justificar |
| Predições (peso, glicemia, composição, adesão), detecção de abandono, benchmark populacional, IA explicável avançada, indicadores compostos | observações_importantes §melhorias futuras | Não são necessárias à v1.0 | Pós-PMF |

## BL.2 Gamificação / motor viral (Bloco 5 — gatilho definido)
F43 (Retrospectiva de Boas-Vindas, Cartão da 1ª Semana, Retrospectiva Mensal), pontos sociais, streak, ligas/rankings (F38), widget streak+anel (F18), válvula anti-culpa (F19), pontos de refeição/peso/revisão de plano, medicamentos (F22), mensagens de ciclo do vínculo (F39). **Origem:** v6 Parte 7 + decisões 07/Ago. **Motivo:** construir sobre o núcleo já validado; medir retenção com o motor vivo. **Gatilho:** **entre o teste solo do fundador e o beta de amigos** (não antes do solo, não depois do beta). *Nota: a Retrospectiva de Boas-Vindas é insight do dia 1 e depende da Carga Inicial (N18).*

## BL.3 Ondas futuras (v6 — não-feito)
| Item | Origem | Gatilho |
|---|---|---|
| Exportação PDF+CSV / loop viral B2B (F16) | v6 Onda 2 | Fase de marketing/beta |
| Alerta de Tendência não-clínico (F17) | v6 Onda 2/3 | Pós-validação |
| Modo Cuidador/Familiar (F20), Relatórios sazonais (F23), Ciclo menstrual/menopausa (F44) | v6 Onda 3 | Público Guardião/feminino |
| Prescrição de **treino** + Garmin em produção (F26 treino), 2FA painel (F25), Deep link WhatsApp (F27), `logs_acesso` popular (F28), Liga por profissional (F38) | v6 Onda 4 | Fase 2 B2B (primeiros pagantes) |
| Dashboards Nível 2/3 (F51 N2/N3) | v6 v5.2 | Demanda comprovada |
| Alta frequência bruta + FIFO (F35), Índice de Bem-Estar (F31), Modo Recuperação Humano (F21), Revogação instantânea (F24 auditar) | v6 | Conforme necessidade |
| Diagnóstico de coleta / liga-desliga Health Connect (F49), Widget único de câmera (F50), Biometria de abertura (F04), F15 seed de exames/anomalias | v6 Parte 9.5 | Higiene/qualidade pós-núcleo |

## BL.4 EM HOLD (⛔ proibido implementar — Parte 4)
Score Atuarial/Sinistralidade para seguradoras (F12/F14) e afins. **Retomada só sob todas as condições da Parte 4.1.** Fora de escopo sem revisão: chat aberto de IA sobre saúde; SDKs proprietários de wearables; feed social; expansão internacional antes do PMF.

---

*Fim do Documento Mestre v7.0. Para continuidade: cole este v7.0 em qualquer nova sessão (+ o Plano de Marketing v1.0 quando o assunto for marca). Evolução por adendo/log (`/docs/log_dev`); próxima consolidação (v8.0) no próximo marco — sugerido: fim da rodada de teste fake do app.*
