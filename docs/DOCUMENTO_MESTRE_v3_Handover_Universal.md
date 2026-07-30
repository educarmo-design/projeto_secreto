# DOCUMENTO MESTRE v3.0 — HANDOVER UNIVERSAL DO PROJETO
## Plataforma de Saúde Preventiva Baseada em IA (Ecossistema B2C/B2B)

**Data de referência:** Julho de 2026
**Status:** FONTE ÚNICA DE VERDADE. Substitui e consolida: PRD Consolidado v1, Apêndice de Arquitetura, Roadmap em Ondas, Estudo de Mercado, Handover Técnico e PRD v2.0. Em caso de conflito entre documentos, este prevalece.
**Propósito:** Este documento é autossuficiente. Qualquer assistente de IA (Claude, ChatGPT, Gemini ou outro) que receber este arquivo deve ser capaz de assumir o projeto imediatamente, sem contexto adicional.

---

# PARTE 0 — INSTRUÇÕES DE OPERAÇÃO PARA O ASSISTENTE DE IA

Se você é uma IA recebendo este documento, siga estas regras em ordem de precedência:

1. **NUNCA implemente, expanda ou corrija** os itens marcados como EM HOLD (Parte 4).
2. **Antes de escrever qualquer código novo**, execute o Protocolo de Auditoria (Parte 3) se ainda não foi executado nesta fase do projeto. O status "implementado" declarado neste documento significa "declarado em sessões anteriores de IA" — não "verificado por humano". Trate como não-confiável até auditar.
3. **Os requisitos de segurança da Parte 6 são bloqueadores de release.** Nenhum build vai para testadores externos sem todos aprovados.
4. **As diretrizes de UX da Parte 8 prevalecem** sobre qualquer padrão visual default seu.
5. **Regra de arquitetura inegociável:** toda regra de negócio sensível (pontos, streaks, scores, desbloqueios, elegibilidade) é calculada server-side (Edge Functions/Cron). O cliente apenas exibe.
6. **Regra de dados inegociável:** nenhum dado real de usuário em APIs de IA gratuitas ou com cláusula de treinamento. Zero mídia persistida (pipeline RAM volátil).
7. **Git:** proibido force push. Proibido commitar segredos, chaves ou IDs de projeto. Branch main protegida, trabalho via branches + PR.
8. **O perfil do fundador:** não-desenvolvedor, trabalhando solo, usando IA para 100% do código. Explique decisões técnicas em linguagem simples, commite em etapas funcionais pequenas e sempre diga como testar o que foi feito.
9. **Ferramenta de execução adotada:** Claude Code (ver Parte 10 para o guia de modelos e o template de prompt).
10. **Idioma de trabalho:** português brasileiro. Código e nomes de variáveis em inglês ou português conforme padrão já existente no repositório (auditar antes de decidir).

---

# PARTE 1 — VISÃO DE NEGÓCIO E CONTEXTO ESTRATÉGICO

## 1.1 O problema
Fragmentação extrema das healthtechs (apps isolados para calorias, prontuários ou wearables), baixa retenção crônica de diários manuais e perda do histórico clínico de longo prazo pelos pacientes.

## 1.2 A solução
Ecossistema unificado: **um backend (Supabase) + múltiplos apps de interface** por nicho:
- **App Atleta** (B2C, gamificação estilo Duolingo/Strava, tema escuro competitivo) — assinatura anual R$ 179,90 com 14 dias grátis.
- **App Guardião Clínico** (B2C sênior/crônico, linha do tempo de exames, medicamentos, sem competição).
- **Painel Web B2B** (React) para nutricionistas, treinadores e médicos — ticket R$ 120/mês por profissional (até 20 pacientes).

## 1.3 Decisão estratégica central (revisão v2)
**A Fase 2 (B2B profissionais) é o coração comercial do negócio**, não uma extensão. O B2C Atleta é ferramenta de engajamento do paciente e canal de aquisição, não a aposta principal de receita. Motivo: canal de vendas B2B é identificável e previsível (nutricionistas via CRN/Instagram/congressos); o B2C orgânico viral (modelo Cal AI) é loteria estatística.

## 1.4 Mercado (síntese validada)
- Mercado global de apps de saúde/fitness: US$ 13,8–14,6 bi, projeção > US$ 33 bi (CAGR > 13,5%).
- Validações: Cal AI (visão por foto, ARR US$ 30-35M, vendida por ~US$ 50M), Whoop (assinatura de dados, US$ 3,6 bi), Strava (gamificação/ligas, US$ 2,2 bi), MyFitnessPal (US$ 310M/ano em assinaturas).
- Brechas locais: Wellhub não faz inteligência de dados; Desrotulando é ferramenta isolada; Dietbox/Nutrium têm apps de paciente fracos (nossa entrada B2B); operadoras (Sami, Alice) são sistemas fechados.
- Premissas conservadoras adotadas: conversão trial→pago 1–2,5%; retenção 30 dias do mercado 5–10%.

## 1.5 Lacunas conhecidas do estudo de mercado (pendências não-técnicas)
1. **Análise de CAC inexistente** — modelar 3 cenários (orgânico puro / híbrido / pago a R$ 3–8 por instalação) antes de investir em divulgação. CAC pode superar LTV de R$ 179,90 se o orgânico falhar.
2. **Cenário de resposta competitiva** — Samsung Health/Google podem embutir análise de foto grátis; o fosso real é a base longitudinal + relação B2B.
3. **Validação primária** — entrevistar 20 nutricionistas e 20 usuários-alvo antes do lançamento público.

## 1.6 Unit economics de referência
- B2C mensal R$ 29,90: taxa loja 15% (−R$ 4,48), imposto ~6% no CNPJ (−R$ 1,79), IA ~R$ 0,012/usuário/mês → margem > 75%.
- B2C anual: R$ 179,90 (produto principal do funil).
- B2B: R$ 120/mês por profissional; custo IA agregado R$ 0,30–0,60/mês → margem > 80%.
- **Correção v2:** premissa "custo zero" substituída por "custo mínimo controlado" (ver 1.7).

## 1.7 Custos reais reconhecidos
| Item | Valor | Quando |
|---|---|---|
| Gemini API paga (nunca free tier com dados reais) | ~R$ 0,012/usuário/mês | Desde o 1º usuário real |
| Supabase Pro | ~US$ 25/mês | Desde o 1º usuário real (free só com seed fictício) |
| Google Play Console | US$ 25 único | Agora (fase de teste) |
| Apple Developer | US$ 99/ano | Adiado até beta iOS |
| CNPJ + contador | ~R$ 200–400/mês | Gatilho: 50 assinantes OU campanha pública |
| Parecer jurídico ANVISA/LGPD | R$ 5–15 mil único | Antes do lançamento público |
| Revisão de segurança por dev sênior | R$ 2–5 mil único | Antes do lançamento público |

## 1.8 Situação jurídico-fiscal atual
Operação em CPF (permitida na fase de teste e primeiras vendas): contas de desenvolvedor como pessoa física; receita das lojas declarada via carnê-leão mensal (rendimento do exterior, alíquota progressiva até 27,5%). **MEI não é permitido** para a atividade; o caminho é ME/Simples Nacional. Responsabilidade ilimitada no CPF — o gatilho de CNPJ (50 assinantes ou campanha pública) é mandatório. LGPD aplica-se desde o primeiro usuário real, com ou sem CNPJ.

---

# PARTE 2 — ARQUITETURA TÉCNICA (REFERÊNCIA)

## 2.1 Stack
- **Backend:** Supabase (PostgreSQL + Auth + Edge Functions em Deno/TypeScript + Cron Jobs). RLS ativado em todas as tabelas.
- **Mobile:** Flutter (app unificado, padrão Feature-First), i18n via `lib/l10n/` (`pt.json`, `en.json`, `es.json` — pt-BR é a fonte). UI dinâmica pela tag `perfil_uso` (atleta / exames_puro / foto_assincrono) sem reinicialização.
- **Web B2B:** React + TypeScript + Vite, code splitting manual (vendor-react, vendor-supabase, vendor-charts), deploy em Cloudflare Pages (já no ar, sem dados).
- **IA:** Google Gemini 2.5 Flash via API paga, chamada exclusivamente pelo servidor (Edge Function). Chaves apenas em variáveis de ambiente do servidor.
- **Wearables:** leitura LOCAL via pacote `health` (Android Health Connect / iOS HealthKit). Proibido usar APIs de nuvem pagas de agregação (ex.: Terra API) nas Ondas 1–2. Sync: oportunista na UI + background 1x/dia (WorkManager, restrições: carregando + Wi-Fi). Carga inicial: 30 dias históricos no primeiro acesso.
- **Garmin Training API:** Edge Function `supabase/functions/garmin-gateway/` com OAuth 1.0a (HMAC-SHA1), server-to-server, para enviar treinos prescritos ao relógio do aluno (Fase 2).

## 2.2 Esquema de dados (modelo de colunas fixas, pós-migração do JSONB genérico)
- `perfis_usuarios` — identificação (id ref auth.users, nome, email, CEP, endereço). Criptografia em repouso. Sigilo máximo.
- `metricas_saude_diarias` — 1 linha por usuário/dia (passos, sono, peso, FC média/repouso/máxima, glicose, pressão agregados).
- `diario_alimentar_diario` — nutrição híbrida: macros em colunas fixas, micros em JSONB.
- `resultados_exames` — padrão EAV (Entidade-Atributo-Valor) para curvas históricas; nomes de exames normalizados para chaves universais (ex.: `blood_glucose`) independentemente do idioma do PDF original.
- `eventos_treino` — exercícios estruturados.
- `eventos_anomalias_saude` — "Caixa Preta": picos biológicos críticos gravados com granularidade fina para auditoria.
- `progresso_gamificacao` — streaks, pontos, status, recuperação.
- `planejamento_clinico` — prescrições da Fase 2 (JSONB de estrutura de plano, flag sincronizado_garmin).
- `logs_acesso` — **(criar na próxima sessão se não existir)** auditoria append-only: quem acessou o quê, quando, de onde. Sem UPDATE/DELETE (policies).
- Indexação B-Tree composta (usuario, tipo, data DESC). Meta de latência < 200ms.
- **Pseudonimização (não "anonimização"):** separação lógica Tabela de identidade × tabelas de saúde via `usuario_id_anonimo`. Sob LGPD é dado pessoal pleno — vocabulário corrigido em toda a documentação e marketing.

## 2.3 Pipelines críticos
- **Zero Storage Pipeline (visão):** câmera nativa forçada (galeria bloqueada, antifraude anti-moiré/reflexo) → bytes em RAM local → stream binário TLS 1.3 → Edge Function aloca em RAM volátil → Gemini extrai JSON estruturado → persiste JSON em banco → **destrói a mídia da RAM imediatamente**. Nenhuma mídia toca disco, nunca.
- **Cron da madrugada:** insights diários em lote + rankings geográficos pré-calculados em cache estático (exibem apenas nickname + avatar; ranking público de localidade só com N ≥ 30 usuários ativos).
- **Cadastro adaptativo:** chip BR → ViaCEP autocompleta; internacional → campo postal manual livre, sem chamadas de API.
- **Autenticação:** OAuth Google/Apple + cadastro tradicional com OTP 6 dígitos por e-mail; tokens no Android Keystore / iOS Keychain via secure storage; biometria obrigatória para descriptografar; JWT 60 min + refresh com rotação.

---

# PARTE 3 — MATRIZ DE STATUS E PROTOCOLO DE AUDITORIA

## 3.1 Legenda de status
- ✅ **DECLARADO-IMPLEMENTADO:** relatado como pronto em sessões anteriores de IA. **NÃO VERIFICADO POR HUMANO.**
- 🔍 **VERIFICADO:** auditado e testado pelo fundador em dispositivo/ambiente real (atualizar manualmente após cada auditoria).
- 🔲 **PENDENTE:** especificado, não iniciado.
- ⛔ **EM HOLD:** proibido implementar (Parte 4).

## 3.2 Matriz de funcionalidades

| # | Funcionalidade | Status | Observação de auditoria |
|---|---|---|---|
| F01 | Esquema de dados em colunas fixas + RLS em todas as tabelas | ✅ | Auditar: RLS realmente ativo? Teste 2 usuários (Parte 3.3, item 4) |
| F02 | Tabela Caixa Preta (eventos_anomalias_saude) | ✅ | Auditar gravação real de um pico |
| F03 | Login social Google/Apple + OTP 6 dígitos | ✅ | Testar fluxo completo em aparelho |
| F04 | Cofre de hardware (Keystore/Keychain) + biometria obrigatória | ✅ | Testar em aparelho físico |
| F05 | Suíte de testes de segurança em test/core/security/ | ✅ | **Ceticismo alto:** testes de IA podem testar pouco. Revisar conteúdo |
| F06 | Cadastro adaptativo BR (ViaCEP) / internacional | ✅ | Testar com chip BR |
| F07 | Sync wearables (30 dias iniciais + oportunista + background 1x/dia) | ✅ | **Teste crítico com Garmin real** (Parte 9, Etapa 3) |
| F08 | Dashboard modular drag-and-drop + switches de cards | ✅ | Revisar contra diretrizes UX (Parte 8) |
| F09 | Esteira 14 dias + Cadeado Dourado Borrado (dia 7) | ✅ | **Reescrever nomenclatura:** agora é "Projeção de Hábitos e Consistência" (sem exames no B2C) — ver Parte 5.2 |
| F10 | Gateway Gemini + Zero Storage Pipeline | ✅ | Auditar: mídia realmente não persiste? Chave só no servidor? Free tier ou pago? |
| F11 | Painel React B2B (dados brutos, code splitting, Cloudflare) | ✅ | No ar sem dados. Verificar se URL exige login |
| F12 | Filtragem "anônima" para seguradoras no painel | ⛔ | Parte do módulo EM HOLD — não expandir |
| F13 | Garmin Training API Gateway (OAuth 1.0a) | ✅ | Exige aprovação no programa Garmin — verificar status do cadastro |
| F14 | Motor de sinistralidade (sinistralidade_engine.dart + espelho TS) | ⛔ | EM HOLD (Parte 4). Se existir código, isolar atrás de feature flag desligada |
| F15 | Script de seed (10–20 usuários, 30 dias, EAV, anomalias) | 🔲 | **PRÓXIMA TAREFA.** Usuários via Auth Admin API, nunca INSERT direto |
| F16 | Exportação completa de dados (PDF + CSV, LGPD art. 18) | 🔲 | Onda 2 — prioridade máxima das novas |
| F17 | Alerta de Tendência não-clínico (janelas de 4 semanas) | 🔲 | Onda 2/3, server-side, linguagem de convite à consulta |
| F18 | Widget de tela inicial (streak + anel) | 🔲 | Onda 2 |
| F19 | Válvula de proteção alimentar (registro sem foto 2x/semana; nunca punir conteúdo calórico) | 🔲 | Onda 2 — ajuste no algoritmo de streak |
| F20 | Modo Cuidador/Familiar (somente leitura + alertas de remédio) | 🔲 | Onda 3. Pagante-alvo: filho adulto |
| F21 | Modo Recuperação Humano (congela jogo, interface acolhedora) | ✅/🔲 | Especificado no PRD v1; auditar se foi implementado |
| F22 | Registro de medicamentos + push local + missão diária | ✅/🔲 | Auditar implementação real |
| F23 | Relatórios sazonais macro (tri/semestral/anual via resumos textuais) | 🔲 | Onda 3 |
| F24 | Revogação instantânea de acesso do profissional pelo paciente | ✅/🔲 | Auditar; espelhar padrão no Modo Cuidador |
| F25 | 2FA no painel web profissional | 🔲 | Onda 4 (bloqueador da Fase 2) |
| F26 | Prescrição ativa (cardápios + planilhas de corrida) | 🔲 | Onda 4 |
| F27 | Deep linking WhatsApp (cobranças e convites virais) | 🔲 | Onda 4 |
| F28 | logs_acesso append-only | 🔲 | Criar já (schema), popular na Fase 2 |
| F29 | Requisitos de segurança S1–S9 (Parte 6) | 🔲 | Bloqueadores de release |
| F30 | Telas revisadas pelo design system (Parte 8) | 🔲 | Passar tela a tela no checklist 8.6 |

## 3.3 PROTOCOLO DE AUDITORIA (primeira tarefa de qualquer nova sessão de código)
Execute e reporte em linguagem simples, item a item:
1. **Inventário:** listar árvore do repositório e comparar com a matriz 3.2; marcar o que existe de fato.
2. **Segredos:** varrer o repositório por chaves/API keys/IDs commitados (gitleaks ou grep). Se achar, rotacionar a chave no provedor e limpar histórico.
3. **RLS:** para cada tabela, confirmar `ENABLE ROW LEVEL SECURITY` + policy vinculada a `auth.uid()`. Listar tabelas sem policy.
4. **Teste de isolamento:** com 2 usuários de teste, tentar ler dados cruzados via API REST do Supabase. Esperado: vazio/negado.
5. **Pipeline de visão:** confirmar que a chamada Gemini parte do servidor (não do app), que a chave não está no app, e qual tier de API está configurado (deve ser pago).
6. **Testes existentes:** abrir test/core/security/ e avaliar o que os testes realmente cobrem; reportar honestamente.
7. **F14/F12 (HOLD):** localizar o código do motor de sinistralidade; garantir que está atrás de flag desligada e sem rotas ativas.
8. **Build:** rodar `flutter analyze` + build debug; listar erros/warnings reais.
9. Atualizar a matriz 3.2 (✅→🔍 ou ✅→🔲 conforme o encontrado) e devolver a nova versão ao fundador.

---

# PARTE 4 — ITENS EM HOLD (PROIBIDO IMPLEMENTAR)

## 4.1 Score Atuarial / Sinistralidade para Seguradoras — ⛔ EM HOLD
**Congela:** `sinistralidade_engine.dart`, espelho TypeScript, indicador "Redução Estimada de Sinistralidade", login administrativo de operadoras, qualquer exibição/venda de score de usuários a terceiros.
**Motivos:** (1) políticas do Google Health Connect e Apple HealthKit proíbem uso de dados dessas APIs para fins atuariais/seguros — risco real de banimento das lojas; (2) cálculo estava no cliente (manipulável); (3) LGPD exige base legal, consentimento destacado e RIPD inexistentes.
**Condições cumulativas de retomada:** redesenho usando só dados fornecidos diretamente pelo usuário (nunca HealthKit/Health Connect) + consentimento específico revogável com benefício direto ao titular (modelo Vitality) + cálculo 100% server-side com auditoria + parecer jurídico formal (LGPD/SUSEP) + verificação das políticas das lojas vigentes na data.
**Instrução:** se encontrar esse código, não expandir, não corrigir, não integrar. Isolar atrás de feature flag desligada.

## 4.2 Fora de escopo sem nova revisão
Chat aberto de IA sobre saúde; SDKs proprietários de wearables além dos agregadores nativos; feed social estilo Strava; expansão internacional/idiomas antes do PMF no Brasil.

---

# PARTE 5 — BLINDAGEM JURÍDICA E REGULATÓRIA

## 5.1 LGPD
- Dados de saúde = dado sensível (art. 11): consentimento específico e destacado no onboarding; política de privacidade pública (URL exigida pela Play); direito de exclusão e portabilidade (F16) implementados no app.
- Pseudonimização ≠ anonimização: nunca usar "anônimo" em termos/marketing para dados vinculáveis.
- Proibido enviar dado real a IA em free tier ou com cláusula de treinamento.
- Comunicação de incidente: referência de 3 dias úteis à ANPD (ver S7).
- RIPD (Relatório de Impacto) a produzir antes do lançamento público.

## 5.2 ANVISA (RDC 657/2022) — tese revisada
A classificação como SaMD depende da **finalidade**, não do vocabulário. Regras funcionais:
- O app B2C **não cruza exames laboratoriais com telemetria** para predições individuais. Predições B2C ficam no território de hábitos (consistência, tendência de sono, regularidade).
- A "cenoura" do dia 7 chama-se **"Projeção de Hábitos e Consistência"** (projeção de streak, pontos, ranking, metas comportamentais). Correlações clínicas: só no painel do profissional (CRM/CRN), onde a responsabilidade é humana.
- Alerta de Tendência (F17): apenas convite à consulta, sem interpretação clínica, sem termos diagnósticos.
- IA do app proibida de emitir laudos, diagnósticos ou termos médicos diretos; painel B2B mostra dados brutos e reais.
- Parecer jurídico formal contratado antes do lançamento público (bloqueador de release, não de desenvolvimento).
- Atenção Fase 2: prontuário médico tem requisitos próprios de guarda (até 20 anos) — reconciliar com a política de minimização antes de ativar o painel para médicos.

## 5.3 Lojas de aplicativos
- Play Console: formulário Data Safety espelhando a política de privacidade; **Declaração de Apps de Saúde do Health Connect** (aprovação do Google, pode levar semanas, bloqueia distribuição ampla — protocolar já).
- Contas pessoais novas: exigência de teste fechado (14 dias contínuos com nº mínimo de testadores — conferir número vigente no Console) antes de produção. Internal Testing é liberado de imediato (até 100 testadores).
- Apple (futuro): TestFlight exige conta paga; conta Individual expõe nome pessoal na loja — mais um motivo para o gatilho de CNPJ.

---

# PARTE 6 — REQUISITOS DE SEGURANÇA (BLOQUEADORES DE RELEASE)

Complementam TLS 1.3 + SSL pinning, Keystore/Keychain + biometria, RLS e Zero Storage já especificados.

- **S1. Sessão server-side:** refresh token com rotação; ação "Desconectar todos os aparelhos"; token revogado rejeitado em < 60s.
- **S2. Proteção de tela:** FLAG_SECURE nas rotas clínicas (Android) + ocultação na miniatura de apps recentes; ofuscação de snapshot no iOS. Exceção: telas de gamificação podem permitir screenshot (viralização).
- **S3. Root/jailbreak:** detectar na abertura, avisar o usuário (sem bloquear) e gravar flag `dispositivo_comprometido` no servidor.
- **S4. Rate limiting + teto financeiro:** máx. 30 análises de imagem/dia/usuário; alerta de billing (US$ 10/dia) no Google Cloud; circuit breaker global acima do teto diário.
- **S5. logs_acesso append-only:** criado já, populado na Fase 2 e no Modo Cuidador. Sem UPDATE/DELETE.
- **S6. Backup testado:** ritual mensal de restauração em staging com validação de integridade.
- **S7. Plano de resposta a incidente:** arquivo `INCIDENT_RESPONSE.md` no repositório privado — sequência de contenção (revogar chaves → banco read-only → invalidar sessões), responsáveis, modelo de comunicação a titulares/ANPD, contato do advogado.
- **S8. Higiene de repositório:** main protegida (sem force push, inclusive por agentes de IA), PRs obrigatórios, varredura de segredos no CI, zero chaves em código.
- **S9. Revisão humana:** dev sênior revisa RLS, fluxo de tokens/biometria e pipeline de imagem antes do primeiro release público. Testes gerados por IA não substituem.

---

# PARTE 7 — GAMIFICAÇÃO E RETENÇÃO (REGRAS DE NEGÓCIO)

- **Streak diário:** Condição 1 (1 foto de refeição OU, até 2x/semana, registro rápido sem foto — F19) + Condição 2 (treino Garmin detectado OU 8.000 passos locais). Quebra zera a chama e aplica −100 pontos. Nunca punir conteúdo calórico; pontuar consistência de registro.
- **Cálculo server-side** (Cron da madrugada); cliente só exibe.
- **Rankings:** ligas de amigos, cidade, estado, país; cache estático noturno; nickname + avatar; localidade pública só com N ≥ 30.
- **Esteira 14 dias:** Dia 1 carga de 30 dias históricos (mata o dashboard vazio); dias 1–6 missões homeopáticas de upload de exames; dia 7 desbloqueio do 1º prêmio (com congelamento — não zeragem — em caso de imprevisto) + teaser "Projeção de Hábitos e Consistência" borrada com cadeado dourado (BackdropFilter blur) → conversão no dia 14 para anual R$ 179,90.
- **Marcos:** relatórios especiais 21/28 dias; Modo Competição Target aos 45 dias.
- **Modo Recuperação Humano:** voluntário, congela ofensivas sem punição, paleta calma, foco em sono/medicação/nutrição regenerativa.
- **Medicamentos:** cadastro de dose/horário, push local, missão diária (+10 pts).
- **Copy de paywall:** Atleta = pontos, ranking da cidade, relatório trancado; Guardião = linha do tempo clínica de uma vida + controle automatizado de remédios.

---

# PARTE 8 — DESIGN SYSTEM E UX (PREVALECE SOBRE DEFAULTS DE IA)

## 8.1 Proibições explícitas (eliminar "tiques de IA")
Gradiente roxo/índigo como identidade; glassmorphism generalizado; sombras difusas em cascata; **emoji como ícone de UI**; paleta creme+serifa+terracota default; fundo quase-preto com verde-ácido único; marcadores numerados decorativos sem sequência real; placeholders ("Lorem ipsum", "usuário123"); microcopy traduzida do inglês ("Ops, algo deu errado :("); dois estilos de componente para a mesma função.

## 8.2 Identidades por superfície
- **Atleta (escuro competitivo):** base grafite #0E1114 (não preto puro); UM acento de energia (laranja-cobre OU verde-sinal, nunca ambos); números em face condensada com algarismos tabulares; assinatura visual = anel de HealthScore segmentado por métrica com gaps visíveis (não copiar Apple).
- **Guardião (claro clínico-acolhedor):** off-white quente; corpo ≥ 18pt; toque ≥ 48dp; contraste AA/AAA; acento único azul-petróleo ou verde-sálvia; sem contadores agressivos; vermelho só em confirmação destrutiva; assinatura = linha do tempo vertical por ano.
- **B2B Web:** instrumento profissional — densidade alta, hairlines, zero ornamento, Recharts com paleta sóbria e legendas completas, números tabulares.

## 8.3 Tokens (fonte única)
Grade 8pt (4pt micro); um raio global (ex.: 12) + um para chips (999); escala tipográfica única (12/14/16/18/22/28/34) num TextTheme central; um único set de ícones outline (Phosphor ou Lucide, 1 peso); cores só via tokens semânticos (surface/onSurface/accent/positive/critical), zero hex em widget; motion 150ms micro / 250ms navegação, respeitar reduce-motion do sistema; animação só com significado (streak, anel) — confete/parallax gratuito proibido.

## 8.4 Padrões de tela
Estados vazios projetados (ilustração do sistema + 1 frase de ação); skeletons na forma do conteúdo (não spinner de tela cheia); erros com direção ("Sem conexão com o Health Connect. Verifique permissões em Ajustes > Apps conectados."), sem desculpas e sem humor; 1 número-herói por tela (HealthScore no Atleta; próximo remédio no Guardião); acessibilidade como piso (AA, foco visível, TalkBack/VoiceOver, escala de texto até 130% sem quebra).

## 8.5 Microcopy pt-BR nativo
Sentence case; verbos que dizem o que acontece ("Gerar PDF", nunca "Enviar"/"OK" em ações com consequência); nomes estáveis do botão ao toast ("Exportar dados" → "Dados exportados"); tom Atleta direto sem gíria forçada, Guardião claro e caloroso sem diminutivos ("remedinho" proibido), B2B técnico neutro; glossário fixo no i18n (pt.json é a fonte).

## 8.6 Checklist por tela (obrigatório antes de codificar)
(1) declarar objetivo da tela + número-herói em 3 linhas; (2) checar contra 8.1; (3) usar só tokens 8.3; (4) após codificar, screenshot em 360×800 e viewport grande, conferindo quebras em palavras longas do pt-BR ("sincronização", "acompanhamento").

---

# PARTE 9 — ETAPAS DE EXECUÇÃO (ROADMAP SEQUENCIAL)

## ETAPA 0 — Auditoria (imediata, antes de qualquer código novo)
Executar Protocolo 3.3 completo. Entregável: matriz 3.2 atualizada + lista de correções.

## ETAPA 1 — Seed de dados realista
Script Node.js: 10–20 usuários **criados via Supabase Auth Admin API** (nunca INSERT direto — de propósito, para validar RLS), 30 dias de `metricas_saude_diarias` com curvas oscilantes (glicose, pressão, HRV), exames EAV em `resultados_exames`, 2–3 anomalias na Caixa Preta, progresso de gamificação variado. Entregável: painel Cloudflare e app com gráficos vivos.

## ETAPA 2 — Correções da auditoria + segurança S1–S8
Implementar o que a Etapa 0 apontou + requisitos S1–S8 (S9 é humano). Renomear a feature do dia 7 para "Projeção de Hábitos e Consistência" e remover cruzamento exames×telemetria do B2C (5.2).

## ETAPA 3 — Homologação no aparelho real (Android + Garmin)
1. `flutter build appbundle --release` com `applicationId` definitivo (nunca com.example), Play App Signing, upload key guardada fora do repositório.
2. Play Console (CPF): conta criada (verificação de identidade pode levar dias — iniciar já), Data Safety, URL de política de privacidade (página no Cloudflare Pages), **Declaração Health Connect protocolada**.
3. Internal Testing: subir AAB, opt-in com o e-mail do fundador, instalar via Play.
4. Ciclo Garmin completo: treino real → Garmin Connect → verificar permissão de **escrita** do Garmin Connect no Health Connect → app lê passos/treino/FC/sono. Validar carga inicial de 30 dias contra o histórico do Garmin Connect.
5. Sync noturno (aparelho na tomada + Wi-Fi) validado no log do Supabase.
6. Pipeline de visão com foto real (prato + visor de pressão): JSON persistido, zero mídia em storage.
7. Teste RLS 2 usuários; screenshot bloqueado nas telas clínicas; revogação de sessão < 60s; rate limit.
8. Passar telas no checklist 8.6.
**Critério de saída:** tudo aprovado + 7 dias de uso próprio sem crash.

## ETAPA 4 — Onda 2 completável (App Atleta BR)
F16 (exportação PDF/CSV), F17 (alerta de tendência), F18 (widget), F19 (válvula alimentar), paywall com copy da Parte 7. Closed Testing (inicia a janela de 14 dias da Play) com 12–20 testadores reais recrutados.

## ETAPA 5 — Pré-lançamento público (bloqueadores não-técnicos)
Política de privacidade + termos de uso finais; RIPD; parecer jurídico ANVISA/LGPD; revisão de segurança humana (S9); análise de CAC em 3 cenários; validação primária (20 nutricionistas + 20 usuários). Monitorar gatilho de CNPJ.

## ETAPA 6 — Produção Android + preparação iOS
Promoção a produção na Play (após a janela de teste fechado). Conta Apple Developer (US$ 99), TestFlight, adaptações iOS (HealthKit já mapeado no pacote health; snapshot ofuscada; permissões).

## ETAPA 7 — Onda 3 (Guardião) e ETAPA 8 — Onda 4 (B2B)
Guardião: perfil exames_puro, linha do tempo, medicamentos, Modo Cuidador (F20), relatórios sazonais (F23). B2B: 2FA (F25), logs_acesso ativos, prescrição (F26), Garmin Training API em produção (verificar aprovação do programa Garmin — iniciar cadastro já), deep links WhatsApp (F27). **Meta comercial: primeiros 10 nutricionistas pagantes.**

## FASE 3 — ⛔ EM HOLD (Parte 4.1).

---

# PARTE 10 — GUIA DE EXECUÇÃO COM CLAUDE CODE (FERRAMENTA ADOTADA)

## 10.1 Decisão de ferramenta
O desenvolvimento é executado no **Claude Code** (terminal ou app desktop; docs: https://docs.claude.com/en/docs/claude-code/overview). O planejamento/geração de prompts pode ser feito em qualquer chat de fronteira, mas os prompts devem ser escritos **para o Claude Code executar**.

## 10.2 Regra de seleção de modelo (custo-benefício)
Ao gerar qualquer prompt de desenvolvimento, **informe no cabeçalho do prompt o modelo recomendado**, seguindo esta política:
- **Padrão (melhor custo-benefício): Claude Sonnet** (linha 4.6 na data deste documento) — implementação de telas, CRUD, integrações documentadas, testes, refactors médios. Deve cobrir ~80% das tarefas.
- **Tarefas triviais: Claude Haiku** (linha 4.5) — renomeações, ajustes de copy/i18n, formatação, scripts simples.
- **Tarefas críticas: modelo topo de linha vigente (Opus/superior)** — desenho/revisão de políticas RLS, pipeline de segurança (tokens, biometria, RAM volátil), OAuth 1.0a da Garmin, decisões de arquitetura. Justifica o custo maior porque erro aqui é caro.
- Verificar os modelos disponíveis na data com o comando `/model` dentro do Claude Code e em https://docs.claude.com (nomes e linhas evoluem).
- Economia adicional: manter sessões curtas por tarefa (contexto enxuto = menos tokens), usar `/clear` entre tarefas não relacionadas e apontar arquivos específicos em vez de pedir varreduras do repositório inteiro.

## 10.3 Template de prompt para o Claude Code (usar sempre)
```
[MODELO RECOMENDADO: Sonnet | Haiku | Topo de linha — conforme 10.2]
[CONTEXTO]: Cole a Parte 0 deste documento + as seções relevantes à tarefa.
[TAREFA]: Objetivo único e claro (1 tarefa por sessão).
[ARQUIVOS]: Caminhos exatos a criar/alterar.
[RESTRIÇÕES]: Itens EM HOLD intocáveis; segurança Parte 6; UX Parte 8; server-side por padrão; sem segredos em código; sem force push.
[CRITÉRIO DE ACEITE]: Como o fundador (não-desenvolvedor) testa o resultado, passo a passo, em linguagem simples.
[ENTREGÁVEL]: Código + explicação simples do que foi feito + comando de commit em branch própria + instrução de PR.
```

## 10.4 Ritual de trabalho do fundador (não-desenvolvedor)
1 tarefa por sessão → Claude Code implementa e explica → fundador testa pelo critério de aceite → commit/PR → merge na main protegida. Se algo quebrar: `git revert` (nunca force push). Dúvida técnica: pedir explicação em linguagem simples antes de aprovar.

---

# PARTE 11 — REGISTRO DE DECISÕES (LOG IMUTÁVEL)

| Data | Decisão | Motivo |
|---|---|---|
| Jul/2026 | Fase 3 (score seguradoras) EM HOLD | Políticas HealthKit/Health Connect + LGPD + cálculo no cliente |
| Jul/2026 | "Custo zero" → "custo mínimo controlado" | Free tiers incompatíveis com dados de saúde (treinamento de IA, sem SLA) |
| Jul/2026 | Gemini somente API paga | LGPD art. 11 — free tier usa dados para treino |
| Jul/2026 | "Anonimizado" → "pseudonimizado" | LGPD: dado vinculável é dado pessoal pleno |
| Jul/2026 | Cenoura do dia 7 = "Projeção de Hábitos e Consistência" (sem exames no B2C) | RDC 657/2022 — finalidade define SaMD |
| Jul/2026 | B2B (Fase 2) = prioridade comercial; B2C = engajamento/aquisição | CAC B2C imprevisível; canal B2B identificável |
| Jul/2026 | Regra server-side para toda lógica sensível | Cliente é manipulável por engenharia reversa |
| Jul/2026 | Ranking público de localidade só com N ≥ 30 | Risco de reidentificação em cidades pequenas |
| Jul/2026 | Operação em CPF com gatilho de CNPJ (50 assinantes OU campanha pública) | Responsabilidade ilimitada + carnê-leão vs Simples |
| Jul/2026 | Teste Android via Play Internal Testing antes de qualquer outra loja | Fundador tem Android + Garmin; custo US$ 25 |
| Jul/2026 | Claude Code como executor; Sonnet como modelo padrão custo-benefício | Parte 10 |
| Jul/2026 | Novas features aprovadas: F16–F20 | Valor LGPD/retenção/persona compradora |

---

*Fim do Documento Mestre v3.0 — cole este arquivo integralmente em qualquer nova sessão de IA para continuidade total do projeto. Atualize a matriz da Parte 3.2 e o log da Parte 11 a cada marco concluído.*

auditoria etapa 0 data 12/07/2026

Rebaixe F10, F03, F06, F08, F09 e F21 de ✅ para ⚠️ (Implementação parcial/desconectada).

Adicione ao Log (Parte 11): "Auditoria revelou desconexão no roteamento e falta das Edge Functions do Gemini. E-mails requerem criptografia."

Parte 11 (Log): Registre: "Etapa 0.5 concluída. Rotas religadas com adição da ProfileSelectionPage. Tabelas órfãs removidas. Lógica do Modo Recuperação (F21) movida para stub no servidor."

Parte 3.2 (Matriz): Mantenha o F21 como ⚠️ (pois agora é um stub HTTP 501, aguardando a lógica real).

Data	Decisão	Motivo
12/Jul/2026	Etapa 1: Criptografia de e-mail Client-Side (em perfis_usuarios)	Conformidade LGPD sem onerar o BD com gestão de chaves; reaproveitamento do CryptoStorageService.
12/Jul/2026	Etapa 1: Algoritmo Server-Side do Trial (F21) atrelado ao auth.users.created_at	Prevenção de fraude de data via manipulação no cliente; lógica 100% no servidor garantida.
---

Título:
Etapa 0.5/1: liga o roteador, remove tabelas órfãs, cifra e-mail e implementa Modo Recuperação real

Descrição:
## Resumo
- Liga o AppRouter aos ecrãs reais (Login/Cadastro/Dashboard), antes apontando para rascunhos; adiciona ProfileSelectionPage para a primeira escolha de perfil.
- Remove as tabelas órfãs `metricas_saude` e `ciclo_menstrual` (migração já aplicada em produção via `supabase db push`).
- Cifra `perfis_usuarios.email` com AES-256-GCM (mesmo padrão de nome/telefone), em vez de introduzir pgsodium/pgcrypto no servidor.
- Implementa o cálculo real da Esteira dos 14 Dias / Modo Recuperação na Edge Function `calculate-recovery-mode` (antes um stub 501), com a data de início do trial semeada a partir de `auth.users.created_at` — nunca do cliente. Nova tabela `esteira_trial_estado` (já aplicada), com RLS só de leitura.

## Teste realizado
- `flutter analyze`: sem problemas
- `flutter test`: 55 testes, todos a passar
- `deno test` (calculate-recovery-mode): 7 testes / 16 cenários, todos a passar
- Migrações aplicadas e verificadas em produção via `supabase migration list`

🤖 Gerado com Claude Code

Fica só a abrir o link, colar isto e clicar em "Create pull request" — não fiz o merge nem toquei na main, como combinado.