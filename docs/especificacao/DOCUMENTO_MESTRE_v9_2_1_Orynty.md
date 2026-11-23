# DOCUMENTO MESTRE v9.2.1 — ORYNTY
## Plataforma de Saúde Preventiva com IA · Ecossistema Unificado B2C/B2B (Single-Backend / Multi-App)
### Marco: R24 encerrado · Motor de Descobertas sequenciado e quebrado em etapas verificáveis
### Emenda v9.2.1: postura de segurança das RPCs do Motor e fronteira declarada do híbrido

**Data:** 16 de Novembro de 2026 (emenda do mesmo dia)
**Status:** FONTE ÚNICA DE VERDADE E AUTOSSUFICIENTE. Consolida e substitui integralmente o DOCUMENTO MESTRE v9.1, incorporando: o **encerramento do R24** (billing do Gemini ligado em 16/Nov, após 84 dias), a **redefinição do R6** de rotação para migração de chaves com prazo de terceiro, as **oito tarefas de 01 a 09/Nov** (relatórios 102 a 109), a **confirmação do horário de refeição**, a decisão de construir o **Motor de Descobertas como RPC** e a **quebra do N41 em quatro etapas independentemente verificáveis**. Qualquer IA que receba este arquivo deve conseguir assumir o projeto sem contexto adicional.
**Precedência:** v9.2.1 > v9.2 > v9.1 > v9.0 > v8.0 > v7.0 > anteriores.

> **EMENDA v9.2.1 — 16/Nov, mesmo dia da consolidação.** Origem: segunda opinião pedida sobre a decisão 88, que o próprio consultor havia marcado como reversível. A segunda opinião propôs arquitetura híbrida (RPC = núcleo analítico, Edge Function = orquestração) e **acertou um ponto que o v9.2 não cobria: a postura de segurança das funções**. O v9.2 moveu o núcleo analítico para dentro do Postgres sem escrever uma linha sobre `SECURITY INVOKER`/`DEFINER`, `search_path` ou `EXECUTE` — a regra 20 do projeto é de **tabela**, não de função. A emenda registra três coisas e **não muda a fila**: a **decisão 97** (postura de segurança de RPC, obrigatória em toda tarefa do Motor), a **decisão 98** (o híbrido é o destino declarado, com a fronteira em notificação e integração externa, não em "orquestração" genérica) e uma **nota de desenho em D.4** sobre a propriedade que o Motor só-RPC tem e o híbrido perde. Mais o **antipadrão 13**, contra o consultor. Quem está com o v9.2 sem a marca "(emenda do mesmo dia)" no cabeçalho está com a versão anterior a estes três registros.

**Nome oficial do produto:** **Orynty** (definido em 25/Out/2026, decisão 61). O `applicationId` segue `br.com.atleta.app` — ver R10.

**Documentos-anexo vigentes:**
- **`ORYNTY_CATALOGO_DESCOBERTAS_v2_1.md`** — os 277 templates de descoberta, em **36 famílias de cálculo**. **Subordinado a este Mestre**: não cria regra, nível, permissão, gate nem finalidade; onde conflitar, o Mestre prevalece. Sincronizado com esta versão.
- `docs/motor_metabolico.txt` — especificação técnica do Motor Metabólico e da Anamnese. **Subordinado a este Mestre** (ver Parte 2.8, que resolve a contradição interna daquele documento).
- PLANO DE MARCA, MARKETING E LANÇAMENTO v1.0 (22/Jul/2026) — não revisado neste marco. Em produto/técnica este Mestre prevalece; em marketing, o Plano. *Pendências conhecidas:* o Plano trata o motor viral (F43) como construído — ele **não** está; e o Plano antecede a definição do nome Orynty.

**Documentos históricos (consulta apenas):** Mestre v3.0/v5.0/v6.0/v7.0/v8.0/v9.0/v9.1; Adendos v4.0/v5.1/v5.2/v6.1; `ORYNTY_CATALOGO_TEMPLATES_UAU_CONTINUOUS_RF_ET_005.md` v1.2 (**descartado** — ver Parte D.8); `ORYNTY_CATALOGO_DESCOBERTAS_v2_0.md` (substituído pelo v2.1).

---

# PARTE 0 — INSTRUÇÕES DE OPERAÇÃO PARA O ASSISTENTE DE IA

1. **NUNCA implemente, expanda ou corrija** itens EM HOLD (Parte 4 e Parte BL).
2. **Antes de escrever código novo**, verifique o estado real (Parte 2) e a Matriz (Parte 3), e **investigue o código real antes de presumir**. Padrão: auditar → reportar o achado → agir. "Declarado-implementado" ≠ verificado por humano.
3. **Segurança (Parte 6) é bloqueador de release.**
4. **UX (Parte 8) prevalece** sobre qualquer default visual.
5. **Arquitetura inegociável:** toda lógica sensível (pontos, streaks, scores, elegibilidade, trial, prescrição, criação de vínculos, cálculo metabólico, validação de leituras de OCR, **seleção e renderização de descobertas**) é **server-side**. O cliente apenas exibe.
6. **Dados inegociável:** nenhum dado real de usuário em IA de tier gratuito ou com cláusula de treinamento. Zero mídia persistida (pipeline RAM volátil). **Nenhuma foto é persistida** — ver decisão 51 e sua emenda (decisão 62).
7. **Git:** proibido force push; main protegida; PRs obrigatórios; zero segredos/chaves/IDs em código.
8. **Perfil do fundador:** não-desenvolvedor, solo, IA para 100% do código. Explicar em linguagem simples, uma tarefa por vez, sempre dizer como testar.
9. **Ferramenta de execução:** Claude Code (Parte 10: política de modelos, template de prompt, antipadrões).
10. **Toda migração** = RLS habilitado + policy vinculada a `auth.uid()`/vínculo + **GRANT explícito**.
11. **Idioma:** pt-BR. i18n em pt/en/es (pt é a fonte).
12. **Não gerar novos documentos** exceto quando o fundador pedir ("consolida"/"gera").
13. **Relatório de fim de tarefa obrigatório** (ver 17).
14. **"Validação = completa funcionalmente, crua visualmente."**
15. **Erro de app nunca se disfarça de erro de servidor.**
16. **Anti-hardcode:** valores que mudam comportamento vêm de secret ou tabela configurável. Casos vigentes: `GEMINI_MODEL_NAME`, `EMBEDDING_MODEL_NAME`, threshold da busca semântica, faixas de validação, lista de papéis, PAL, parâmetros de macro e de déficit, **limiares práticos de publicação de descoberta, faixas de horário, tamanhos mínimos de grupo, faixas de referência de WHtR**. *Exceção registrada e aceita (30/Ago):* os 5 tamanhos de bebida em `confirmacao_prato_page.dart` são constantes nomeadas — são escolha visível do usuário, não parâmetro oculto.
17. **Governança de log:** ao fim de cada tarefa, `/docs/log_dev/AAAAMMDD_SSSS.md` + `INDICE.md` append-only. **Anti-alucinação:** registra só o que foi feito **e verificado**; `pronto-para-teste` ≠ `testado`.
18. **Avaliação de merge ao fim de cada bloco** — sugere, nunca mescla sem autorização.
19. **Sincronização dos 3 prompts** (consultor, Gemini, Claude Code) a cada mudança de comportamento/prioridade.
20. **Modelo de embedding:** seed e runtime no mesmo modelo, via secret.
21. **Performance como critério de GERAÇÃO**, não só de correção.
22. **Observabilidade obrigatória em toda Edge Function:** log de conclusão (duração, status, tamanho do corpo) e `X-Request-Id` ecoado. **Corolário:** ausência de log não é evidência de ausência de execução — confirmar no código que o log existe antes de concluir por ele.
23. **Nunca arbitrar dado em silêncio — falhar visível.** Dado que o sistema não consegue resolver volta marcado como não resolvido e a decisão vai ao usuário. Nenhum resumo declara sucesso total havendo item arbitrado.
24. **Teste que documenta bug não vira especificação.** Antes de "atualizar um teste desatualizado", declarar explicitamente por que o comportamento atual é o correto.
25. **Nenhuma tela se fecha sozinha em silêncio.** `pushReplacement` proibido em fluxo dependente de rede.
26. **Dado gerado por IA em massa exige amostragem humana** antes de alimentar cálculo.
27. **Comentário e documentação de arquivo são parte do código.** Quando o comportamento muda, o cabeçalho, os comentários e os avisos de tela que o descrevem são atualizados **na mesma tarefa**. **Origem:** o cabeçalho de `resultado_motor_metabolico_page.dart` afirmava que o app "nunca pré-calcula nem sugere um valor" enquanto, 300 linhas abaixo no mesmo arquivo, o seletor de protocolos preenchia três campos.

## Regra 28 — reescrita nesta consolidação

> **28 — Inteligência pessoal baseada em evidências observadas.**
>
> Sobre dado de um único usuário é **proibido**:
> 1. publicar número que não foi observado — coeficiente de correlação, inclinação de regressão, valor-p, significância estatística, projeção futura;
> 2. afirmar ou insinuar causa, benefício, prejuízo ou relação clínica entre dimensões, inclusive por insinuação ("coincidiu com", "por isso", "resultado de", "graças a");
> 3. escolher qual comparação publicar em função da maior diferença encontrada;
> 4. tratar ausência de registro como ausência de comportamento;
> 5. apresentar estimativa ou dado de qualidade insuficiente como fato confirmado.
>
> É **permitido** descrever o que foi observado e comparar grupos de dias ou períodos observados, desde que **simultaneamente**:
> 1. o cruzamento conste da biblioteca `perguntas_analiticas` — versionada e aprovada **antes** da análise;
> 2. cada grupo atinja o tamanho mínimo declarado nessa tabela;
> 3. a dispersão de cada grupo seja exibida junto da diferença, e a diferença **não** seja publicada quando ficar abaixo do limiar prático do indicador;
> 4. a frase descreva os grupos, nunca o vínculo.
>
> **Governança:** alterar a biblioteca exige **revisor nomeado** e registro no log. A regra vale igualmente para os dois perfis — integridade analítica não muda com o papel do usuário. O que muda é a camada de **interpretação** permitida.
>
> **Nota de enquadramento:** esta é uma regra de **integridade analítica**. Ela **não** determina o enquadramento regulatório, que depende da **finalidade declarada de cada módulo** (Parte 5.0). Um texto sem correlação estatística ainda pode ter finalidade clínica.

**Por que foi reescrita.** A redação anterior proibia uma *técnica* (coeficiente, regressão, tendência) quando o que precisava ser protegido eram dois riscos distintos com fronteiras distintas: **invalidez do número** (com 30 dias de uma pessoa, um coeficiente é ruído; e testar 40 cruzamentos e publicar o maior garante achado falso) e **ato clínico** (afirmar que X causou Y é inferência individualizada). Separados, o limite real aparece: a regra proíbe **produzir número não observado** e **afirmar vínculo** — não proíbe comparar grupos observados. O que de fato travava os N4 era a **múltipla comparação**, e isso tem conserto por governança, não por proibição de estatística. Ver Parte D.4.

**O que não muda:** a linha de três camadas (decisões 43/44), a regra 29, o R25, e as duas finalidades declaradas. A Regra 28 revista libera **método**; ela não libera **prescrição**.

## Regras novas desta consolidação (30–31)

30. **Variável de template não carrega sentido (01/Nov).** Nenhuma variável de frase pode conter o verbo, o juízo ou a descrição do achado. Variável carrega **número, data, nome de métrica ou rótulo de grupo** — nunca significado. **Origem:** no catálogo v1.2, `{descricao_padrao}`, `{estado_mudanca}`, `{descricao_variacao_peso}`, `{efeito}` e `{metodo}` carregavam o sentido inteiro de ~60 templates sem que nenhum vocabulário fechado existisse para preenchê-los. `HV-C3-001` a `HV-C3-038` eram 38 títulos diferentes sobre **um corpo de texto idêntico**.
31. **Frase sobre o registro é SUPORTE, não descoberta (01/Nov).** Quando o sujeito da frase é o **registro** e não o **comportamento** — quantos dias tiveram dado, quando o usuário anota água, em que dia ele se pesa —, a frase é qualidade de dado e vive na tela de qualidade, nunca no cartão de descoberta. **Origem:** ~370 das 2.178 entradas do catálogo v1.2 eram cobertura vendida como achado. É a regra 23 na camada editorial: o produto diz **onde não sabe**, mas não chama isso de descoberta.

---

# PARTE 1 — VISÃO DE NEGÓCIO E ESTRATÉGIA

## 1.1 Problema
Fragmentação das healthtechs, baixa retenção crônica de diários manuais, perda do histórico clínico de longo prazo pelo paciente.

## 1.2 Solução
Backend único (Supabase) + múltiplas interfaces por nicho: **App Atleta** (B2C gamificado), **App Guardião Clínico** (B2C sênior/crônico/feminino), **Painel Web B2B** (nutricionistas, treinadores, médicos). Um único app mobile com perfil dinâmico (`perfil_uso`).

**Frase-norte de produto (decisão 63):** *"O Orynty não tenta adivinhar o que acontece com você. Ele encontra, nos seus próprios dados, coisas que você ainda não tinha percebido."*

## 1.3 Decisão estratégica central
**O B2B é o coração comercial.** O B2C é engajamento e canal de aquisição.

## 1.4 Beachhead
Nutricionistas esportivos + treinadores de corrida e seus pacientes com Garmin. **Beachhead de marketing, leque técnico aberto.**

## 1.5 Mercado
Global de apps saúde/fitness US$ 13,8–14,6 bi → > US$ 33 bi (CAGR > 13,5%). **Distinção regulatória crítica:** InsideTracker, Function Health e Superpower são testadores (CLIA/FDA); nós **não** — o usuário já possui o exame, nós lemos e organizamos.

## 1.6 Fosso defensável — **REVISADO EM 01/NOV**

**Não é diferencial (o mercado já entrega):**
- **Cruzamento de calorias consumidas × gastas.** MyFitnessPal e Garmin têm parceria oficial desde 2015: saldo do dia, ajuste de calorias, e as calorias consumidas num widget do próprio Garmin Connect. **Paridade competitiva**, não fosso.
- Dado de wearable dentro do painel profissional. O Nutrium tem.
- Plano alimentar digital, app do paciente, evolução de medidas, aderência à meta. Commodity.

**É diferencial verificado:**
1. **Telemetria contínua, não só sessões de treino.** O Nutrium sincroniza atividades mas **exclui explicitamente passos diários e caminhadas de menos de 15 minutos**; o VibeFit registra sono e água como marcação manual de hábito. Passos, andares, sono por estágio, FC de repouso, FC máxima e composição corporal da balança não existem no B2B brasileiro.
2. **Gasto medido em vez de estimado.** O Nutrium calcula calorias pela própria base de exercícios; nós lemos do relógio.
3. **Declarado × medido.** Confrontar a rotina autorrelatada na anamnese com os treinos reais do wearable. Não encontrado em nenhum produto, brasileiro ou global. **Template `N2-FOS-001`.**
4. **Saldo acumulado × peso real.** Audita o próprio sistema. Requer as três pontas; ninguém reúne. **Template `N2-FOS-002`.**
5. **Cruzamentos de sono com nutrição** (última refeição × início do sono; açúcares × sono). Exige sono granular, que nenhum app de nutrição brasileiro tem.
6. **Qualidade do dado exposta ao usuário** (família QLD na Parte W; família SUPORTE no catálogo de descobertas). O líder global acumula dupla contagem no saldo há uma década sem avisar ninguém.
7. **Captura por foto de aparelho analógico** (glicosímetro/pressão do sênior). Sem concorrente.
8. **Brasil-first** (PDF de labs locais, idioma, preço, base alimentar nacional) e **base longitudinal** que aumenta custo de troca com o tempo.
9. **(NOVO — decisão 64) Descobertas pessoais com procedência citável.** Não é o número: é o número **com o estudo e a comparação populacional ao lado**. Concorrente mostra "sua janela alimentar é de 14h20"; o Orynty mostra isso e, no contexto, que no estudo que descreveu o padrão a maioria das pessoas também passava de 15 horas. **Isso é outra categoria de produto**, e é o que torna o Painel Web vendável a um profissional. Base: a camada de índices publicados da Parte D.6.
10. **(NOVO — decisão 64) A biblioteca governada de perguntas analíticas, os templates versionados e os critérios de qualidade** tornam-se, com o tempo, parte do ativo tecnológico — não só do produto.

**Item removido do fosso no v9.0 e mantido fora:** o loop "profissional→prescrição→relógio Garmin". A Edge Function `garmin-gateway` **não está deployada**.

## 1.7 Concorrência (varredura de 12/Out, mantida)

**Brasil — B2B:** **Dietbox** (líder, 79% de lembrança, faturamento acima de R$ 8 mi; planos, suplementos, app do paciente, gestão de consultório; **nenhuma integração de wearable**) · **Nutrium** (120 mil profissionais; sincroniza Google Fit/Apple Health **exceto passos diários e caminhadas <15 min**; energia gasta calculada pela base própria) · **Nutrio** (plano, gráficos, exames; sem wearable) · **VibeFit** (cinco pilares, bases IBGE/TBCA/TACO/USDA, hábitos manuais; *o uso da TBCA confirma que a licença é obtível comercialmente*) · **Health Compass** — não encontrado, removido até confirmação.

**Global — B2C:** **MyFitnessPal + Garmin** (saldo desde 2015; **dupla contagem endêmica documentada em fóruns há anos**, mitigação exige o usuário descobrir sozinho "permitir ajustes negativos"; fuso por CEP, que quebra para não-americanos) · **Oura** (metabólico desde maio/2025, foto de refeição + Dexcom) · **WHOOP** (Journal correlaciona comportamento com Recuperação; sem nutrição nativa) · **Cronometer** (Garmin, mesmos problemas de agregação).

**Implicação estratégica:** o cartão de visita **não é** o saldo energético. São **declarado × medido** e **saldo acumulado × peso real** — e agora, com a camada de descobertas, **a dispersão**: o que o usuário não tem como saber de si sem alguém calcular.

## 1.8 Lacunas não-técnicas
CAC (orgânico-primeiro; pago só se estagnar após 3 meses); resposta competitiva (Samsung/Google podem embutir foto grátis — fosso real = base longitudinal + B2B + descobertas); validação primária (20 nutricionistas + 20 usuários antes do lançamento público).

## 1.9 Unit economics
B2C anual R$ 179,90 ≈ R$ 142 líquidos/ano. **Teto de CAC = R$ 142; meta ≤ R$ 47.** B2B margem > 80%. Conversão trial→pago 1–2,5%; retenção D30 de mercado 5–10%.

## 1.10 Custos reais
Gemini API (**R24 encerrado em 16/Nov — billing ligado, Tier 1**; custo medido na ordem de **US$ 3/mês** para um beta de 10 amigos, ver Parte 12.1); Supabase Pro (~US$ 25/mês); Play Console (US$ 25); Apple Developer (US$ 99/ano); CNPJ + contador (R$ 200–400/mês); **parecer de enquadramento das duas finalidades** (R$ 5–15 mil — ver Parte 5.0); revisão de segurança sênior (R$ 2–5 mil); domínio; marca INPI **sob o nome Orynty**.

## 1.11 Situação jurídico-fiscal
CPF na fase de teste (carnê-leão). **MEI não permitido** → ME/Simples. **Gatilho de CNPJ (50 assinantes OU campanha pública) é mandatório.** LGPD desde o 1º usuário real.

## 1.12 Preços
**B2B Essencial** (até 15 pacientes) R$ 97/mês; **B2B Performance** (com Garmin, até 40) R$ 167/mês; **Fundadores** 10–20 profissionais, vitalício ~R$ 67. **B2C Anual** R$ 179,90/ano; **Mensal** R$ 34,90. Paciente via profissional não paga e não recebe gatilho de venda. Terceira linha: créditos de Análise Complexa N3.

## 1.13 Definição de cliente final
- **Cliente avulso:** sem vínculo. Usa **apenas o app**. Meta no enquadramento de **bem-estar**, **registrada por ele mesmo**; revisa 1×/mês. Sujeito à trava clínica. **O sistema informa, não prescreve** (Parte 5.2).
- **Cliente profissional:** vinculado. **Não edita a própria meta.** A relação comercial é com o profissional. Ao desvincular, passa à regra do avulso com histórico preservado.

---

# PARTE 2 — ESTADO REAL DO PROJETO (16/Nov/2026)

> Sexta consolidação, mesma regra que sobreviveu a todas: **"declarado-implementado" ≠ "verificado por humano"**. A seção 2.6 é a que governa o risco.

## 2.1 Legenda
**[PRONTO/testado]** verificado pelo fundador em aparelho · **[PRONTO/nv]** relatado, não verificado · **[EM TESTE]** corrigido, confirmação parcial · **[NÃO EXISTE]** · **[CORRIGIR]** existe e fere uma regra.

## 2.2 Marco alcançado

**O teste solo foi concluído com sucesso em 12/Out** e, entre 12 e 25/Out, **o fundador executou testes de campo** que produziram 12 tarefas em 4 dias com análises de causa raiz de boa qualidade. O produto roda. O portão seguinte continua sendo o **beta de amigos** — dado real de terceiros.

**O que os testes de campo mudaram:** o fundador sentiu falta de funcionalidades que geram valor percebido, e isso reposicionou a prioridade. Ver Parte 9.1.

**O marco desta versão: o R24 foi encerrado em 16/Nov.** O billing do Gemini foi ligado, o projeto passou a Tier 1, e o risco crítico mais antigo do projeto — aberto desde 24/Ago, **84 dias** — deixou de existir. Com ele, **o beta de amigos deixa de estar bloqueado por decisão** e passa a estar bloqueado por três itens do fundador (R6, R33, higiene do Bloco 4) e por código.

**Nota honesta de calibração registrada:** o custo medido do beta é da ordem de **US$ 3/mês**, menor que a conta do Supabase. A decisão que ficou 84 dias parada era de valor menor que a infraestrutura que já se pagava. Fica como lição de processo: **decisão barata parada é mais caro que decisão errada tomada**.

## 2.2.1 As oito tarefas de 01 a 09/Nov (relatórios 102 a 109)

Entregues após o v9.1, todas mescladas em `main` (confirmado pelo fundador em 16/Nov):

- **102, 103** — unificação da régua de validade da anamnese: três telas calculavam "próxima revisão" por conta própria, ignorando `anamneses.data_validade`; agora todas usam a mesma `AnamneseValidadeStatus`. Mais o fix de duplo envio (`if (_enviando) return;` **síncrono**, antes de qualquer `setState`) e a reatividade do histórico de peso.
- **104, 105** — correlação meta↔anamnese. A proposta por **janela de tempo** foi rejeitada pelo fundador ("frágil, viola boas práticas de modelagem relacional") e substituída por **FK direta**: `objetivos_alimentares.anamnese_id`, com `validar_e_salvar_meta` gravando a FK no próprio INSERT e backfill retroativo documentado como gap honesto.
- **106** — a trava de 30 dias da meta passou a usar a FK: anamnese nova sempre libera, mesmo dentro dos 30 dias. Verificado de ponta a ponta contra o banco real.
- **107** — máscara HH:mm compartilhada; removido o botão "usar este valor em Calorias"; `AnamneseDetalhesPage` passou a **ler** `anamneses.resultado_motor_v1`, que já era persistido desde setembro; removida a trava client-side de carência que divergia do servidor.
- **108** — protocolos **MACRO-004 e 005** expostos na UI (já eram calculados pela RPC desde setembro) e kcal por refeição renderizada no histórico. Duas premissas da tarefa foram auditadas e corrigidas antes de codar.
- **109** — **Fase 1 de escalabilidade**: auditoria das 54 migrations levantando toda coluna usada em RLS e toda FK; 17 colunas sem índice próprio cobertas (`CREATE INDEX IF NOT EXISTS`, idempotente). Roadmap das Fases 2 (cache de borda) e 3 (transaction pooling, read replicas) registrado.

**Leitura estratégica, sem rodeio:** as oito tarefas são sólidas e bem documentadas, e **nenhuma delas era o Motor de Descobertas**, definido como prioridade máxima em 01/Nov. É a quarta vez que o padrão do R19 se manifesta. A Parte 9.1 desta versão responde a isso quebrando o N41 em etapas pequenas o suficiente para começarem.

**Pendência de registro:** os relatórios 102 a 109 **não anotam a mesclagem** — o último registro explícito de merge no log é de 23/Set. O fundador confirmou em 16/Nov que todos foram feitos. Como a Parte 2.6 depende da fidelidade do log, vale fechar essa lacuna: **o relatório de fim de tarefa registra o merge, não só a branch.**

## 2.3 O que está construído

**Fases 0 a 4:** fundação de identidade com RBAC dinâmico M:N, telemetria completa (persistência, Carga Inicial de 30 dias, hierarquia de fontes, sono por estágio, 99 tipos de atividade, fuso resolvido por ponto), motor de cálculo, registro de refeição por 4 métodos, favoritas, hidratação, aparelho por foto, busca semântica com índice HNSW.

**Integridade do dado de porção (30–31/Ago) — o risco nº1 do v8.0, encerrado:** `encontrarMedida` parou de arbitrar; item sem medida volta como `ItemPratoNaoReconhecido`; os 6 testes que codificavam o chute foram reescritos citando a Regra 24; UI de resolução manual sem bloquear o resto do prato; **amostragem de 50 das 1.056 medidas — 0% de erro claro, 4% questionável**; `FATORES_UNIDADE_BRUTA` corrigiu o bug de escala (erro medido entre 25× e 120×).

**Catálogo de alimentos (02–08/Set):** 404 falhas de autoconsistência corrigidas; **Regra Anti-Sequestro** (alias de uma palavra só resolve apenas por match exato); **falha visível em empate**; curadoria em 27 linhas.

**Motor Metabólico V1 e Anamnese de 16 blocos (15–27/Set)** — ver 2.4.

**UI de câmera unificada (15/Set):** seletor Prato/Rótulo, troca por `setState` sem reinicializar a câmera; resolução `medium` com custo **medido** em +16 tokens (~1,5%).

**Testes de campo (12–25/Out):** 12 tarefas.

**01 a 09/Nov:** 8 tarefas (ver 2.2.1). **Nenhuma branch aberta, nenhum merge pendente** — confirmado pelo fundador em 16/Nov.

## 2.4 O Motor Metabólico e a Anamnese — entrega grande, escopo não registrado

Entre 15 e 27/Set, **dez das dezoito tarefas** foram dirigidas por `docs/motor_metabolico.txt`, documento de 3.512 linhas que não existia no v8.0 e nunca passou por consolidação.

**Entregue:** SSOT (peso e altura saíram de `perfis_usuarios` e passaram a snapshot de cada versão da anamnese) · `calcular_motor_metabolico_v1` (TMB-001 Mifflin-St Jeor, TDEE por dia da semana por Decomposição **ou** PAL, **nunca somadas**) · MACRO-001 a 005 com validação matemática (soma das kcal = energia-alvo, tolerância 2 kcal) · tabela de déficit multicritério DEFICIT-002 com os 6 fatores · score de qualidade · Anamnese Blocos 1–16 com 5 blocos condicionais e versionamento · anamnese inteligente (`iniciar_rascunho_anamnese`, `processar_medias_smartwatch`, validade com bloqueio aos 40 dias) · Painel Web com Anamnese Profissional, histórico de versões, metas por dia da semana, card do Motor V1, validação ao vivo do MACRO-005.

**O que isso significou:** o **Módulo Clínico**, que o v8.0 colocava em BL.1, entrou pela porta lateral. O trabalho é sólido, verificado ao vivo e matematicamente conferido — mas consumiu dez tarefas, a Fase 5 ficou parada, e nada passou por registro de decisão. Formalizado na decisão 42.

## 2.5 Correções de fatos acumuladas

| # | O que se afirmava | Realidade | Consequência |
|---|---|---|---|
| **C17** | Cruzamento telemetria×nutrição é o que os concorrentes não têm | MyFitnessPal + Garmin entregam saldo desde 2015 | O saldo é paridade (decisão 46) |
| **C18** | Loop Garmin é item do fosso | `garmin-gateway` **não deployada** | Removido do fosso (decisão 48) |
| **C19** | Health Compass é concorrente | Não encontrado na varredura | Removido (decisão 49) |
| **C20** | Peso e altura vivem em `perfis_usuarios` | Colunas removidas em 16/Set | Parte 3.4 reescrita |
| **C21** | Circunferências não são coletadas | **Coletadas desde 18/Set** (Bloco 3) | ANT-007 destravado; **e o WHtR fica a uma divisão de distância** (decisão 67) |
| **C22** | "11 testes quebrados" em `confirmacao_prato_page` | Bug real de produção (`Flexible` dentro de `Wrap`), corrigido em 21/Ago | Reafirmado |
| **C23** | A fila do v8.0 é a vigente | O teste solo já aconteceu | Parte 9 reescrita no v9.0 |
| **C24 (NOVO)** | A decisão 51 proíbe "armazenamento de fotos de qualquer natureza" | A redação confundiu **persistir** com **exibir**. O preview em memória (`Image.memory`) não fere o Zero Storage | **Emenda na decisão 62** |
| **C25 (NOVO)** | O catálogo de insights tinha 2.178 candidatos aproveitáveis | Extração mecânica: **254 esqueletos de frase, 20 cobrindo 82,5%**; só 195 entradas com frase única; **31 sobreviveram** | Catálogo v1.2 descartado; ver Parte D.8 |
| **C26** | A Regra 28 resolvia o enquadramento regulatório das descobertas | A RDC 657/2022 enquadra por **finalidade**, não por técnica. Texto sem correlação ainda pode ter finalidade clínica | **Parte 5.0 — duas finalidades declaradas** |
| **C27 (NOVO)** | O horário da refeição estava confirmado como gravado | O v9.1 registrou "com data e hora" **a partir de afirmação verbal do fundador, sem leitura do arquivo** — exatamente o que a regra de desconfiar do estado declarado existe para impedir. Em 16/Nov o fundador confirmou: **é gravado, no início da refeição** | 24 templates de hora de refeição **viáveis**; 7 de **tipo** de refeição seguem pendentes (N43) |
| **C28 (NOVO)** | O R6 é "rotacionar a Service Role Key" | A Supabase **descontinuou** anon e service_role para o fim de 2026, **deixou de permitir rotação** das legadas, e recomenda **migrar** para `sb_publishable_` / `sb_secret_`. Rotacionar as novas **não** desloga ninguém | **R6 redefinido** (Parte 6, S8) — deixa de ser dívida e passa a ter **prazo de terceiro** |
| **C29 (NOVO)** | A pendência de catalogar os bugs de campo seguia aberta desde 12/Out | Os relatórios 102 a 108 **reportaram e corrigiram** cada bug com RCA no próprio log. Não houve log dedicado, mas o objetivo da regra foi cumprido | Pendência **encerrada** |

## 2.6 Verificado pelo fundador × apenas declarado — **a tabela que governa o risco**

**Verificado em aparelho / em uso real:**
- Teste solo completo (12/Out) e **testes de campo** (12–25/Out e 01–09/Nov), todos sem dashboards e sem descobertas.
- A jornada de renovação da anamnese, inclusive com "time travel" forçando `data_validade` no passado (relatórios 102/103).
- A trava de meta liberando corretamente após anamnese nova, confirmada de ponta a ponta contra o banco real (relatório 106).
- **Que o horário da refeição é gravado no início da refeição** (confirmado pelo fundador em 16/Nov).
- Correção de fuso, treino de força, hidratação, glicosímetro e balança gravando em `coleta_diaria`.
- Os 4 métodos de registro de refeição; fluxo de foto funcionando.
- Que o card de déficit e os chips MACRO **não aparecem** para o objetivo usado pelo fundador — confirmando que são condicionais (2.8).
- Build compilando e rodando após o fix do Kotlin.

**NÃO verificado (declarado apenas):**
- **Painel Web da Anamnese Profissional** — nunca testado pelo fundador. É a frente B2B inteira de 17 a 27/Set. **(R33)**
- **Motor Metabólico V1 de ponta a ponta pelo fundador** — verificado por conferência matemática, não em uso.
- Os blocos condicionais (idoso, atleta, recomposição, diabetes, renal) em uso real.
- A revisão de smartwatch (`RevisaoSmartwatchPage`) e a IA de refeições habituais.
- O gráfico de histórico de peso (`fl_chart`).
- **O fluxo de consentimento de compartilhamento com o profissional** — o fundador afirma que o consentimento de instalação está tratado; o **consentimento nominal, revogável e auditável de compartilhamento** é outro e nunca foi exercido por ninguém. **(R39, NOVO)**
- iOS, em qualquer aspecto.
- **O billing do Gemini em Tier 1** — ligado em 16/Nov, **não verificado em uso**. O teste é barato: três ou quatro registros por foto seguidos (antes, a partir da 21ª chamada do dia o Gemini devolvia 429).

**Bugs pequenos dos testes de campo:** **pendência encerrada** — ver C29.

## 2.7 O que NÃO existe

- **Fase 5 inteira:** `catalogo_widgets` semeado, `widgets_disponibilidade`, os renderizadores, os dashboards, os cruzamentos, o resumo (N23) e o onboarding (N24).
- **Motor de Descobertas inteiro** (Parte D): tabelas, biblioteca de perguntas, limiares práticos, avaliador de gates, seleção, deduplicação, renderização. **Nenhuma linha.**
- **Timestamp de início e fim do sono** — a verificar (N43). O dado **chega** com início e fim do Health Connect; a dúvida é se é **persistido** ou descartado após virar minutos. Decide 22 templates.
- **Tipo da refeição** (café/almoço/jantar) nos quatro métodos de registro — a verificar (N43). Existe nas favoritas; não confirmado no resto. Decide 7 templates.
- **Colunas NOVA e grupo FAO** em `alimentos_referencia` (N39).
- **Fibra e sódio** em `alimentos_referencia` (N30).
- **WHtR** — a circunferência existe desde 18/Set; o índice não é calculado (N38).
- **Migração para as chaves `sb_publishable_` / `sb_secret_`** (N44) — **prazo: fim de 2026**.
- **Tratamento de HTTP 402** no chamador do Gemini (N45) — com o pré-pago, esse erro passou a existir de verdade.
- `garmin-gateway` em produção.
- Motor viral / gamificação (F43).
- Produção separada de homolog (R-E4).
- Desligamento da detecção de anomalia de FC (R25) — **pendência regulatória aberta há quase 3 meses**.
- CI/CD. Mesclar em `main` nunca deployou nada; Edge Function exige `supabase functions deploy` manual.
- Suíte de testes de componente no Painel Web — **zero cobertura automatizada em todo o B2B**.
- Testes de `CameraCaptureView`/`CameraCaptureController`.
- Banner de validade da anamnese na Tela Senior.
- Suporte iOS verificado.

## 2.8 A contradição do `motor_metabolico.txt` e sua resolução

O documento contém **duas especificações incompatíveis** para o usuário sem acompanhamento: as **seções 9, 23 e Meta Energética §5** mandam calcular recomendação energética com déficit por tabela parametrizada; o **ME-005** proíbe exatamente isso.

**As duas foram implementadas.** Em `resultado_motor_metabolico_page.dart`: linha 486 copia `recomendacaoMediaDiaria` (TDEE menos déficit) para o campo Calorias; linha 505 (`_buildProtocoloSelector`) oferece chips MACRO-001/002/003 que preenchem proteína, carboidrato e gordura. Guardas nas linhas 302 e 355: o backend só emite recomendação para `manter_peso`, `perder_peso` e `reduzir_gordura_corporal` — **mas a anamnese oferece os oito objetivos**, então aparece para qualquer usuário que escolha um dos três.

**Resolução (decisões 43/44):** no fluxo **sem acompanhamento profissional**, o card de recomendação é exibido apenas quando a estratégia for `manutencao`; a variante de **déficit** e o **seletor de protocolos MACRO** ficam ocultos. Tudo permanece no Painel Web, onde há responsável técnico. O `buscarSugestaoCalorias()` de `MetaBemEstarPage` devolve **TDEE**, não déficit — permanece.

> **Conclusão da Parte 2.** O núcleo é sólido e o dado é confiável. O que falta é o produto que o usuário vê — e agora ele tem nome e forma: **Fase 5 + Motor de Descobertas**. O risco mudou de natureza duas vezes: era "o dado está errado", passou a "o produto não chega a ninguém", e hoje é **"o produto chega como paridade"** — porque sem descobertas o Orynty é um registro alimentar com relógio, que é exatamente o que o mercado já tem.

---

# PARTE 3 — ARQUITETURA TÉCNICA E MATRIZ DE STATUS

## 3.1 Stack
- **Backend:** Supabase (PostgreSQL + Auth + Edge Functions Deno/TS + Cron). RLS + GRANT explícito. **pgvector** com índice HNSW.
- **Mobile:** Flutter (Feature-First), i18n pt/en/es. Dois módulos distintos e não intercambiáveis: `lib/features/nutricao/` (anamnese e metas, em português) e `lib/features/nutrition/` (registro de refeições, em inglês). Telas secundárias via `Navigator.push` — **`pushReplacement` proibido em fluxo dependente de rede** (regra 25). `fl_chart` para gráficos.
- **Web B2B:** React + TypeScript + Vite, Cloudflare Pages, `recharts`.
- **IA:** Gemini, só pelo servidor. `pratoRefeicao`, texto e áudio no nível LITE; OCR de rótulo em CORE. Fallback automático CORE→LITE. Timeout por tentativa via `AbortController` (visão 22,5s; embedding 15s). **A chave está em free tier — ver R24.**
- **Wearables:** pacote `health` **13.3.1** (não subir — a 13.3.2 quebra `:health:compileDebugKotlin`, ver R32). READ-only. Bucketização pelo fuso real de cada ponto.
- **Garmin:** `garmin-gateway/` existe como código, **não deployada**.
- **Motor de Descobertas (a construir):** server-side, **determinístico, sem chamada de IA**. Ver Parte D e a nota do R24 abaixo.

> **Nota sobre o R24 e as descobertas.** Um motor de descobertas baseado em template renderizado a partir de valor calculado **não consome Gemini**. Isso significa que **o R24 não bloqueia esta frente** — a primeira da fila em mais de 70 dias que não depende daquela decisão parada. O R24 continua bloqueando o caminho da foto, que o beta também precisa.

## 3.2 Legenda
✅ declarado · 🔍 verificado pelo fundador · 🟡 em teste · ⚠️ parcial · 🔲 pendente · ⛔ hold

## 3.3 Matriz (reconciliada 01/Nov)

| # | Funcionalidade | Status | Nota |
|---|---|---|---|
| F01 | Esquema + RLS | 🔍 | RLS em 6 cenários |
| F02 | Caixa Preta | ⚠️ | **Detecção de anomalia de FC ativa (R25) — primeiro passo da finalidade de bem-estar** |
| F03 | Login social + OTP | ⚠️ | Cadastro social não grava perfil (R14) |
| F04 | Keystore/biometria | ⚠️ | Biometria de abertura → BL |
| F05 | Suíte de testes de segurança | ⚠️ | +7 testes de pentest do token |
| F06 | Cadastro adaptativo | ✅ | Peso saiu do perfil (SSOT) |
| F07 | Sync wearables | 🔍 | Persistência, fuso, 99 atividades, hierarquia de fontes |
| F08 | Dashboard modular | ✅ | 11 widgets na Fábrica + banner de validade |
| F09 | Esteira 14 dias | ⚠️🔲 | Declarado, **nunca visto** (R22) |
| F10 | Gateway Gemini + Zero Storage | 🔍 | 4 métodos; seletor Prato/Rótulo |
| F11 | Painel React B2B | ⚠️ | Muito ampliado — **nada testado pelo fundador** (R33) |
| F12/F14 | Seguradoras | ⛔ | HOLD |
| F13 | Garmin Gateway | 🔲 | **Não deployada** |
| F15 | Seed | ✅ parcial | Falta exames/anomalias |
| F16 | Exportação PDF+CSV | 🔲 | BL — loop viral B2B |
| F17–F25 | (tendência, streak, anti-culpa, cuidador, recuperação, medicamentos, sazonais, revogação, 2FA) | 🔲/⚠️ | Medicamentos entraram na anamnese (Bloco 9) |
| F26 | Prescrição ativa | ✅ | Nutrição com meta por dia da semana. Treino → BL |
| F32/F33 | `marcadores_referencia`, `resultados_exames` | ✅ | + `anamneses_exames_laboratoriais` |
| F34 | `coleta_diaria` | ✅ | Refeição, água, aparelho, rótulo |
| F36/F37/F42 | Vínculos, consentimento, aprovação profissional | ✅ | **Consentimento de compartilhamento nunca exercido (R39)** |
| F43 | Motor viral / gamificação | 🔲 | **BL — Bloco 5.** Marketing supõe pronto: NÃO está |
| F45 | `alimentos_referencia` | ⚠️ | 637 itens, aliases curados, Anti-Sequestro. **Falta fibra, sódio, NOVA e grupo FAO** |
| F46 | Nutrição semântica | ✅ | HNSW + Anti-Sequestro + falha visível em empate |
| F47 | Recuperação de senha | ✅ | Deep link físico pendente |
| F48 | Health Connect | 🔍 | FC, peso, composição, água corporal, IMC, andares, SPEED, TOTAL_CALORIES. **Timestamp de sono a verificar (N37)** |
| F49 | Diagnóstico de coleta | ✅ | Modo Profundo, desligado por padrão |
| F50 | Widget único de câmera | ✅ | `EscolherMetodoRefeicaoPage` + seletor de modo |
| F51 | Dashboards configuráveis | 🔲 | **Nível 1 = Parte W, não iniciado** |
| F52 | **Motor Metabólico V1** | ✅ | TMB-001, TDEE/dia, MACRO-001..005, déficit multicritério, score de qualidade. **Não verificado em uso** |
| F53 | **Anamnese Blocos 1–16** | ✅ | Versionada, SSOT, condicionais, validade, rascunho inteligente |
| F54 | **Agregação de smartwatch para anamnese** | ✅ | `processar_medias_smartwatch` + tela de revisão |
| **F55** | **Motor de Descobertas** (NOVO) | 🔲 | **Parte D. Nenhuma linha. Prioridade máxima** |

## 3.3.1 Itens da v1.0 — situação
N01–N20 entregues. **N27/N28/N14 entregues** (integridade da porção). **N21–N24 não iniciados.** **N29 (observabilidade) parcial** — só em `extract-metric-photo`.

| # | Item | Situação |
|---|---|---|
| **N30** | Fibra e sódio em `alimentos_referencia` + recarga TACO + propagação | 🔲 |
| **N31** | Ocultar variante de déficit e chips MACRO no fluxo sem profissional | 🔲 |
| **N32** | Tabela `widgets_disponibilidade` + tela de admin | 🔲 |
| **N33** | Seis renderizadores genéricos de widget | 🔲 |
| **N34** | Semeadura do catálogo completo (Parte W) | 🔲 |
| **N35** | Histórico alimentar detalhado | 🔲 |
| **N36** | Os seis cruzamentos de lógica própria | 🔲 |
| **N37** | Persistir timestamp de início e fim do sono — **absorvido pelo N43** | ↳ N43 |
| **N38** | WHtR opcional | 🔲 |
| **N39** | Colunas NOVA e grupo FAO em `alimentos_referencia` | 🔲 |
| **N40** | Classificação automática em três camadas + cobertura declarada | 🔲 |
| **N41a** | **Motor: as 4 tabelas + semear limiares práticos** (NOVO) | 🔲 |
| **N41b** | **Motor: avaliador de gates como função pura** (NOVO) | 🔲 |
| **N41c** | **Motor: seleção, deduplicação e cadência** (NOVO) | 🔲 |
| **N41d** | **Motor: renderizador de cartão em 4 camadas** (NOVO) | 🔲 |
| **N42** | **As 9 famílias de cálculo + os 15 templates do UAU** (NOVO) | 🔲 |
| **N43** | **Verificar timestamp de sono e tipo de refeição** — uma investigação, dois campos (NOVO) | 🔲 |
| **N44** | **Migração das chaves Supabase + `.env` versionado + CI/CD** (NOVO, **com prazo**) | 🔲 |
| **N45** | **Tratar HTTP 402 no chamador do Gemini** (NOVO) | 🔲 |
| **N46** | **Continuous: cadência, widget de descoberta recente, volume de templates** (NOVO) | 🔲 |

## 3.4 Entidades de banco

**Identidade:** `perfis_usuarios` (PII cifrada; **sem `peso_kg`/`altura_cm` desde 16/Set**), `papeis`/`permissoes`/`papeis_permissoes`/`usuario_papeis` (RBAC M:N), `vinculos_profissional_paciente`, `garmin_conexoes`.

**Anamnese (SSOT):** `anamneses` (~50 colunas, com composição corporal completa **incluindo circunferências**, objetivo e secundários, padrão alimentar, sono, `rotina_diaria`, 5 blocos condicionais JSONB, `data_validade`, `numero_versao`, `dados_confirmados`, `resultado_motor_v1`), `anamneses_atividades_dias` (PK anamnese+atividade+dia, `intensidade` NOT NULL), `anamneses_alergias`, `anamneses_problemas_saude`, `anamneses_medicamentos`, `anamneses_suplementos`, `anamneses_exames_laboratoriais`. `anamneses_atividades` **congelada**.

**Saúde:** `metricas_saude_diarias` (**a verificar: existem `sono_inicio`/`sono_fim`, ou só durações em minutos? — N37**), `coleta_diaria` (EAV), `eventos_anomalias_saude`, `atividades_fisicas_treinos`, `atividades_fisicas_rotas`, `tipos_atividades_fisicas` (99 códigos + MET + plataforma), `resultados_exames`.

**Nutrição:** `alimentos_referencia` (637 linhas — **faltam `fibra_100`, `sodio_100`, `grupo_nova`, `grupo_fao`**), `alimentos_medidas_caseiras` (1.056), `cache_sinonimos_alimentos`, `alimentos_favoritos`, `objetivos_alimentares` (`tipo_dia` TEXT livre), `sugestao_meta`, `problemas_saude`, `alergias`, `configuracoes_sistema`.

**Fase 5 (a criar):** `catalogo_widgets`, `widgets_disponibilidade`, `configuracao_dashboard`.

**Motor de Descobertas (a criar — Parte D):** `templates_descobertas`, `perguntas_analiticas`, `limiares_praticos`, `descobertas_publicadas`, `marcadores_ultraprocessamento`, `faixas_whtr`.

**Views:** `perfis_pacientes_vinculados` (**sem `security_invoker` — R1, pausado com motivo**), `perfis_profissionais_vinculados`.

**RPCs:** `calcular_motor_metabolico`, `calcular_motor_metabolico_v1`, `gerar_sugestao_meta`, `validar_e_salvar_meta`, `validar_macro_personalizado`, `iniciar_rascunho_anamnese`, `processar_medias_smartwatch`, `anamnese_historico_peso`, `profissional_salvar_anamnese`, `admin_perfis_seguro`, `admin_listar_vinculos`, `admin_encerrar_vinculo`, `admin_aprovar_vinculo`, `profissional_atualizar_sexo_biologico`.

**Edge Functions ACTIVE:** `extract-metric-photo`, `manage-professional-link`, `calculate-recovery-mode`, `search-food`. **Não deployada:** `garmin-gateway`.

### 3.4.1 `widgets_disponibilidade` — configuração por papel

```
widgets_disponibilidade
  widget_codigo   FK → catalogo_widgets
  papel           FK → papeis
  disponivel      bool   -- o papel PODE ver
  ativo_padrao    bool   -- já vem ligado no dashboard novo
  ordem_padrao    int
  PK (widget_codigo, papel)
```

**Regra de precedência:** `disponivel = false` no papel **vence** qualquer configuração individual. É a trava regulatória por papel. Papel novo (idoso, atleta, gestante) vira linha, não migração.

**Decisão 65:** o mesmo mecanismo serve às descobertas. `templates_descobertas` carrega `exige_profissional bool`, consumido pela mesma lógica. **Não são dois catálogos — é um catálogo com uma flag.** Economia: um renderizador, uma tela de admin, uma regra de precedência.

## 3.5 Arquitetura de dados de saúde
G.1 `resultados_exames` EAV (pontual) · G.2 `coleta_diaria` EAV (frequente, `origem` obrigatório) · G.3 `metricas_saude_diarias` colunas fixas (wearable) · G.4 alta frequência + FIFO (BL) · G.5 `eventos_anomalias_saude` · G.6 IA lê resumos, nunca tabelas brutas · G.7 pipeline "IA traduz, backend calcula" · G.8 a anamnese versionada é a fonte oficial de peso, altura e composição corporal · **G.9 (NOVO) dado derivado de evento guarda-se cru e deriva-se na consulta.** Horários de sono persistem como instante + offset de fuso; a regra de "a qual noite esse sono pertence" **não** é assada na gravação, porque muda conforme a descoberta (jet lag social precisa do dia da semana do adormecer; duração precisa da data do despertar).

## 3.6 Motor de dashboards (Fase 5)
`catalogo_widgets` é a fonte de verdade de todo widget: `widget_codigo` PK, nomes i18n, `nivel`, `periodos_suportados`, `fonte_calculo`, `categoria`, `renderizador` (qual dos seis genéricos usa) e `parametros` jsonb. **Novo widget = nova linha, não código novo.**

Três níveis: N1 SQL em tempo real (v1.0); N2 Cron (BL); N3 IA paga, só painel profissional (BL).

---

# PARTE 4 — ITENS EM HOLD (PROIBIDO IMPLEMENTAR)

## 4.1 Score Atuarial / Sinistralidade para Seguradoras — ⛔ (F12/F14)
Congela `sinistralidade_engine`, indicador de "Redução de Sinistralidade", login de operadoras, venda de score a terceiros. Motivos: políticas Health Connect/HealthKit proíbem uso atuarial; cálculo estava no cliente; LGPD exige base legal, consentimento destacado e RIPD inexistentes. Se encontrar o código: não expandir, manter atrás de flag desligada.

## 4.2 Fora de escopo sem nova revisão
Chat aberto de IA sobre saúde; SDKs proprietários de wearables; feed social; expansão internacional antes do PMF; **persistência de fotos de qualquer natureza**.

> **Emenda (decisão 62).** A redação original da decisão 51 dizia "armazenamento de fotos de qualquer natureza" e foi escrita larga demais, confundindo **persistir** com **exibir**. O que está proibido é **gravar** mídia em disco, storage ou banco. O **preview em memória** durante a captura (`Image.memory`, pipeline RAM volátil) **não** fere o Zero Storage e é parte do fluxo que já passou pelo teste solo. O erro de redação foi do consultor e está corrigido aqui.

## 4.3 Pergunta livre em linguagem natural sobre o próprio dado — ⛔ **backlog, não HOLD**
Interface de pergunta aberta ("explore sua rotina") foi proposta e **recusada para esta fase** (decisão 66). Motivos: cada pergunta é uma chamada ao Gemini, e o **R24 está aberto há mais de 70 dias com free tier de 20 requisições/dia**; é superfície regulatória nova (o usuário pergunta *"por que eu durmo mal?"* e qualquer resposta é interpretação); e é a funcionalidade que come um trimestre de um fundador solo que ainda não entregou a Fase 5. **Reabrir só depois do beta e com billing resolvido.**

---

# PARTE 5 — BLINDAGEM JURÍDICA E REGULATÓRIA

## 5.0 **DUAS FINALIDADES DECLARADAS** (decisão 68) — a mudança estrutural desta versão

A RDC 657/2022 enquadra software como dispositivo médico **pela finalidade**, não pela técnica. A exclusão de bem-estar vale para software destinado a incentivar hábitos saudáveis e controle de estilo de vida, **desde que não destinado a prevenção, diagnóstico, tratamento ou reabilitação**.

**Prevenção está nomeada como finalidade médica.** Logo, um produto cuja finalidade declarada é "saúde preventiva" **não tem acesso à exclusão de bem-estar**.

A solução não é mudar o produto — é declarar **duas finalidades, uma por módulo**:

| Módulo | Finalidade declarada | O que pode | O que não pode |
|---|---|---|---|
| **App do usuário avulso** | **Bem-estar.** Organizar o próprio registro, descrever hábitos e rotina, mostrar regularidade e variação | descrição, comparação observada, faixa habitual do próprio usuário, marco atingido | alerta, detecção, diagnóstico, prognóstico, prescrição, explicação de causa, qualquer linguagem de risco à saúde |
| **Painel Web profissional** | **Ferramenta para profissional habilitado.** Agrega, organiza e exibe dado; o ato clínico pertence ao profissional | referência clínica, meta, faixa recomendada, leitura prognóstica, índices clínicos | gerar conduta por IA sem o profissional; substituir o julgamento dele |

**Consequências operacionais imediatas:**

1. **A palavra "preventiva" sai da finalidade declarada do app avulso.** A empresa pode ser sobre prevenção; o **módulo de software** declara bem-estar. É texto — mas é o texto que decide o enquadramento.
2. **O R25 vira o primeiro passo, não uma tarefa paralela.** Detecção de anomalia de frequência cardíaca **é detecção**. É a única coisa em produção hoje que contradiz frontalmente um posicionamento de bem-estar, e está assim há quase três meses. **Desligar antes de declarar qualquer finalidade.**
3. **Nenhuma linguagem de alerta no app avulso.** Inclui o "limiar atingido", que era a única família diária planejada: *"você passou de 7.000 passos"* é marco e pode; *"atenção, sua FC de repouso subiu"* é aviso e não pode. Inclui o `SUP-002` (medida pendente): *"toque para resolver"* é operacional e pode; *"atenção"* não.
4. **A mesma política de integridade analítica vale para os dois módulos** (Regra 28). O que muda é a camada de **interpretação**, não a de honestidade.
5. **Aviso de que "o app não substitui um profissional" não muda enquadramento.** A finalidade real e a experiência entregue precisam ser coerentes com o posicionamento.

**Parecer a contratar, com escopo apertado para ser barato (decisão 69):** não é "revise meu produto". É *"confirme o enquadramento de dois módulos com estas finalidades declaradas, este conjunto de funcionalidades e esta política de integridade analítica"*, entregando este Mestre, o Catálogo de Descobertas e a Parte D. Com os três documentos em mão, é consulta pontual.

**Pergunta específica a levar ao parecer, não diluída no briefing:** *o sistema pode calcular e exibir recomendação de déficit calórico e distribuição de macros a usuário sem acompanhamento profissional?* (decisão 43).

**Pendência de conhecimento registrada:** foi mencionada uma **Resolução CFM 2.454/2026** sobre uso de IA na medicina. O consultor **não conhece essa resolução** (posterior ao seu conhecimento confiável) e **não a confirma nem nega**. Não é bloqueador imediato, porque o Painel Web **não** gera recomendação clínica por IA hoje. Deve ser lida por quem der o parecer **antes** de qualquer funcionalidade de apoio à decisão clínica por IA.

## 5.1 LGPD
Dado de saúde é sensível (art. 11): consentimento específico e destacado; política pública; exclusão e portabilidade (F16). **Pseudonimização ≠ anonimização.** Ranking público só com N ≥ 30. Proibido dado real em IA gratuita. Incidente: 3 dias úteis à ANPD. RIPD antes do lançamento. Vínculo nasce pendente; aceite do paciente libera a RLS.

**5.1.1 Dois consentimentos distintos (R39, NOVO).** O consentimento da **instalação** autoriza coletar e tratar o dado do próprio usuário — o fundador afirma que está tratado. O **compartilhamento com o profissional** é outro: autorização **específica, nominal ao profissional, revogável, com registro de acesso**. O primeiro não cobre o segundo. E como toda a frente B2B nunca foi testada (R33), **o fluxo de compartilhamento pode existir em código e nunca ter sido exercido por ninguém**.

**Conferência de 4 itens, antes do beta:** existe tela de autorização nominal ao profissional? com data? com registro de quem acessou o quê? com botão de revogar? Se as quatro existem, R39 fecha.

Requisitos mantidos: separação clara entre dado do usuário e dado disponibilizado ao profissional; nenhum uso secundário de dado sensível para treinamento de modelo sem base legal; relatórios que não expõem dado de terceiros; o usuário pode compreender e contestar os dados usados.

## 5.2 ANVISA (RDC 657/2022) **e exercício profissional (Lei 8.234/1991)**

- O gatilho de SaMD é a **finalidade**, não o tema. A ANVISA avalia rotulagem **e marketing**.
- Somos **organizador de dados que o usuário já possui**. Correlações clínicas só no painel do profissional.
- Gate determinístico de leituras: **não gravar > gravar errado**.
- Trava clínica: avulso que declara condição não recebe meta adaptada.

### 5.2.1 A linha de três camadas (decisão 43) — **regra operacional**

1. **Exibir TMB, TDEE, score de qualidade, gasto por dia da semana** → informação sobre o corpo do próprio usuário. **Permitido ao avulso.**
2. **Sugerir o TDEE como meta** → é a definição de manutenção, não intervenção. **Permitido ao avulso.**
3. **Sugerir TDEE menos déficit calculado + distribuição de macronutrientes** → conduta nutricional completa, montada pelo sistema, entregue a leigo em dois toques. **PROIBIDO no fluxo sem acompanhamento profissional.** Permanece integralmente no Painel Web.

**Fundamento duplo:** além do enquadramento SaMD, **prescrição dietética é ato privativo de nutricionista** (Lei 8.234/1991) — risco distinto, com conselho profissional ativo (CFN). *Este documento não substitui advogado.*

### 5.2.2 Pendência regulatória ativa
**R25:** detecção de anomalia de frequência cardíaca segue **ativa no código**. Encontrada em 10/Ago, apenas documentada. **Agora é o primeiro passo da declaração de finalidade (Parte 5.0), não uma dívida paralela.**

**A linha, escrita para ser aplicável (decisão 70):** **alerta diagnostica; espelho descreve.**
- **Desligar:** detecção e alerta de anomalia de FC.
- **Permitido — espelho:** exibir a FC que o dispositivo mediu. O relógio já mostra isso; o app não cria informação nova.
- **Permitido — descrição sem juízo:** descrever o padrão observado da própria FC, sem faixa "normal", sem zona de treino rotulada, sem comparação com referência clínica, sem "procure um médico".

Isso destrava `N1-FCR-001`, `N2-FCR-001`, `N3-FCM-501` e `N5-FCR-001` do catálogo de descobertas. Os **6 templates de FC pareada ficam fora da primeira biblioteca por escolha** — são o material mais perto da fronteira clínica do catálogo.

### 5.2.3 Vocabulário
Organizar, acompanhar, entender padrões, bem-estar, descoberta. **Nunca** diagnosticar, prever, recomendar conduta, explicar causa ao avulso, nem usar "alerta", "atenção", "fora do normal", "risco". Na tela, para o usuário, a palavra é **descoberta** — nunca "insight".

## 5.3 Lojas e Health Connect
Play: Data Safety + **Declaração de Apps de Saúde** (revisão manual, semanas — protocolar JÁ). Internal Testing até 100 testadores; produção exige teste fechado de 14 dias. **Garmin Developer Program: maior lead time.**

## 5.4 Permissões (minimização)
Health Connect estritamente READ. Permissões declaradas têm feature visível correspondente. Estados vazios são esperados, não bug.

---

# PARTE 6 — REQUISITOS DE SEGURANÇA (BLOQUEADORES DE RELEASE)

- **S1** Sessão server-side com rotação e revogação <60s.
- **S2** FLAG_SECURE nas rotas clínicas.
- **S3** Root/jailbreak: detectar, avisar, flag.
- **S4** Rate limiting e teto financeiro. *Com o R24 encerrado, o teto deixou de ser a cota gratuita e passa a ser configuração: **teto de gasto por projeto** na página Spend do AI Studio e **auto-reload com saldo mínimo**, para o pré-pago não zerar no meio de um teste.*
- **S5** `logs_acesso` append-only.
- **S6** Backup testado + rotação da chave do Vault — **antes dos amigos**.
- **S7** `INCIDENT_RESPONSE.md`.
- **S8** Higiene de repositório. **R6 REDEFINIDO EM 16/NOV — não é rotação, é migração, e tem prazo.** Ver abaixo. **R15 fechado** (`npm run secrets:sync-gemini`).

### S8.1 R6 — migração das chaves Supabase (substitui "rotacionar a Service Role Key")

O R6 nasceu em 01/Set como "rotacionar a Service Role Key", com o agravante de que `supabase projects api-keys` devolveu as chaves legadas **em texto pleno sem `--reveal`**, e com o aviso de que rotacionar invalidaria todas as sessões ativas. **Esse aviso está certo para o caminho antigo e o caminho antigo deixou de ser o correto.**

**O que mudou (verificado em 16/Nov na documentação oficial):**
- A Supabase está **descontinuando `anon` e `service_role` até o fim de 2026**, em favor de `sb_publishable_…` e `sb_secret_…`.
- **Rotacionar as legadas deixou de ser possível** — invalidar uma chave vazada exige migrar e desativar o par antigo.
- Regenerar o JWT secret (o caminho antigo) **invalida todos os segredos e corta todas as conexões** na hora.
- **Rotacionar as novas chaves não invalida sessão de usuário** — os JWTs de sessão são verificados pelo par assimétrico, que não muda.

**Consequência:** o motivo pelo qual o fundador adiou 76 dias — deslogar todo mundo — **não se aplica ao caminho correto**. E o R6 deixa de ser dívida interna: passa a ter **data imposta por terceiro**, como o Play Console e o Garmin.

**Os quatro passos, e quem faz cada um:**

| | Passo | Quem | Observação |
|---|---|---|---|
| 1 | Criar as chaves novas no Dashboard | **Fundador** | Aditivo e seguro: as legadas continuam funcionando |
| 2 | Trocar a publishable no código cliente (app Flutter, `web_painel`) | Claude Code | Onde hoje se usa a `anon` |
| 3 | Trocar a secret no backend (RPCs/funções e os scripts de `web_painel/scripts/`) | Claude Code | Onde hoje se usa a `service_role` |
| 4 | Desativar o par legado em Settings > API Keys | **Fundador** | Só após confirmar que tudo funciona |

**Fora de escopo, para a tarefa não crescer:** a migração do **JWT secret legado para chaves assimétricas** é outra coisa e **é opcional, sem prazo anunciado**. Não misturar.

**Ganho estrutural:** com `service_role` existia uma única chave, e qualquer vazamento obrigava a rotacionar a credencial de todo backend que a compartilhava. Com as novas, um componente que vaza a sua é rotacionado isoladamente.

**Agravante que a tarefa precisa tratar junto:** o R35 registra que `web_painel/.env` está no `.gitignore` contradizendo o próprio `.env.example`, e que a correção do endpoint de "Convidar Paciente" existe **só na máquina do fundador**. Uma troca de chaves que mexe em `.env` cai exatamente nessa fragilidade. **O `.env` versionado e o CI/CD vão na mesma tarefa (N44)**, senão a migração funciona numa máquina e nasce quebrada em qualquer clone.
- **S9** Revisão humana sênior antes do 1º release público.
- **Higiene de debug antes do beta:** remover `debugPrint` de diagnóstico do fluxo de foto e os botões "FORÇAR SYNC"/"FORÇAR CARGA 30 DIAS"/"GERAR LOG DIAGNÓSTICO" da tela de produção.
- **Fragilidade de implantação:** `web_painel/.env` está no `.gitignore` contradizendo o próprio `.env.example`, que o documenta como versionado. A correção do endpoint que quebrava "Convidar Paciente" existe **apenas na máquina do fundador**. Somado à ausência de CI/CD, um clone novo nasce quebrado.
- **S10 (NOVO)** **Consentimento de compartilhamento nominal, revogável e auditável** verificado em uso antes de qualquer dado de terceiro (R39, Parte 5.1.1).

---

# PARTE 7 — REGRAS DE NEGÓCIO

## 7.1 Gamificação e retenção — **BL (Bloco 5)**
Streak diário (1 registro de refeição + treino Garmin ou 8.000 passos; quebra zera e −100 pts, server-side); rankings com cache noturno e N≥30; esteira de 14 dias; pontos de refeição, peso e revisão de plano. **Entram aqui as duas funções de concorrente que fazem sentido ao avulso:** lembretes de refeição e hidratação, e metas semanais de atividade.

## 7.2 Autorrelato
Opt-in, toque único, recompensado, desvinculado da ofensiva. Máx. 1 pergunta/dia.

## 7.3 Motor viral (F43) — BL, **não construído**
Retrospectiva de Boas-Vindas (a Carga Inicial que ela exige **já existe**), Cartão da 1ª Semana, Retrospectiva Mensal, pontos sociais, loop B2B por PDF com marca e QR.

## 7.4 Modelo multi-profissional
Vínculo criado só via `manage-professional-link`, nasce pendente, aceite só do paciente, encerramento por qualquer lado com carência de 30 dias. Permissões como RBAC dinâmico M:N. **Meta:** o profissional define, com meta única ou por dia da semana; o avulso registra a própria, 1×/mês. **Resultado calculado e meta nunca se sobrescrevem** (ME-006).

## 7.5 Análises em 3 níveis
N1 tempo real (v1.0); N2 Cron (BL); N3 IA paga, exclusiva do painel profissional (BL). *Nota: esta numeração é de **dashboards** e não se confunde com os níveis N1–N5 de **descoberta** (Parte D.1).*

## 7.6 Ciclo menstrual e menopausa — BL
Bem-estar; calendário sim, fertilidade não; opt-in separado; nunca em ranking.

## 7.7 Registro offline e lançamento retroativo (decisão 71)

O horário da refeição é dado analítico — metade da família de intervalos (Parte D) depende dele. Mas rede falha. Desenho adotado:

- **Favoritas funcionam offline por completo.** São o caminho recomendado quando não há rede.
- **Texto é enfileirado cru, com o horário da captura preservado.** O processamento acontece ao subir; o horário registrado é o da captura, não o do envio.
- **Foto e áudio exigem rede.** Enfileirá-los obrigaria gravar mídia em disco e feriria o Zero Storage (Parte 4.2). O usuário é avisado e orientado à digitação ou à favorita.
- **Janela de tolerância de meia-noite** de 2 a 3 horas, em config: refeição capturada às 00h40 e enviada às 02h pertence ao dia anterior.
- **Dois estados pendentes, com superfícies diferentes:** não sincronizado é **indicador passivo** (`SUP-001`); medida pendente de tratamento é **alerta acionável** (`SUP-002`), porque é regra 23 — dado não resolvido não se arbitra em silêncio. **Nenhum dos dois usa linguagem de alerta de saúde** (Parte 5.0).

---

# PARTE 8 — DESIGN SYSTEM E UX

## 8.1 Proibições ("tiques de IA")
Gradiente roxo/índigo; glassmorphism generalizado; sombras difusas; emoji como ícone; creme+serifa+terracota default; quase-preto com verde-ácido; placeholders; microcopy traduzida do inglês; dois estilos para a mesma função.

## 8.2 Identidades por superfície
**Atleta** (escuro competitivo): grafite #0E1114, um acento de energia, números tabulares, anel de HealthScore. **Guardião** (claro clínico-acolhedor): off-white quente, corpo ≥18pt, toque ≥48dp, AA/AAA, linha do tempo vertical; escala de fonte via `_escalarTextTheme` (nunca `fontSizeFactor` sobre estilos sem fontSize — crash comprovado). **B2B Web:** densidade alta, hairlines, zero ornamento.

## 8.3 Tokens e camadas
Grade 8pt; um raio global + chips 999; escala tipográfica única; ícones outline de um peso; cores só via tokens, zero hex em widget; motion 150/250ms. Camadas: tokens JÁ; componentes pós-teste; assinaturas visuais antes do beta de amigos.

## 8.4 Padrões de tela
Estados vazios projetados; skeletons; erros com causa distinta (rede ≠ parse ≠ dado ausente ≠ inesperado); **nenhuma tela se fecha sem dizer por quê** (regra 25); 1 número-herói por tela; AA como piso; texto escalável a 130%; feedback progressivo aos 15s em operação longa.

**Padrão de dado incerto (regra 29):** todo número derivado de estimativa, de item arbitrado ou de medida resolvida pelo usuário aparece **marcado** em todas as telas. Um total que inclua qualquer estimativa carrega a marca.

**Padrão de dado ausente:** dia sem telemetria **não vira zero nem buraco silencioso** — cai para a fonte alternativa **declarando a troca na tela**.

## 8.5 Padrão de cartão de descoberta (NOVO)

Quatro camadas fixas, nessa ordem:

1. **Título** — a descoberta em uma linha, não a etiqueta da métrica. *"Você dorme mais no mesmo horário do que acorda"*, não *"Variação dos horários de sono"*.
2. **Corpo** — a frase com os números. No máximo um par de números por oração.
3. **Contexto** — em letra menor: janela, cobertura, dispersão, origem do dado, marca de estimativa. **Tudo que é ressalva sai do corpo e vive aqui.**
4. **Procedência (opcional)** — quando o template tem literatura atrás, uma linha descrevendo o estudo. Descreve a população do estudo; **nunca instrui o usuário**.

**O widget da tela inicial mostra "sua descoberta mais recente", com a data dela, e nunca anuncia o silêncio** (regra 13 do catálogo). Dia sem descoberta não produz cartão vazio nem mensagem de ausência — o cartão anterior continua, datado.

As 14 regras de redação completas vivem no Catálogo de Descobertas, seção 3. **Elas são especificação de produto, não preferência de estilo.**

---

# PARTE D — MOTOR DE DESCOBERTAS

> **Parte nova no v9.1, revisada no v9.2.** É a especificação do que estava faltando: o produto que o usuário vê e pelo qual ele decide se continua pagando. Os 277 templates vivem no documento anexo; **aqui vivem as regras, os gates e a engenharia**.
>
> **O que mudou no v9.2:** o Motor passa a ser construído como **RPC no Postgres, não Edge Function** (D.2.1); o N41 foi **quebrado em quatro etapas independentemente verificáveis** (D.10); e **UAU e Continuous passam a ser entregáveis separados**, com a conta de quantas famílias de cálculo cada um exige (D.10).

## D.1 O que é, e os cinco níveis

O Motor de Descobertas transforma o dado já coletado em frases que o usuário não teria como produzir sozinho. Classificação **editorial e funcional, não medida de significância estatística**:

| Nível | Nome | Critério verificável | Publicação |
|---|---|---|---|
| **N1** | Informativo | Um indicador, total, média, mínimo, máximo, cobertura ou estado isolado | Contexto e fallback. **Nunca cartão principal** |
| **N2** | Comparativo | Mudança entre períodos, distribuição, ou distância de meta **histórica** válida | Publicar se mudança e cobertura justificarem |
| **N3** | Comportamental | Concentração, estrato, dispersão, faixa habitual, bimodalidade, sequência, distribuição interna, intervalo entre eventos | **Priorizar.** É o núcleo do produto |
| **N4** | **Comparativo multidimensional** | Comparação entre grupos de dias observados, em dimensões distintas | Permitido pela Regra 28 revista, sob a biblioteca `perguntas_analiticas` |
| **N5** | **Longitudinal descritivo** | Mudança da dinâmica de um padrão entre janelas comparáveis | Descritivo elegível; componentes associativos sob a mesma biblioteca |
| **SUPORTE** | Estado e qualidade | Cobertura, pendência, origem, estimativa | **Não disputa ranking de descoberta** |

**Renomeações desta versão (decisão 72):** N4 era "Associativo" — a palavra prometia exatamente o que a regra proíbe, e vocabulário interno vaza para a interface com o tempo. N5 era "Longitudinal personalizado".

**Nível não é ranking automático.** N5 com evidência fraca nunca supera N2 robusto. Primeiro passam permissão, validade e qualidade; depois entram em seleção por novidade, relevância, objetivo da anamnese e diversidade. **Nenhuma análise precisa preencher artificialmente um nível.**

## D.2 Arquitetura — as tabelas a criar

**`templates_descobertas`** — a fonte de verdade de cada template.
`template_id` PK · `nivel` · `familia` · `titulo_i18n` · `corpo_i18n` · `contexto_i18n` · `procedencia_i18n` (nullable) · `dados_exigidos` jsonb · `gate` · `parametros` jsonb · **`exige_profissional` bool** · `semantic_key` · `cadencia_permitida` · `ativo` · `versao`.
**Template novo = nova linha, não código novo** — mesmo princípio de `catalogo_widgets`.

**`perguntas_analiticas`** — a biblioteca governada que a Regra 28 exige. **Cada entrada é uma pergunta, não um par de variáveis** — é o que torna o pré-registro defensável diante de um auditor.
`pergunta_id` PK · `versao` · `status` · `texto_da_pergunta` · `indicador_a` · `indicador_b` · `definicao_grupo_a` · `definicao_grupo_b` · `unidade_analise` · `janela` · `defasagem` · `n_minimo_a` · `n_minimo_b` · `cobertura_minima` · `medida_dispersao` · `limiar_pratico_minimo` · `fontes_permitidas` · `template_ids` · `revisor` · `aprovado_em` · `vigente_desde` · `vigente_ate` · `ativo`.

**Dois níveis de aprovação (decisão 73),** para que a cláusula de revisor não seja decorativa:
- **`aprovado_fundador`** — perguntas de rotina e comportamento, sem fisiologia. O fundador é competente para julgar se a pergunta é interessante e se a comparação é honesta.
- **`pendente_revisor`** — qualquer pergunta que cruze fisiologia. Fica **escrita e `ativo=false`**, esperando o parceiro.

Primeira versão: 14 perguntas, 5 aprovadas pelo fundador, 9 pendentes. Lista completa no Catálogo de Descobertas, seção 13.

**`limiares_praticos`** — o portão de publicação, por indicador.
`indicador` PK · `limiar_minimo` · `unidade` · `justificativa` · `versao`.
Valores iniciais: sono 20 min · passos 1.000 · FC 3 bpm · peso 0,5 kg · energia 150 kcal · proteína 15 g · água 300 ml · duração de treino 10 min.

**`descobertas_publicadas`** — proveniência e deduplicação.
`id` · `usuario_id` · `template_id` · `versao_template` · `pergunta_id` (nullable) · `texto_renderizado` · `valores` jsonb · `janela_inicio` · `janela_fim` · `cobertura` · `dispersao` jsonb · `semantic_key` · `publicado_em`.

**`marcadores_ultraprocessamento`** e **`faixas_whtr`** — tabelas de configuração (regra 16), descritas em V1/N39 e V1/N38.

## D.2.1 O Motor sai como RPC, não como Edge Function (decisão 88)

**Decisão arquitetural desta versão.** Todo o Motor de Descobertas — avaliador de gates, seleção, deduplicação, renderização dos valores — é implementado como **RPC no Postgres**. Nenhuma Edge Function nova.

**Motivo direto, com histórico:** não existe CI/CD neste projeto. Mesclar em `main` nunca deployou uma Edge Function, e isso já custou dois ciclos de teste — **cinco dias em 01/Set** contra uma função deployada antes dos fixes (relatório 20260901_0002) e **um mês em 16/Out** contra uma função de 14/Set (relatório 20261016_0003). É o modo de falha mais repetido do histórico do projeto.

RPC vai por **migration**, que o fluxo de tarefa já aplica com `db push --linked` e que a própria conferência de ACEITE exercita. Um componente que vai receber dezenas de tarefas em cima não deve herdar a classe de bug mais recorrente do projeto.

**E não há nada no Motor que exija Deno:** ele é **determinístico, sem chamada de IA** (ver nota do R24 na Parte 3.1). Template renderizado a partir de valor calculado não precisa de modelo.

**Consequências de desenho:**
- O cálculo das famílias vive em funções SQL/PLpgSQL puras, versionadas por migration.
- A renderização do texto final (substituir `{variáveis}` no corpo do template) pode ficar no Postgres ou no cliente; **a decisão fica com a tarefa N41d**, com a preferência registrada de ficar no Postgres, para que o texto publicado seja exatamente o que `descobertas_publicadas` guarda.
- Observabilidade (regra 22) se aplica igual: cada RPC do Motor registra conclusão, duração e contagem de candidatos avaliados.

**Não é "uma RPC".** São funções no plural, uma por responsabilidade, versionadas por migration e já separadas na fila: N41a tabelas, N41b avaliador de gates, N41c seleção, N41d renderização. Registrado porque a leitura de que a decisão 88 significa "monólito num único `CREATE FUNCTION`" apareceu numa segunda opinião e **não é o desenho** — quem for implementar não deve "corrigir" isso.

**Reversível.** Se em algum momento o Motor precisar de algo que o Postgres não faça bem, a troca para Edge Function é localizada. A decisão é de ordem de construção, não de arquitetura irreversível.

### D.2.1.1 Postura de segurança das RPCs do Motor (decisão 97 — emenda v9.2.1)

**Lacuna corrigida.** O v9.2 moveu o núcleo analítico para dentro do banco e não escreveu nada sobre a superfície de segurança que isso cria. A regra 20 do projeto — RLS habilitado + policy vinculada a `auth.uid()` + GRANT explícito — é regra de **tabela**. Função é outra superfície, e o Motor é justamente o componente que vai ler dado agregado. **Sem esta seção, a saída de menor esforço para qualquer implementador é `SECURITY DEFINER` sem `search_path`, que é escalonamento de privilégio clássico: quem controla o `search_path` escolhe qual função o corpo da RPC chama.**

Obrigatório em **toda** tarefa do Motor, e a conferência entra no `[RESTRIÇÕES]` do template de prompt (10.4):

1. **`SECURITY INVOKER` por padrão.** O Motor analisa o dado do próprio usuário; sob INVOKER a RLS já o restringe às linhas dele, sem código extra. O aceite do N41b ("rodar contra o próprio usuário e ler o JSON") funciona assim.
2. **`SECURITY DEFINER` só com justificativa escrita no relatório de fim de tarefa** e, quando usado, com **validação explícita de autorização e propriedade no corpo da função** — nunca confiando em um identificador de usuário recebido como argumento. O momento de tentação é previsível: o primeiro lote que precisar varrer vários usuários.
3. **`SET search_path = ''` na definição** e **todos os nomes qualificados por schema** (`public.coleta_diaria`, `pg_catalog.now()`). Sem exceção.
4. **`REVOKE EXECUTE ... FROM PUBLIC`** e `GRANT EXECUTE` nominal para o papel que precisa. GRANT explícito de função, pelo mesmo motivo da regra 20 para tabela.
5. **Nenhuma RPC administrativa ou de varredura exposta ao cliente.** O que não deve ser chamável pelo app **não mora em schema exposto pela API** — separação por schema, não por confiança no cliente.
6. **Rastreabilidade:** cada resultado gravado carrega a versão da regra e do limiar que o produziram (já exigido em D.4; aqui fica ligado à função que gravou).

**O que esta seção *não* resolve:** ela protege a execução, não a lógica. Gate errado em RPC blindada publica frase errada com segurança perfeita.

### D.2.1.2 O híbrido é o destino, e a fronteira é notificação (decisão 98 — emenda v9.2.1)

A segunda opinião de 16/Nov propôs RPC para o núcleo analítico e Edge Function para orquestração. **Como destino, está certo.** Como ponto de partida, não — e o motivo não é preferência de arquitetura:

- **A proposta não menciona deploy, CI/CD, nem quem opera.** O R35 está elevado a crítico porque mesclar em `main` nunca deployou uma Edge Function, e isso custou 5 dias (01/Set) e um mês (16/Out). Acrescentar o artefato cujo mecanismo de entrega não existe, na fundação do componente que vai receber dezenas de tarefas, é importar o modo de falha mais repetido do projeto para dentro dele.
- **O Cron já está no stack** (Parte 3.1). Agendamento, fila, lote, prioridade, retomada, idempotência e processamento incremental são **`pg_cron` + uma tabela de jobs** — sem runtime novo. O Motor **não é orientado a evento**: é lote por usuário, não requisição.
- **O UAU não tem o que notificar.** Por D.10.2 ele não publica N4 nem N5 e não precisa de cadência, agendamento, dedup no tempo nem widget de recente.

**Fronteira declarada, para não ficar a critério de quem implementa:** a Edge Function entra quando aparece **notificação (push) ou integração com serviço externo** — as duas coisas que o Postgres não faz. Isso acontece no **N46 (Continuous)**, não no N41 nem no N42. "Orquestração" em geral **não** é critério: é larga o bastante para justificar qualquer coisa.

**Três obrigações quando o híbrido entrar:**
1. A camada de orquestração **não reimplementa cálculo nem validação**. A Regra 28 é aplicada onde o dado está.
2. **Idempotência mora na RPC**, não na orquestração — quem grava decide se já gravou. Fronteira difusa entre dois runtimes é onde a lógica duplica.
3. A troca é **localizada por etapa** (N41a–d já são separadas), nunca uma reescrita do Motor.

**E uma propriedade a preservar conscientemente:** ver nota no fim de D.4.

## D.3 O limiar de publicação é prático, não estatístico

A pergunta que o GPT deixou aberta na revisão da Regra 28 — *como medir dispersão e quando uma diferença pode ser publicada* — tem a seguinte resposta, e ela é elegante por um motivo específico:

> **O portão de publicação é um limiar prático declarado por indicador, não um teste estatístico.**

Um limiar estatístico seria exatamente a inferência que a Regra 28 proíbe. Um limiar prático é uma decisão de produto: *abaixo de 20 minutos de diferença de sono, não vale contar*. Fica em `limiares_praticos`, versionado, auditável, e **nunca em código** (regra 16).

**Regra de ouro:** não adotar um único limiar universal ("diferença maior que um desvio padrão") para todos os indicadores. Cada indicador tem a sua grandeza e o seu ruído.

## D.4 Os gates

`G1` registro ou medição válida · `G2` períodos comparáveis com tamanho e cobertura mínimos · `G3` grupos observados comparáveis, suporte por estrato e ausência de viés óbvio de registro · `G4` pareamento temporal explícito, tamanho efetivo, pergunta na biblioteca, dispersão exibida, limiar prático atingido · `G5` múltiplas janelas comparáveis, estabilidade de método e fonte, cobertura parecida.

**O que de fato travava os N4, e como foi resolvido.** Pelas três perguntas da Regra 28 revista (o número foi observado? a frase afirma vínculo? projeta para a frente?), **os N4 passam** — agrupar dias por uma condição e comparar médias observadas não produz número não observado nem afirma causa. O risco real era a **múltipla comparação**: testar 40 cruzamentos e publicar o de maior diferença fabrica achado falso com certeza matemática. Conserto em quatro condições, todas em `perguntas_analiticas`:

1. **lista fixa versionada** de perguntas, decidida antes de olhar o dado;
2. **tamanho mínimo por grupo**;
3. **dispersão exibida junto da diferença**, e diferença abaixo do limiar prático não publica;
4. **o motor nunca escolhe o cruzamento "mais interessante"** — essa é a etapa que fabrica achado falso.

**Regra de operação do motor:** nunca criar cruzamento dinamicamente a partir do dado; nunca ordenar candidatos por tamanho da diferença. A seleção decorre de relevância pré-declarada, objetivo da anamnese, novidade e diversidade. Deduplicação por `semantic_key` (métrica, comparação, método, direção, janela) — **não republicar resultado equivalente só porque o número mudou na terceira casa**.

**Nota de desenho — a propriedade que o Motor só-RPC tem (emenda v9.2.1).** Enquanto todo o Motor é RPC, **não existe rota que contorne a Regra 28**: a validação roda onde o dado está e não há segunda porta para `descobertas_publicadas`. A proposta híbrida de 16/Nov sentiu a falta e escreveu a regra *"a Edge Function não poderá contornar as validações executadas pelas RPCs"* — o que é a confissão de que o híbrido **cria** a rota e depois pede para ninguém usá-la. Para a espinha regulatória do produto, **superfície a menos vale mais que regra a mais**. Quando o híbrido entrar (D.2.1.2), a garantia deixa de ser estrutural e passa a depender de disciplina: a gravação em `descobertas_publicadas` fica **restrita à RPC de seleção**, com `EXECUTE` negado a qualquer outro caminho, e a camada de orquestração **nunca** escreve nessa tabela.

## D.5 Por que os dois templates do fosso não caem na Regra 28

Esta análise é o achado de maior valor comercial da consolidação e **merece segunda opinião antes de virar código** (ver Parte 9.1, Bloco 0).

| | O que é | É inferência? | Classificação |
|---|---|---|---|
| **Declarado × medido** (`N2-FOS-001`) | TDEE da anamnese (PAL declarado) menos gasto medido pelo relógio | **Não.** Dois números observados, uma subtração | **N2 — liberado** |
| **Saldo acumulado × peso real** (`N2-FOS-002`) | Soma de (consumido − gasto) ao longo de N semanas, posta **ao lado** da variação de peso observada | **Não, se a frase não afirmar o vínculo** | **N2 — liberado com redação controlada** |

A diferença está inteira na redação:

❌ **Bloqueado** (afirma causalidade): *"Seu déficit de 4.200 kcal **resultou em** uma perda de 0,6 kg."*
❌ **Bloqueado** (projeta): *"Mantendo esse déficit, você perderia 2,4 kg em dois meses."*
✅ **Liberado** (justapõe dois fatos observados): *"Você registrou 4.200 kcal menos do que gastou neste mês. No mesmo período, seu peso caiu 0,6 kg."*

**Proibido nesses dois templates:** "resultou em", "levou a", "por causa de", "graças a", e qualquer projeção. A redação é o que os mantém fora da regra.

## D.6 A camada de índices publicados

Diferencial da decisão 64: **procedência citável**. Índices validados, calculáveis com o dado que o Orynty já coleta.

**Viáveis e adotados:**

| Índice | Fonte | Dado exigido | Templates |
|---|---|---|---|
| Eficiência de sono e tempo acordado (WASO) | métricas padrão de actigrafia | `sono_total_min` + **`acordado_min` (já existe e estava sem uso)** | `N3-EFI-001/002`, `N2-SON-003` |
| Jet lag social | Wittmann/Roenneberg, *Chronobiol Int* 2006 | horários de dormir e acordar | `N3-JET-001`, `N5-SON-004` |
| Distribuição de proteína entre refeições | Mamerow et al., *J Nutr* 2014 (EVEN 31/30/33 g vs SKEW 11/16/63 g → síntese 24h ~25% maior) | proteína por refeição | `N3-DIS-001/002`, `N3-PRO-101/102` |
| Janela alimentar | Gill & Panda, *Cell Metab* 2015 (maioria comia ≥15 h/dia) | refeições com hora | `N3-INT-907`, `N3-JAN-001` |
| Deslocamento do horário das refeições | Zerón-Rugerio et al., *Nutrients* 2019; *JAHA* 2022 | refeições com hora + calendário | `N3-EJE-001` |
| Diversidade alimentar | guias FAO (MDD) | **coluna `grupo_fao` (N39)** | `N3-DIV-001/002`, `N2-DIV-001` |
| Classificação NOVA | Monteiro et al. 2010 (USP); base do Guia Alimentar brasileiro; ensaio de Hall et al., *Cell Metab* 2019 (dieta ultraprocessada → ~500 kcal/dia a mais com o prato pareado) | **coluna `grupo_nova` (N39)** | `N3-NAT-001`, `N2-NAT-001` |
| Carga de treino TRIMP (Banister) | — | FC média da sessão + FC repouso + FC máxima (**os três existem**) | `N3-TRI-001`, `N2-TRI-001` |
| Monotonia de Foster | — | duração das sessões por semana (**proxy declarado**, sem percepção de esforço) | `N3-MON-001` |
| Relação ritmo/esforço (Efficiency Factor) | prática de treinamento (TrainingPeaks/Friel), **não índice revisado por pares** | velocidade média + FC média por sessão | `N3-EFF-001`, `N5-EFF-001` |
| Padrão "weekend warrior" | O'Donovan et al., *JAMA Intern Med* 2017; *JAMA Netw Open* 2023 | sessões + calendário | `N3-WEE-001` |
| Limiares de passos e cadência de pico 30 min | *PLoS One* 2019 (NHANES): 4.325–6.192 passos/dia; 66–72 passos/min | passos; **cadência exige passos intradiários — a verificar** | `N3-LIM-001`, `N3-CAD-001` |
| FFMI | VanItallie e seguidores | massa magra + altura (**os dois existem**) | `N3-FFM-001`, `N2-FFM-001` |
| Relação cintura-estatura (WHtR) | NICE NG7 (2022): 0,40–0,49 / 0,50–0,59 / ≥0,60; metanálises Ashwell 2012, Savva 2013, Jayedi 2020 | **cintura (existe desde 18/Set) + altura** | `N1-WHT-001`, `N3-WHT-002`, `N5-WHT-001` |
| Disponibilidade energética | consenso IOC 2023 (REDs) | ingestão + calorias de sessão + massa magra (**os três existem**) | `N3-EA-001/002`, `N4-EA-TRE-001` — **somente Painel Web** |
| Variabilidade de peso | Bangalore et al., *NEJM* 2017 | peso seriado | `N3-OSC-001`, `N2-VAR-001` (prof) |
| Velocidade de perda de peso | Garthe et al., *IJSNEM* 2011 | peso seriado + massa magra | `N3-PER-001`, `N2-PER-001` (prof) |

**Recusados com motivo — e a recusa é parte do diferencial:**

- **ACWR (razão carga aguda:crônica).** Impellizzeri et al., *IJSPP* 2020, "Conceptual Issues and Fundamental Pitfalls", e o artigo seguinte argumentando por descartar a razão e sua teoria. **Não implementar.** Todo app de treino vende isso; não vender é posicionamento defensável diante de um preparador físico.
- **Sleep Regularity Index pelo nome.** O SRI de Phillips et al. (2017) é definido por época ao longo das 24 h e existe esforço formal em curso (declaração RIRI) porque implementações open-source divergem do mesmo dado. O Orynty tem agregados; **a aproximação de bloco único existe (`N3-REG-001`) e não se chama SRI** em nenhuma superfície.
- **Adaptação metabólica como narrativa.** O Orynty **tem** como calcular medido-menos-predito (TDEE do relógio contra TDEE do Motor V1). Mas Martins et al., *Am J Clin Nutr* 2020, mediram ~54 ± 105 kcal/dia abaixo do predito (~3–4%), não sustentado em 1 e 2 anos, e concluem que a ideia de adaptação metabólica como motor do reganho "deveria ser posta para descansar". **Descrever a divergência: pode. Chamar de "metabolismo danificado": não.**
- **Conformidade com recomendação de açúcar livre.** A TACO traz **açúcares totais**, não livres. `N3-ACU-001` descreve a proporção e **declara o limite**; não afirma conformidade.
- **Desacoplamento aeróbico (Pa:HR)** e **fragmentação da atividade (transição ativo→sedentário)** — exigem, respectivamente, divisão intra-sessão e acelerometria minuto a minuto. **Não calculáveis.**
- **Completude do dia alimentar como gate.** Não existe como sinal e a própria especificação do projeto diz que não se infere do número de refeições. **Sete templates do catálogo v1.2 tinham esse gate — o gate não tinha o que checar.** Nenhum template do v2.0 depende dele.

## D.7 Cadência e arquitetura de publicação (decisão 74)

**D-1 como gatilho, não como assunto.** O motor roda sobre o dia anterior fechado, mas a janela de análise é independente da periodicidade: uma descoberta rodada na terça pode falar de 90 dias.

**Uma janela de avaliação, cinco tipos de descoberta:**

| Tipo | Cadência | Exemplo |
|---|---|---|
| Fato do dia | dashboard, não cartão | passos de ontem |
| **Limiar atingido** | **a única família diária** | *"você passou de 7.000 passos"* — **marco, nunca alerta** (Parte 5.0) |
| Padrão sustentado | semanal | faixa habitual, concentração |
| Tendência longa | mensal | N5 |
| Comparação | cadência do período comparado | N2, N4 |

**Diário oportunista, semanal e mensal garantidos.** Se nada relevante passar o gate num dia, **não se publica nada** — e a tela **não anuncia o silêncio** (`SUP-019`). O widget mostra a descoberta mais recente com a data dela.

**Nunca criar informação falsa para cumprir meta de publicação.** É a regra que impede o motor de virar máquina de conteúdo.

**Ciclo de vida de padrão:** padrão que se **mantém** fica calado — "nada mudou" não é descoberta. Padrão que **deixa de se repetir** é descoberta (`N5-SON-003`), e a redação é *"não se repetiu com a mesma frequência"*, nunca *"desapareceu"*.

## D.8 O descarte do catálogo v1.2

`ORYNTY_CATALOGO_TEMPLATES_UAU_CONTINUOUS_RF_ET_005.md` v1.2 declarava 2.178 candidatos. Extração mecânica do arquivo (2.166 entradas com corpo de texto, variáveis e nomes de métrica normalizados):

- **254 esqueletos de frase distintos**
- **20 esqueletos cobrem 1.786 entradas — 82,5% do catálogo**
- **195 entradas tinham frase realmente única**
- **31 sobreviveram** à avaliação contra as regras novas

O resto era produto cartesiano. As duas causas viraram as **regras 30 e 31** da Parte 0. Registro completo do descarte no Catálogo de Descobertas, seção 14.

**O que o v1.2 de fato contribuiu, e vale dizer:** não as frases — **as perguntas**. As 18 combinações de `HV-C4`, as 25 de `EV-C-4` e as 6 de `X-CRUZAMENTO` formam um inventário de cruzamentos candidatos mais completo do que o montado de forma independente. Quatro pares eram novos: açúcar × sono, gasto estimado × energia registrada, variabilidade do sono × atividade, e **regularidade de refeição × regularidade do sono**.

**A auditoria preliminar do GPT (ORY-INS-AUD-N28-001) recomendava "PRESERVAR, COM QA GLOBAL" os 1.448 N1.** Discordância registrada: os 1.448 são **11 frases** repetidas por 119 métricas, e 5 das 11 não são N1 — são SUPORTE ou saem. QA global sobre 1.448 linhas é auditar a mesma frase 119 vezes.

## D.9 Três regras adotadas na arquitetura de descobertas

1. **Ausência ≠ zero.** Dia sem registro não entra como valor zero em nenhuma média, soma ou comparação. (Formalizada na regra 28, proibição 4.)
2. **Metas têm vigência histórica.** Comparação com meta usa a meta que valia **na data de cada registro**, nunca a atual. Registrado em `SUP-004`, que exibe isso ao usuário como descoberta de confiança.
3. **Cadência ≠ janela.** A periodicidade do relatório não restringe a janela de análise.

---
## D.10 Arquitetura de entrega — UAU e Continuous são dois entregáveis (decisão 89)

O v9.1 tratava "o Motor de Descobertas" como uma coisa. **São duas**, com escopos e prazos diferentes, e misturá-las é a receita para nenhuma das duas sair.

### D.10.1 A unidade de trabalho é a família, não o template

**Template não é código — é linha de tabela.** Código é a **família de cálculo**. *"Metade dos seus passos veio de 6 dias"* e *"um terço das suas calorias veio de 5 dias"* são a mesma conta de concentração aplicada a métricas diferentes: **uma função, duas linhas**.

Medido no catálogo:

| | |
|---|---:|
| Templates | **277** |
| **Famílias de cálculo** | **36** |
| Famílias tocadas pelos 15 templates do UAU | **9** |
| Templates que essas 9 famílias destravam | **87 (31%)** |

**Logo: construir as 9 famílias do UAU entrega o relatório inteiro e deixa 87 templates a um `INSERT` de distância.** Isso reposiciona a conversa de "277 tarefas" para "36 funções, 9 delas primeiro".

**Semear um template depois que a família existe é entrada de dado com amostragem (regra 26), não desenvolvimento.**

### D.10.2 O que o UAU precisa, e o que ele não precisa

O relatório UAU é gerado **uma vez**, sobre a Carga Inicial de 30 dias, em 6 telas lógicas com até 3 descobertas cada.

**O UAU não publica nenhum N5** — N5 exige duas janelas comparáveis e a carga tem uma. **E não publica nenhum N4** — o tamanho mínimo de grupo não fecha com confiança em 30 dias.

Consequência prática, e é grande: **o UAU não precisa de cadência, nem de agendamento, nem do widget "sua descoberta mais recente", nem da deduplicação ao longo do tempo.** Metade do Motor é do Continuous.

| | Precisa para o UAU | Precisa para o Continuous |
|---|---|---|
| As 4 tabelas (D.2) | sim | sim |
| Avaliador de gates G1–G3 | sim | sim |
| Gates G4 e G5 | **não** | sim |
| Biblioteca `perguntas_analiticas` | **não** (só N4 usa) | sim |
| Deduplicação por `semantic_key` | **não** | sim |
| Cadência e os 5 tipos (D.7) | **não** | sim |
| Widget de descoberta recente | **não** | sim |
| Renderizador de cartão | sim | sim |
| Notificação (push) | **não** | sim |
| **Edge Function de orquestração** (decisão 98) | **não** | sim — é o que a torna necessária |

### D.10.3 O N41 quebrado em quatro etapas (mitigação estrutural do R40)

O R40 registra que o Motor é a maior entrega de uma vez na história do projeto, e que a mitigação é "a fundação entrega sozinha". **Escrito como uma tarefa, isso não acontece.** Critério da quebra: **cada etapa é verificável pelo fundador sem a seguinte existir.**

| | Tarefa | Entrega | Como o fundador verifica |
|---|---|---|---|
| **N41a** | As 4 tabelas + semear `limiares_praticos` | Migration pura, **zero lógica** | Insere uma linha e consulta. SQL, sem app |
| **N41b** | Avaliador de gates G1–G3 como **função pura** | Devolve o que passou; **não publica nada** | Roda contra o próprio usuário e lê o JSON de saída |
| **N41c** | Seleção: dedup por `semantic_key`, novidade, cadência | Grava em `descobertas_publicadas` | Roda duas vezes seguidas e confirma que nada republica |
| **N41d** | Renderizador de cartão em 4 camadas (Parte 8.5) | Lê uma descoberta já gravada | Insere uma linha à mão e vê o cartão na tela |
| **N42** | As **9 famílias de cálculo** + as 15 linhas do UAU | O relatório UAU completo | Lê as 6 telas e julga cada frase |

**N41c é opcional para o UAU** e obrigatória para o Continuous — pode correr depois do N42 se o objetivo for colocar o UAU na frente dos amigos o quanto antes.

A ordem respeita a regra do projeto de **validação completa funcionalmente, crua visualmente**: cada etapa tem um aceite que não depende de design pronto.

### D.10.4 O Continuous, depois

**N46** reúne o que sobra: gates G4/G5, a biblioteca de perguntas semeada, cadência com os cinco tipos, o widget de descoberta recente com a regra de **nunca anunciar o silêncio**, e o volume de templates em lotes por família.

**Ordem sugerida dos lotes depois do UAU:** as famílias que mais templates destravam por função escrita — dispersão (12), intervalos (10), distribuição interna (10), estrato semanal (10), concentração (9), faixa habitual (8), dia específico (8). Deixar **período contra período (24)** para depois, apesar de ser a maior: ela compara com a janela anterior, que **não existe no primeiro mês de uso** e portanto não aparece para um usuário novo de beta.

---

# PARTE 9 — EXECUÇÃO E PLANO DE TESTE

## 9.1 Fila vigente (16/Nov/2026)

> **Mudança de prioridade (decisão 75).** Os testes de campo mostraram que o que falta é valor percebido. O Motor de Descobertas passa à frente dos ~40 widgets de paridade, **com a correção de que "descobertas" não é uma tarefa**: a fundação do motor vem antes dos 277 templates, pela mesma lógica que põe os renderizadores antes dos 40 widgets. Construir template antes do motor é construir 277 vezes o que se constrói uma.
>
> **O que escorrega, dito em voz alta:** os ~40 widgets de paridade. Pela repositionagem das decisões 46–49, eles fazem o Orynty **empatar** com o VibeFit. Um beta com widget de paridade colhe "legal, mas eu já tenho o MyFitnessPal". Um beta com *"você dorme mais no mesmo horário do que acorda"* colhe reação.

### BLOCO 0 — Não é código

**0.1 ~~Decidir o billing do Gemini (R24)~~ — ENCERRADO EM 16/NOV.** Billing ligado, projeto em Tier 1. Aberto 84 dias. **Falta verificar em uso** (2.6).
**0.2 Segunda opinião sobre a Parte D.5** — a análise que libera `N2-FOS-001` e `N2-FOS-002` da Regra 28. São os dois templates de maior valor comercial; o custo de errar é alto.
**0.3 Segunda opinião sobre a redação final da Regra 28** — alteração de maior alcance do v9.1.
**0.4 Contratar o parecer de enquadramento das duas finalidades** (Parte 5.0), com o escopo apertado da decisão 69.
**0.5 Lead time externo — começar agora, porque não é esforço, é espera:** Declaração de Apps de Saúde no Play Console (revisão manual, semanas), Garmin Developer Program (o maior lead time de todos), domínio e landing sob o nome Orynty, marca no INPI. Nenhum iniciado; o nome foi definido em 25/Out.

### BLOCO 1 — Prazo de terceiro e verificações baratas (**ordem desta vez importa**)

**1.1 N44 — migração das chaves Supabase + `.env` versionado + CI/CD.** **Prazo: fim de 2026.** Quatro passos da Parte 6/S8.1, dois do fundador e dois do Claude Code. Vem **antes** do Motor por dois motivos: o prazo não é nosso, e construir o Motor sobre credenciais que estão mudando é ter duas peças móveis nos mesmos arquivos. O `.env` versionado vai junto, não depois.
**1.2 R25 — desligar a detecção de anomalia de FC.** É o **primeiro passo da declaração de finalidade de bem-estar** (Parte 5.0), não dívida paralela. Junto: auditar as telas (nenhuma faixa de referência de FC, zona rotulada ou juízo clínico) e registrar por escrito a linha alerta/espelho (5.2.2).
**1.3 N43 Etapa 1 — uma investigação, dois campos.** Em `metricas_saude_diarias`, os instantes de início e fim do sono são persistidos ou só as durações? E em `coleta_diaria`, a linha de refeição guarda o **tipo** (café/almoço/jantar) nos quatro métodos de registro, ou só nas favoritas? **Juntas decidem 29 templates — 10% do catálogo.** Só relata e **para** (contramedida da Parte 10.6).
**1.4 N45 — tratar HTTP 402** no chamador do Gemini. Com o pré-pago, saldo zerado é erro real: **não retenta e não cai no fallback** (os dois níveis falham igual, o saldo é da conta de faturamento). Mensagem própria e honesta, no mesmo lugar do `ErroCotaGemini`.
**1.5 N38 — WHtR opcional.** Confirmar em qual bloco da anamnese está a circunferência de cintura. Se existe, **não criar campo** — é uma divisão.
**1.6 N31 — ocultar a variante de déficit e os chips MACRO** no fluxo sem profissional (linhas 302 e 355). **Junto, corrigir o cabeçalho do arquivo**, que afirma o contrário do que o código faz (regra 27).
**1.7 N30 + N39 juntos — fibra, sódio, NOVA e grupo FAO.** Mesma tabela, mesma recarga da TACO, mesma propagação até o Flutter. **Fazer em duas passadas é recarregar a TACO duas vezes por nada.**
**1.8 Conferência de 4 itens do consentimento de compartilhamento** (R39, Parte 5.1.1).

### BLOCO 2 — Fundação do Motor de Descobertas (**quatro etapas, cada uma com aceite próprio**)

Tudo como **RPC no Postgres** (decisão 88, Parte D.2.1). Critério da quebra em D.10.3: **cada etapa é verificável sem a seguinte existir.**

> **Obrigatório em toda tarefa deste bloco que cria ou altera função:** a postura de segurança da decisão 97 (Parte D.2.1.1) — `SECURITY INVOKER`, `SET search_path = ''`, nomes qualificados por schema, `REVOKE EXECUTE FROM PUBLIC` + GRANT nominal, e `DEFINER` só com justificativa escrita no relatório. **Isso não é item de aceite do fundador** (ele não tem como testar `search_path` pela tela): é item de conferência do prompt e do relatório.

**2.1 N41a — as 4 tabelas** da Parte D.2 + semear `limiares_praticos` com os 8 valores. Migration pura, zero lógica.
*Aceite: inserir uma linha em `templates_descobertas` e consultá-la. Baixar o limiar de um indicador e ver o valor mudar na tabela.*

**2.2 N41b — avaliador de gates G1–G3 como função pura.** Devolve os candidatos que passaram, com cobertura e dispersão. **Não publica nada, não grava nada.**
*Aceite: rodar contra o próprio usuário e ler o JSON de saída.*

**2.3 N43 Etapa 2** — persistir `sono_inicio`/`sono_fim` com offset de fuso, consolidação de segmentos declarada em config, derivação na consulta (G.9); e o tipo de refeição, se faltar. Só **após** o relatório da Etapa 1.

**2.4 N41d — renderizador de cartão em 4 camadas** (Parte 8.5), lendo uma descoberta já gravada.
*Aceite: inserir uma linha à mão em `descobertas_publicadas` e ver o cartão na tela, com contexto e cobertura.*

**2.5 N41c — seleção, deduplicação e cadência.** **Opcional para o UAU, obrigatória para o Continuous** (D.10.2) — pode correr depois do Bloco 3 se o objetivo for pôr o UAU na frente dos amigos antes.
*Aceite: rodar duas vezes seguidas e confirmar que nada republica.*

### BLOCO 3 — O relatório UAU

**3.1 `N2-FOS-001` e `N2-FOS-002`** — o fosso. Maior valor comercial, nenhuma dependência nova. Redação controlada da Parte D.5: **proibido "resultou em", "levou a", ou qualquer projeção.**
**3.2 N42 — as 9 famílias de cálculo + as 15 linhas do UAU** (Catálogo, seção 12). Prova a cadeia inteira com o melhor conteúdo, e **destrava 87 templates (31%)** para semeadura posterior (D.10.1).
**3.3 N1 e SUPORTE** — rápidos, e sem eles o relatório não tem rodapé nem fallback honesto.
**3.4 N35 — histórico alimentar detalhado.** Não é paridade: foi o fundador que sentiu falta no teste de campo, e é a tela que dá sentido a todo o registro que o usuário faz.

> **Fim do Bloco 3 = o beta pode começar**, desde que o Bloco 4 tenha fechado.

### BLOCO 4 — Destravar o beta de amigos (**pode correr em paralelo ao 2 e ao 3 — é pré-condição, não concorrente**)

**4.1** ~~Rotação da Service Role Key~~ → **absorvido pelo N44 (Bloco 1.1)**.
**4.2** Separar homolog de produção (R-E4).
**4.3** Backup e rotação da chave do Vault (S6).
**4.4 BL.1 — fila de revisão de alimentos criados pelo usuário.** O gatilho combinado era exatamente este momento.
**4.5** Tirar os botões de debug e os `debugPrint` de diagnóstico da produção.
**4.6** `garmin-gateway`: deployar **ou** remover do fosso.
**4.7** **Testar o Painel Web da Anamnese Profissional** (R33) — frente inteira nunca verificada.
**4.8** Configurar **teto de gasto por projeto** e **auto-reload com saldo mínimo** no AI Studio (S4).

> **Condição registrada.** Se o Bloco 3 avança e o Bloco 4 escorrega, o resultado é um motor de descobertas bonito que **não pode legalmente ou seguramente ser mostrado a um amigo**. Beta de amigos é dado real de terceiro. São horas de infra, não semanas de produto.

### BLOCO 5 — O Continuous (depois que o beta estiver rodando)

**5.1 N46** — gates G4/G5, biblioteca `perguntas_analiticas` semeada (14 perguntas: 5 `aprovado_fundador`, 9 `pendente_revisor`), cadência com os cinco tipos (D.7), e o widget de descoberta recente com a regra de **nunca anunciar o silêncio**.
**5.2 N40** — classificação automática em três camadas para alimento novo: herança por similaridade (pgvector, já existe), marcadores de ultraprocessamento por regra, e **fila de revisão com cobertura declarada** quando nada decide.
**5.3 Volume de templates por lote de família**, na ordem de retorno da D.10.4: dispersão, intervalos, distribuição interna, estrato semanal, concentração, faixa habitual, dia específico. **Período contra período fica para o fim**, apesar de ser a maior família — ela compara com a janela anterior, que não existe no primeiro mês de uso.
**5.4** Os **N4 da biblioteca `aprovado_fundador`** (perguntas 6, 7, 8, 10, 11).

### BLOCO 6 — Fase 5 de widgets

**6.1 N32** (`widgets_disponibilidade`) → **N33** (seis renderizadores) → **N34** (semear a Parte W).
**6.2** Os ~40 widgets de paridade e telemetria, por configuração.
**6.3 N36** — os seis cruzamentos de lógica própria.
**6.4 N23** resumo e **N24** onboarding.
**6.5** Gamificação (F43) com lembretes e metas semanais.

### BLOCO 7 — Depois do revisor nomeado
**7.1** Os N4 `pendente_revisor`. **Não construir antes.**
**7.2** Os 3 templates de ultraprocessado (fronteira NOVA 3/4 validada por nutricionista).
**7.3** Os 6 N4 de FC pareada, se e quando a decisão regulatória permitir.

### 9.1.1 Bloco permanente — achados de campo

**O v9.0 não tinha slot para o que o fundador descobre usando o produto**, e isso era falha de desenho da fila: os testes de campo de outubro produziram 12 tarefas que não tinham onde morar, e as oito de novembro vieram pelo mesmo caminho. Bloco permanente, com prioridade entre o Bloco 1 e o Bloco 2: **todo achado de campo entra aqui, é catalogado no log antes de ser corrigido, e é triado em "impede o teste" ou "entra na fila".**

### 9.1.2 Regra de sequenciamento

**O Bloco 1 vem primeiro, e dentro dele o N44 primeiro de todos** — é o único item da fila com data imposta por terceiro.

Nada do Bloco 3 começa antes do Bloco 2 fechar — **com uma exceção registrada: o N41c (seleção e dedup) pode ir depois do Bloco 3**, porque o UAU não precisa dele (D.10.2). O Bloco 4 corre em paralelo ao 2 e ao 3. O **Bloco 5 (Continuous) só depois do beta começar**, porque é ele que ganha valor com o tempo de uso. O **Bloco 6 (widgets) é o último** — e é a segunda consolidação seguida em que a Fase 5 fica deliberadamente atrás, agora com dois motivos registrados: os widgets são paridade (decisões 46–49) e o Continuous é o que retém.

### 9.1.3 O que esta fila entrega, em ordem

| Marco | O que o usuário vê | Depende de |
|---|---|---|
| Fim do Bloco 1 | nada novo — terreno firme e prazo resolvido | N44, R25, N43 |
| Fim do Bloco 2 | nada novo — o motor existe e é verificável | N41a, N41b, N41d |
| **Fim do Bloco 3** | **o relatório UAU com 15 descobertas** | N42 + os dois do fosso |
| Bloco 4 fechado | — | pré-condição do beta |
| **Beta de amigos** | o produto com o diferencial ligado | Blocos 1–4 |
| Bloco 5 | descobertas semanais e mensais que crescem com o uso | N46 + lotes de família |
| Bloco 6 | os ~40 widgets de paridade | depois de tudo |

## 9.2 Ambientes
**Alvo:** dois projetos Supabase. **Real:** um só. Antes de dado de terceiro, criar prod separado + checklist de paridade (secrets, verify_jwt, providers, GRANTs, config.toml). **Migrações** sempre `--linked` contra o remoto; este projeto nunca usou Postgres local. **Sem CI/CD:** mesclar em `main` não deploya Edge Function — exige `supabase functions deploy` manual (lição de 01/Set, quando 5 dias de teste rodaram contra uma função antiga).

## 9.3 Plano de teste
Web fake → app fake → correções → **teste solo (CONCLUÍDO)** → **testes de campo (CONCLUÍDOS)** → Motor de Descobertas → zerar → **amigos com Garmin/Android via loja** → iOS depois. Nada do backlog entra durante testes, exceto bug que impede o teste.

## 9.4 Roteiro de validação do Motor Metabólico (pendente)

A tela deve expor a **cadeia inteira**. Conferência manual:
- Mifflin-St Jeor homem: `(10 × peso) + (6,25 × altura) − (5 × idade) + 5`; mulher: `−161` no lugar do `+5`.
- Katch-McArdle: `370 + (21,6 × MLG)` · Cunningham: `500 + (22 × MLG)`.
- Gasto por atividade: `MET × peso(kg) × horas`.

**Três armadilhas:**
1. **Dupla contagem (resolvida, manter vigilância).** O gasto **declarado** (anamnese) é baseline de verificação; o **medido** (Garmin) alimenta o relatório. **Nunca somados.** Dia sem telemetria cai para o TDEE do motor **declarando a troca**.
2. **Massa magra inferida alimentando Katch-McArdle.** O trigger deriva massa magra de peso × %gordura. Derivado não é medido — a tela declara.
3. **TEF isolado.** Está correto e documentado; o risco é alguém "corrigir" meses depois achando que foi esquecimento.

**Gaps conhecidos:** TMB-003 (Cunningham) e a biblioteca de fórmulas como **tabela** não foram confirmados como implementados — hoje o versionamento vive no JSON de saída, o que fere a regra 16 (R37). **NEAT** nunca é estimável (falta fonte de dado) e o motor usa PAL — correto pela própria regra do documento. *Nota: o `N3-NEA-001` do catálogo de descobertas **não** é NEAT estimado — é passos do dia menos passos da sessão, que é dado observado.*

---

# PARTE 10 — EXECUÇÃO COM CLAUDE CODE

## 10.1 Papéis
Execução no **Claude Code**. Planejamento: **Gemini 3.1 Pro** (gerente de projeto), **Claude** (consultor/revisor), **GPT** (segunda opinião). Este Mestre é a memória oficial.

## 10.2 Política de modelos
Padrão **Sonnet**; trivial **Haiku**; crítico **topo de linha** (RLS, segurança, tokens, pipeline RAM, OAuth, criptografia, arquitetura, **motor de descobertas**).

## 10.3 Governança de log
`/docs/log_dev/AAAAMMDD_SSSS.md` + `INDICE.md` append-only. Registra só o que foi feito **e verificado**.

## 10.4 Template de prompt
`[MODELO]` · `[CONTEXTO]` Parte 0 + a seção da Parte V1, W ou D da tarefa · `[TAREFA]` objetivo único · `[ARQUIVOS]` caminhos exatos (investigar antes de criar) · `[RESTRIÇÕES]` HOLD; segurança; UX; server-side; GRANT; sem segredos; sem hardcode (16); performance (21); observabilidade (22); falhar visível (23); teste não vira spec (24); tela não fecha em silêncio (25); amostragem de dado de IA (26); documentação reconciliada (27); **Regra 28 revista**; estimativa declarada (29); **variável não carrega sentido (30)**; **frase sobre registro é SUPORTE (31)**; **linguagem de alerta proibida no app avulso (Parte 5.0)**; **se a tarefa cria ou altera função no banco: postura de segurança de RPC (decisão 97, Parte D.2.1.1) — `SECURITY INVOKER` por padrão, `SET search_path = ''`, nomes qualificados por schema, `REVOKE EXECUTE FROM PUBLIC` + GRANT nominal, `DEFINER` só com justificativa escrita no relatório** · `[ACEITE]` como o fundador testa, passo a passo · `[ENTREGÁVEL]` código + explicação simples; branch + PR; **deploy explícito se tocar Edge Function**; relatório de fim de tarefa com decisões|motivo · infra/config · entidades novas · desvios · problemas encontrados · riscos mapeados · como o fundador testa · performance · estado das branches.

## 10.5 Ritual
1 tarefa/sessão → implementação + explicação → teste pelo aceite → commit/PR → merge. Quebrou: `git revert`.

## 10.6 Antipadrões observados em agentes — ler antes de aceitar um diagnóstico

1. **Manter a conclusão e reencaixar a evidência nova nela.** Exigir que o agente cheque se a *premissa* da hipótese anterior ainda vale.
2. **"Alta confiança" com evidência ambígua.** Pedir a segunda explicação possível e como distingui-la.
3. **Concluir por ausência de log.** Pode significar que o log nunca foi implementado.
4. **Débito rotulado "fora do escopo" tarefa após tarefa.** Três relatórios seguidos → vira tarefa própria.
5. **Atualizar o teste em vez do comportamento** (regra 24).
6. **Ponto cego do arquivo não aberto.**
7. **Documentação do arquivo que contradiz o próprio arquivo** (regra 27).
8. **Confiar em contagem de ferramenta externa para decidir onde parar de ler.** Em 18/Set, uma contagem devolveu 2288 para um arquivo de 3512 linhas; 1.224 linhas com três seções inteiras ficaram sem leitura. **Ler até a ferramenta não devolver mais conteúdo.**
9. **(NOVO) Consertar o mecanismo e presumir que a conclusão vem de brinde.** Em 01/Nov o consultor reescreveu a Regra 28 e tratou isso como se resolvesse o enquadramento regulatório. Não resolve: a RDC 657/2022 enquadra por **finalidade**, não por técnica. **Quando um conserto é técnico, perguntar explicitamente o que ele não conserta.**
10. **Estimar volume de catálogo por contagem de linhas.** O catálogo v1.2 declarava 2.178 candidatos e era ~254 frases, 20 delas cobrindo 82,5%. **Normalizar variáveis e colapsar nomes de métrica antes de acreditar num número de inventário.**
11. **(NOVO) Registrar como confirmado o que foi afirmado verbalmente.** Em 25/Out o fundador disse que data e hora de tudo estavam sendo gravadas; o consultor escreveu "com data e hora" na lista de dado **confirmado** do Mestre e construiu 31 templates em cima. Em 16/Nov o próprio fundador recuou ("não sei se é gravada"). O dado estava lá — mas o registro foi feito sem leitura de arquivo, violando a regra que o próprio consultor cobra. **Afirmação verbal vira pendência de verificação, nunca linha de "confirmado".** Ver C27.
12. **(NOVO) Entregar um conserto e manter o escopo que o conserto tornou obsoleto.** O R6 ficou 76 dias descrito como "rotacionar a chave", com um aviso de impacto que já não valia — e o aviso era justamente o que travava a execução. **Antes de cobrar um item antigo de terceiro, reler a documentação do terceiro.**
13. **(NOVO) Mover lógica para uma camada nova e não levar o modelo de segurança junto.** Em 16/Nov o consultor decidiu que o núcleo analítico do Motor vive no Postgres (decisão 88) e **não escreveu uma linha sobre `SECURITY INVOKER`/`DEFINER`, `search_path` ou `EXECUTE`** — o Mestre v9.2 tinha zero ocorrências dos três. A regra 20 do projeto cobre **tabela**; função é outra superfície, e a saída de menor esforço para quem implementa é a insegura. Quem apontou foi a segunda opinião, não o autor da decisão. **Toda decisão que atravessa uma fronteira (banco↔função, cliente↔servidor, síncrono↔lote) exige escrever a postura de segurança do destino na mesma decisão — ela não viaja de carona.** Ver decisão 97 e D.2.1.1.
14. **(NOVO) Proposta de arquitetura que dimensiona para a escala futura e não menciona quem opera.** A mesma segunda opinião de 16/Nov pediu escalabilidade "para milhares e, futuramente, milhões de usuários" em 128 linhas que **não citam deploy, CI/CD nem operador** — num projeto de fundador solo não-desenvolvedor, sem CI/CD, cujo modo de falha mais repetido é exatamente o deploy manual (R35). É o padrão do R19 em outra casa: entregável sólido que não toca a restrição que gerou a pergunta. **Ao receber proposta de arquitetura, perguntar primeiro quem faz o deploy e quantos usuários existem hoje.**

**Contramedida padrão em bug intermitente:** instrumentar antes de corrigir, em **duas etapas separadas** — Etapa 1 só adiciona logs e **para**; Etapa 2 corrige, só após log reproduzido.

**Contramedida para estado:** quando o fundador afirmar que algo não existe no produto e o log disser que existe, **não concluir por nenhum dos dois** — ler o arquivo. Em 12/Out, as duas afirmações estavam certas: o código existia e era condicional a um objetivo que o fundador não havia escolhido.

---

# PARTE 11 — REGISTRO DE DECISÕES (LOG IMUTÁVEL)

## 11.1–11.7 Histórico (preservado por referência)
Decisões até 16/Jul (HOLD seguradoras; B2B coração; server-side; organizador de dados/SaMD; preços; D1/D2/D3); técnicas de Jul (Edge Function única por header; gate determinístico; casamento léxico; modelo via secret; erro nunca disfarçado; Health Connect READ; pgvector); v6.1 (camadas de interface; onboarding valor-antes-de-fricção; naming); **v7.0 (1–28)** — Nutrição v1.0, M:N, data de nascimento, ANVISA bem-estar/clínico, Mifflin+Katch, TDEE em dois modos, população ≥18, telemetria como construção nova, governança de log; **v8.0 (29–41)** — falhar visível, teste não vira spec, observabilidade, `pushReplacement` proibido, amostragem de dado de IA, 637 alimentos, ordem do catálogo, TBCA antes de carga, ODbL sem parecer, N27+N28+N14 juntos, instrumentar antes de corrigir, fila de revisão com gatilho no beta.

## 11.8 Decisões do v9.0 (12/Out/2026) — preservadas

| # | Decisão |
|---|---|
| 42 | **O Módulo Clínico entrou no produto e sai do BL.1.** Formalizar é mais honesto que fingir backlog. Custo nomeado: a Fase 5 ficou parada |
| 43 | **Linha de três camadas.** Exibir TMB/TDEE: permitido. Sugerir TDEE: permitido. Sugerir déficit + macros sem profissional: **proibido**. Fundamento duplo: SaMD e Lei 8.234/1991 |
| 44 | **N31: ocultar a variante de déficit e os chips MACRO** no fluxo sem profissional; manter no Painel Web |
| 45 | **`buscarSugestaoCalorias()` permanece** — devolve TDEE, não déficit |
| 46 | **O cruzamento de energia é paridade competitiva, não fosso** |
| 47 | **O cartão de visita passa a ser declarado × medido e saldo acumulado × peso real** |
| 48 | **`garmin-gateway` sai do fosso até ser deployada** |
| 49 | **Health Compass sai da lista de concorrentes** até confirmação |
| 50 | **Fibra e sódio entram no catálogo, exibidos sem meta** no app avulso |
| 51 | **Nenhuma foto é persistida.** Linha do tempo de fotos de evolução recusada — **ver emenda na decisão 62** |
| 52 | **Gasto declarado = baseline; gasto medido = fonte do relatório. Nunca somados** |
| 53 | **`widgets_disponibilidade` como tabela M:N**, com `disponivel=false` vencendo a escolha individual |
| 54 | **Seis renderizadores genéricos antes dos 40 widgets** |
| 55 | **Proibida inferência estatística sobre amostra individual** (regra 28) — **revista na decisão 78** |
| 56 | **Histórico alimentar detalhado entra na v1.0** (N35) |
| 57 | **Das 15 funções de concorrente, 8 são B2B e não se aplicam ao avulso**; 6 entram; 1 recusada |
| 58 | **O portão passa a ser o beta de amigos**, não o teste solo |
| 59 | **Documentação de arquivo é parte do código** (regra 27) |
| 60 | **Parte W (catálogo de widgets) fica dentro do Mestre** — catálogo em documento separado foi o que gerou a deriva da decisão 42. **Mantida; ver decisão 76 para o caso das descobertas** |

## 11.9 Decisões desta consolidação (v9.1 — 25/Out a 01/Nov/2026)

| # | Decisão | Motivo |
|---|---|---|
| **61** | **O nome oficial do produto é Orynty** | Definido em 25/Out. O `applicationId` segue `br.com.atleta.app` (R10); domínio, landing e INPI sob o nome novo |
| **62** | **Emenda à decisão 51: persistir ≠ exibir.** Proibido é **gravar** mídia. O preview em memória (`Image.memory`, pipeline RAM volátil) não fere o Zero Storage | A redação original dizia "armazenamento de qualquer natureza" e foi escrita larga demais pelo consultor, condenando um fluxo que já tinha passado pelo teste solo. Erro de redação, corrigido |
| **63** | **Frase-norte de produto:** *"O Orynty não tenta adivinhar o que acontece com você. Ele encontra, nos seus próprios dados, coisas que você ainda não tinha percebido."* | Define posicionamento que é defensável regulatoriamente e verdadeiro tecnicamente ao mesmo tempo |
| **64** | **O fosso ganha dois itens: descobertas com procedência citável, e a biblioteca governada como ativo tecnológico** | Concorrente mostra o número; o Orynty mostra o número com o estudo ao lado. É outra categoria de produto, e é o que torna o Painel Web vendável |
| **65** | **Um catálogo de descobertas com flag `exige_profissional`, não dois catálogos** | A maioria dos índices aparece duas vezes: versão descritiva no app, versão com referência no painel. Um renderizador, uma tela de admin, uma regra de precedência — reusa o mecanismo de `widgets_disponibilidade` |
| **66** | **Pergunta livre em linguagem natural sobre o próprio dado: recusada para esta fase** | Cada pergunta é chamada ao Gemini com o R24 aberto; superfície regulatória nova (toda resposta a "por que durmo mal?" é interpretação); e come um trimestre de um fundador solo que ainda não entregou a Fase 5 |
| **67** | **WHtR entra como índice opcional** — se a medição de cintura existe, o índice aparece; se não, não aparece e não insiste | A circunferência é coletada desde 18/Set e a altura está na anamnese. É uma divisão, e entrega o melhor marcador antropométrico sem exame — que resolve o IMC classificar errado o usuário musculoso |
| **68** | **DUAS FINALIDADES DECLARADAS: bem-estar no app avulso, ferramenta profissional no Painel Web** | A RDC 657/2022 enquadra por finalidade. "Prevenção" é finalidade médica nomeada, então um app cuja finalidade declarada é "saúde preventiva" **não tem acesso à exclusão de bem-estar**. Não custa um único insight: custa a palavra "preventiva" na finalidade do app |
| **69** | **Parecer regulatório com escopo apertado:** confirmar o enquadramento de dois módulos com estas finalidades, estas funcionalidades e esta política de integridade analítica | Com os três documentos em mão é consulta pontual, não projeto |
| **70** | **Linha operacional do R25: alerta diagnostica, espelho descreve.** Desligar a detecção de anomalia; permitir exibir a FC medida e descrever o padrão sem juízo | O R25 embrulhava três coisas diferentes e travava 4 templates que não precisavam estar travados |
| **71** | **Desenho de registro offline:** favoritas offline completas; texto enfileirado cru com o horário da captura; foto e áudio exigem rede; janela de meia-noite de 2–3 h; dois estados pendentes com superfícies diferentes | Enfileirar foto obrigaria gravar mídia em disco e feriria o Zero Storage |
| **72** | **N4 renomeado para "Comparativo multidimensional"; N5 para "Longitudinal descritivo"** | "Associativo" prometia o que a regra proíbe. Vocabulário interno vaza para a interface |
| **73** | **Biblioteca `perguntas_analiticas` em dois níveis de aprovação** | Com 14 perguntas e um revisor que é o próprio fundador não-clínico, a cláusula de revisor viraria teatro. Perguntas de rotina ele aprova; perguntas de fisiologia ficam escritas e inativas |
| **74** | **Cadência: D-1 como gatilho; diário oportunista; semanal e mensal garantidos; cinco tipos de descoberta; nunca criar informação falsa para cumprir meta; padrão mantido fica calado** | Se nada relevante acontecer na terça, a terça não tem descoberta — e a tela não anuncia o silêncio |
| **75** | **O Motor de Descobertas passa à frente dos ~40 widgets de paridade** | Os widgets fazem o Orynty empatar; as descobertas fazem o usuário reagir. Para um beta cuja função é descobrir se o produto merece ser mantido, o fosso vale mais que o empate. **O que escorrega está dito em voz alta na Parte 9.1** |
| **76** | **O catálogo de descobertas é documento separado, com cláusula de subordinação explícita** | 277 templates dobrariam o Mestre e destruiriam sua função de ser anexado em prompt. A lição do `motor_metabolico.txt` não é "nunca separe" — é "documento separado tem que ser **subordinado e referenciado**, nunca paralelo e autoritativo". A cláusula e o ponteiro de versão são o que impede repetir a decisão 42 |
| **77** | **Regras 30 e 31:** variável de template não carrega sentido; frase sobre o registro é SUPORTE | Juntas explicam ~430 das 2.178 entradas descartadas do catálogo v1.2. Sem virar regra, voltam no próximo catálogo |
| **78** | **Regra 28 reescrita:** proíbe publicar número não observado, afirmar vínculo, e escolher comparação pela maior diferença; permite comparar grupos observados sob biblioteca versionada com tamanho mínimo, dispersão exibida e limiar prático | A redação anterior proibia uma *técnica* quando havia dois riscos distintos embrulhados: invalidez do número e ato clínico. Separados, o que travava os N4 era a múltipla comparação — e isso tem conserto por governança |
| **79** | **Recusas explícitas da camada de índices:** ACWR (debunked, Impellizzeri 2020), "SRI" pelo nome (o Orynty tem agregados, não épocas), adaptação metabólica como narrativa (Martins 2020: ~3–4%, não sustentado), conformidade com açúcar livre (a TACO traz açúcares totais) | Recusar o que o mercado vende é posicionamento. "O Orynty não usa ACWR, e aqui está por quê" é uma frase que ganha respeito de um preparador físico |
| **80** | **N30 e N39 executam juntos** — fibra, sódio, NOVA e grupo FAO na mesma passada | Mesma tabela, mesma recarga da TACO, mesma propagação. Duas passadas é recarregar a TACO duas vezes por nada |
| **81** | **Métrica de ultraprocessado invertida: publicar "% de in natura" (NOVA grupo 1), não "% de ultraprocessado" (grupo 4)** | O grupo 1 é inequívoco e dispensa a fronteira 3/4, que exige validação por nutricionista. E "prefira alimentos in natura ou minimamente processados" é a recomendação principal do próprio Guia Alimentar brasileiro. Mesma literatura, zero dependência de parceiro |
| **82** | **Itens que dependem de nutricionista vão para backlog** — a fronteira NOVA 3/4 e os 3 templates de ultraprocessado | Decisão do fundador em 01/Nov. Quando houver parceiro, se solicita a ele. *Correção registrada: o consultor exagerou a dependência na rodada anterior — a TACO já tem coluna de categoria, o que torna o mapa FAO em grande parte uma tradução categoria-a-categoria, e o grupo 4 em rótulo sai por regra de marcadores de ingrediente* |
| **83** | **Não haverá meta hídrica.** `NUT-008` (hidratação × meta) sai da Parte W | Decisão do fundador em 25/Out |
| **84** | **`week_start_day` configurável vai para o backlog** | Escrito e adiado |
| **85** | **`nutrition_target_versions` não será criada** — `objetivos_alimentares` já tem vigência e reconstrói a meta ativa de qualquer data passada | Verificação de 10 minutos confirmou. Tabela nova riscada |
| **86** | **O limiar de publicação de descoberta é prático e declarado por indicador, não estatístico** | Um limiar estatístico seria exatamente a inferência que a Regra 28 proíbe. E não se adota um limiar universal para indicadores de grandezas diferentes |
| **87** | **Bloco permanente de achados de campo na fila**, com prioridade entre o Bloco 1 e o Bloco 2 | O v9.0 não tinha slot para o que o fundador descobre usando o produto, e os 12 achados de outubro não tinham onde morar. Falha de desenho da fila, corrigida |

## 11.10 Decisões desta consolidação (v9.2 — 16/Nov/2026)

| # | Decisão | Motivo |
|---|---|---|
| **88** | **O Motor de Descobertas é construído como RPC no Postgres, não como Edge Function** | Não existe CI/CD: mesclar em `main` nunca deployou uma Edge Function, e isso custou 5 dias em 01/Set e um mês em 16/Out — o modo de falha mais repetido do projeto. RPC vai por migration, que o fluxo já garante. E o Motor é determinístico, sem IA: não há nada nele que precise de Deno. **Reversível e localizada** se o Postgres não der conta de algo |
| **89** | **UAU e Continuous são dois entregáveis separados. E a unidade de trabalho é a família de cálculo, não o template** | Medido: 277 templates são **36 famílias**; os 15 do UAU tocam **9 famílias** que destravam **87 templates (31%)**. O UAU não publica N4 nem N5, logo **não precisa de cadência, agendamento, widget de recente nem dedup no tempo** — metade do motor é do Continuous. Template é linha de tabela; semear depois que a família existe é entrada de dado com amostragem, não desenvolvimento |
| **90** | **O N41 é quebrado em quatro etapas, com o critério de que cada uma é verificável sem a seguinte existir** | O R40 diz que a mitigação do tamanho é "a fundação entrega sozinha". Escrito como uma tarefa, isso não acontece. N41a verifica em SQL, N41b em JSON, N41d inserindo uma linha à mão, N41c rodando duas vezes. A mitigação do R40 passa de **avisada** a **estruturalmente imposta** |
| **91** | **O R6 deixa de ser "rotacionar a Service Role Key" e passa a ser "migrar para `sb_publishable_`/`sb_secret_` e desativar o par legado"** | A Supabase descontinuou as legadas para o fim de 2026, **deixou de permitir rotação** delas, e rotacionar as novas **não desloga ninguém**. O motivo do adiamento de 76 dias — deslogar todo mundo — não se aplica ao caminho correto. E o risco ganha **data imposta por terceiro** |
| **92** | **O `.env` versionado e o CI/CD entram na mesma tarefa da migração de chaves (N44)** | A migração mexe em `.env` de três lugares. Com o `.env` fora do versionamento, ela funciona na máquina do fundador e nasce quebrada em qualquer clone — exatamente o R35. É o momento em que essa dívida cobra |
| **93** | **Tratar HTTP 402 no chamador do Gemini, sem retry e sem fallback** | Com o pré-pago, saldo zerado é erro real em produção. Os dois níveis de modelo falham igual, porque o saldo é da conta de faturamento — retentar ou cair no fallback só faz o usuário esperar mais pela mesma falha, o padrão que o relatório 20260824_0002 já corrigiu uma vez para a cota |
| **94** | **O horário da refeição está confirmado (gravado no início da refeição). O N43 unifica as duas verificações restantes** | 24 templates de hora de refeição voltam a ser viáveis. Restam **tipo de refeição (7)** e **timestamp de sono (22)** — mesma consulta ao schema, uma tarefa só, 29 templates decididos |
| **95** | **R24 encerrado. E fica registrada a lição de processo, não só o fato** | 84 dias parados numa decisão cujo custo medido é da ordem de **US$ 3/mês** — menor que a conta do Supabase. **Decisão barata parada custa mais que decisão errada tomada**; o item que bloqueia tudo entra no Bloco 0 e sai dele por data, não por disposição |
| **96** | **O relatório de fim de tarefa registra a mesclagem, não só a branch** | Os relatórios 102 a 109 não anotam merge; o último registro explícito é de 23/Set. Como a Parte 2.6 depende da fidelidade do log, a lacuna é de processo, não de memória |

## 11.11 Emenda v9.2.1 (16/Nov/2026 — mesmo dia)

**Origem:** segunda opinião pedida pelo fundador sobre a decisão 88, que o consultor havia marcado como reversível. A proposta recebida foi arquitetura híbrida (RPC = núcleo analítico, Edge Function = orquestração). **A decisão 88 é mantida para os Blocos 2 e 3; a proposta vira destino declarado com fronteira; e um ponto dela corrige uma lacuna real do v9.2.**

| # | Decisão | Motivo |
|---|---|---|
| **97** | **Postura de segurança obrigatória para toda RPC do Motor: `SECURITY INVOKER` por padrão, `SET search_path = ''` com nomes qualificados por schema, `REVOKE EXECUTE FROM PUBLIC` + GRANT nominal, `DEFINER` só com justificativa escrita, nenhuma RPC administrativa em schema exposto** | **Lacuna do v9.2, apontada pela segunda opinião e não pelo autor da decisão 88:** o Mestre tinha **zero ocorrências** de `SECURITY INVOKER`, `SECURITY DEFINER` e `search_path`. A regra 20 cobre tabela; função é outra superfície — e `DEFINER` sem `search_path` fixo é escalonamento de privilégio. O Motor é justamente o componente que lê dado agregado. Entra no `[RESTRIÇÕES]` do template de prompt (10.4). Ver D.2.1.1 e antipadrão 13 |
| **98** | **O híbrido RPC + Edge Function é o destino declarado, e a fronteira é notificação e integração externa — não "orquestração". Entra no N46, não no N41/N42. Até lá, agendamento e fila são `pg_cron` + tabela de jobs** | A proposta não menciona deploy, CI/CD nem operador, num projeto sem CI/CD cujo modo de falha mais repetido é o deploy manual (R35: 5 dias em 01/Set, um mês em 16/Out). O Cron já está no stack e o Motor é lote por usuário, não orientado a evento. E **o UAU não tem o que notificar** (D.10.2: sem N4, sem N5, sem cadência). "Orquestração" é critério largo o bastante para justificar qualquer coisa; notificação e integração externa são as duas coisas que o Postgres não faz. Ver D.2.1.2 |

**Registrado contra o consultor:** antipadrões **13** (mover lógica sem levar o modelo de segurança) e **14** (aceitar proposta de arquitetura sem perguntar quem opera). O antipadrão 14 vale para o fluxo inteiro, não só para esta proposta.

**Não alterado pela emenda:** a fila da Parte 9.1, os 277 templates do catálogo (anexo segue em v2.1), as 36 famílias, a quebra do N41 em quatro etapas e a ordem dos blocos. **O N44 continua sendo o primeiro item.**

---

# PARTE 12 — RISCOS CARREGADOS

## 12.1 Encerrados até esta consolidação
- **R24 (era o crítico mais antigo) — ENCERRADO EM 16/NOV, após 84 dias.** `GEMINI_API_KEY` saiu do free tier; projeto em Tier 1. **Custo medido na ordem de US$ 3/mês** para um beta de 10 amigos (≈US$ 0,002 por registro por foto, com a contagem de tokens medida pelo próprio projeto em 15/Set). Dois tetos permanecem e **não removem a lógica de cota**: limite de gasto de US$ 10 em janela rolante de 10 minutos e teto de US$ 250/mês no Tier 1 — o 429 continua possível. **Falta verificar em uso** (2.6). *Lição registrada na decisão 95.*
- **R23 (era o nº1):** invenção silenciosa de quantidade → **encerrado** (N27/N28/N14). Amostragem: 0% de erro claro, 4% questionável.
- **R17:** peso típico hardcoded → **encerrado**.
- **R15:** `GEMINI_API_KEY` duplicada → **encerrado**.
- **R28:** dupla contagem de gasto → **encerrado pela decisão 52**.
- **R26:** fix da navegação da foto sem causa raiz → **encerrado**: o fluxo foi usado no teste solo e nos testes de campo sem reincidência.

## 12.2 Abertos

**Críticos:**
- **R25 (crítico, regulatório):** detecção de anomalia de FC ativa. **Aberta há mais de 3 meses** e agora é **pré-condição da declaração de finalidade** (Parte 5.0), não dívida paralela.
- **R6 (crítico, COM PRAZO — redefinido em 16/Nov):** as chaves `anon` e `service_role` estão **descontinuadas para o fim de 2026** e **não podem mais ser rotacionadas**. O caminho é **migrar** para `sb_publishable_`/`sb_secret_` e desativar o par legado (Parte 6, S8.1 · N44). Agravante original mantido: as legadas voltaram **em texto pleno sem `--reveal`** em 01/Set. **Deixou de ser dívida interna e passou a ter data de terceiro.** Em compensação, a migração **não desloga nenhum usuário** — o motivo do adiamento caiu.
- **R-E4 (alto):** homolog e produção são o mesmo projeto. Antes dos amigos.
- **R43 (alto, NOVO):** **o prazo das chaves é de terceiro e não negociável.** Se a migração não ocorrer e o par legado for desligado pela Supabase, o app e o Painel param ao mesmo tempo. **Mitigação: N44 é o primeiro item do Bloco 1.**
- **R33 (alto):** **a frente B2B inteira de 17 a 27/Set nunca foi testada pelo fundador.** É o coração comercial, 100% em "declarado".
- **R39 (alto, NOVO):** **o consentimento de compartilhamento com o profissional pode existir em código e nunca ter sido exercido.** Dado de saúde é pessoal sensível; o consentimento de instalação não cobre o compartilhamento nominal. Conferência de 4 itens na Parte 5.1.1.

**Médios:**
- **R1 (PAUSADO com motivo):** `security_invoker` na view já foi tentado, quebrou a lista de pacientes e foi revertido de propósito. Corrigir exigiria policy de vínculo em `perfis_usuarios`, que abriria PII pior que o risco.
- **R19:** escopo à frente do roadmap + fôlego do fundador solo. **Materializou quatro vezes**: 23 dias no v8.0; 10 tarefas de Módulo Clínico em setembro; a Fase 5 de widgets, hoje com **103 dias priorizada sem uma linha**; e, entre 01 e 09/Nov, **oito tarefas boas que não eram o Motor de Descobertas**, definido como prioridade máxima em 01/Nov. **A resposta desta consolidação não é um aviso mais forte — é a quebra do N41 em etapas pequenas o suficiente para começarem** (decisão 90). Se o padrão repetir com as etapas quebradas, o problema não é o tamanho da tarefa.
- **R40 (médio):** **o Motor de Descobertas é a maior entrega de uma vez na história do projeto.** **Mitigação agora estrutural, não só declarada:** N41a a N41d, cada uma com aceite que não depende da seguinte (D.10.3), e o UAU separado do Continuous (D.10.2) — o beta precisa de 9 das 36 famílias, não das 36.
- **R44 (médio, NOVO):** **o pré-pago do Gemini zera para tudo de uma vez.** Quando o saldo chega a zero, todas as chaves de todos os projetos daquela conta de faturamento param juntas, com HTTP 402. **Mitigação em duas pontas:** auto-reload com saldo mínimo (S4, Bloco 4.8) e o N45 tratando o 402 com mensagem honesta.
- **R41 (médio, NOVO):** **a análise da Parte D.5** — que libera `N2-FOS-001` e `N2-FOS-002` da Regra 28 — **é do consultor, não de advogado.** São os dois templates de maior valor comercial do catálogo. Se a análise estiver errada, saem. **Mitigação: Bloco 0.2, segunda opinião antes de virar código.**
- **R20:** threshold semântico 0,55. Mitigado pela Anti-Sequestro e pela falha visível em empate.
- **R22:** F09 declarado pronto, nunca visto.
- **R27:** zero teste em `CameraCaptureView`/`CameraCaptureController`.
- **R29:** lacuna de **preparações** no catálogo (637 ingredientes cobrem mal o que o usuário fotografa). Mitigação: caminho de erro visível (feito) e decisão de fonte (TBCA — contato pendente).
- **R34:** **zero cobertura de teste automatizado no Painel Web.**
- **R35 (ELEVADO em 16/Nov):** **sem CI/CD e `.env` não versionado.** A correção do "Convidar Paciente" existe só numa máquina. Edge Function exige deploy manual — já causou 5 dias de teste contra código antigo (01/Set) e um mês contra uma função de 14/Set (16/Out). **Agora virou pré-requisito de um item com prazo:** a migração de chaves (N44) mexe em `.env` de três lugares. **Mitigação dupla:** o `.env` versionado entra na mesma tarefa (decisão 92), e o Motor de Descobertas sai como RPC para não herdar a classe de bug do deploy manual (decisão 88). **Emenda de 16/Nov:** a decisão 98 fixa *quando* a Edge Function volta a ser necessária — notificação ou integração externa, no N46 — de modo que este risco precisa estar **encerrado antes do Continuous**, não antes do Motor. É a diferença entre uma dívida com prazo e uma dívida sem data.
- **R36:** **snapshot do motor só é persistido quando uma meta é salva.** Usuário que faz anamnese e não registra meta fica sem fotografia do cálculo. Afeta os widgets de evolução **e os N5 de composição**.
- **R37:** **biblioteca de fórmulas não é tabela.** Versionamento no JSON de saída fere a regra 16. TMB-003 não confirmada.
- **R3/R4/R14:** trial por `created_at`; backfill nasce pendente; cadastro social sem perfil.

**Baixos:**
- **R32:** `health` travado em **13.3.1**. A 13.3.2 quebra `:health:compileDebugKotlin`. **Não subir sem testar build real** (`flutter analyze` e `flutter test` não invocam o compilador Kotlin).
- **R30:** iOS gerado, nunca compilado.
- **R31:** buraco no histórico de telemetria (13–17/Ago).
- **R38:** banner de validade da anamnese ausente na Tela Senior; dispensa de alertas não persiste entre sessões.
- **R42 (NOVO):** **pendência de conhecimento sobre a Resolução CFM 2.454/2026** (uso de IA na medicina). Não confirmada pelo consultor. Não é bloqueador hoje porque o Painel Web não gera recomendação clínica por IA; **deve ser lida por quem der o parecer antes de qualquer apoio à decisão clínica por IA.**
- **R10/R11/R12/R21:** `applicationId` (`br.com.atleta.app` **não acompanha o nome Orynty**), dívida Kotlin, pausa por inatividade, performance como precedente.
- **F15:** seed sem exames/anomalias.

---

# PARTE W — CATÁLOGO DE WIDGETS (semeadura da Fase 5)

> **Como ler.** `AV` = avulso · `AC` = paciente acompanhado · `PR` = profissional. `✅` ligado por padrão · `○` disponível, desligado · `—` indisponível para o papel.
> **Classificação:** `P` paridade competitiva · `D` diferencial · `D+` não encontrado em nenhum concorrente.
> **Renderizador:** `num` · `serie` · `meta` · `dupla` · `pilha` · `lista`. Widgets marcados `própria` têm lógica dedicada.
> Todos são **Nível 1** (SQL em tempo real) salvo indicação.
> **Mantida dentro do Mestre pela decisão 60.**

## W.1 Nutrição (NUT)

| Código | Widget | AV | AC | PR | Cls | Rend. |
|---|---|---|---|---|---|---|
| NUT-001 | Consumo × meta do dia (kcal) | ✅ | ✅ | ✅ | P | meta |
| NUT-002 | Consumo × meta por macro | ✅ | ✅ | ✅ | P | meta |
| NUT-003 | Série de consumo no período | ○ | ✅ | ✅ | P | serie |
| NUT-004 | Distribuição percentual de macros | ○ | ○ | ✅ | P | pilha |
| NUT-005 | Açúcares no dia | ○ | ○ | ○ | P | num |
| NUT-006 | Diário alimentar do dia | ✅ | ✅ | ✅ | P | lista |
| NUT-007 | Hidratação do dia | ✅ | ✅ | ○ | P | num |
| ~~NUT-008~~ | ~~Hidratação × meta~~ | — | — | — | — | **removido (decisão 83)** |
| NUT-009 | Aderência à meta (% de dias dentro) | ○ | ✅ | ✅ | P | num |
| NUT-010 | Refeições registradas por dia | ○ | ○ | ✅ | P | serie |
| NUT-011 | Fibra e sódio no dia | ○ | ○ | ✅ | P | num |
| **NUT-012** | **Histórico alimentar detalhado** (N35) | ✅ | ✅ | ✅ | **D** | própria |
| **NUT-013** | **Perfil in natura do dia** (NOVA grupo 1) — NOVO | ○ | ✅ | ✅ | **D+** | num |
| **NUT-014** | **Variedade alimentar** (grupos FAO no dia) — NOVO | ○ | ✅ | ✅ | **D+** | num |

## W.2 Antropometria (ANT)

| Código | Widget | AV | AC | PR | Cls | Rend. |
|---|---|---|---|---|---|---|
| ANT-001 | Peso atual + variação | ✅ | ✅ | ✅ | P | num |
| ANT-002 | Série histórica de peso | ✅ | ✅ | ✅ | P | serie |
| ANT-003 | IMC | ○ | ○ | ✅ | P | num |
| ANT-004 | Composição corporal (massa magra / % gordura) | ○ | ✅ | ✅ | P | num |
| ANT-005 | Série de composição corporal | ○ | ✅ | ✅ | P | serie |
| ANT-006 | Água corporal | ○ | ○ | ○ | P | num |
| ANT-007 | Circunferências (cintura/quadril) | ○ | ○ | ✅ | P | serie |
| **ANT-008** | **Relação cintura-estatura (WHtR)** — NOVO (N38) | ○ | ✅ | ✅ | **D** | num |
| **ANT-009** | **Índice de massa magra (FFMI)** — NOVO | ○ | ○ | ✅ | **D** | num |

## W.3 Telemetria — atividade (TEL)

| Código | Widget | AV | AC | PR | Cls | Rend. |
|---|---|---|---|---|---|---|
| TEL-001 | Passos do dia | ✅ | ✅ | ○ | P | num |
| TEL-002 | Série de passos | ○ | ✅ | ✅ | P | serie |
| TEL-003 | Andares subidos | ○ | ○ | ○ | P | num |
| TEL-004 | Distância percorrida | ○ | ○ | ○ | P | num |
| TEL-005 | Calorias ativas | ✅ | ✅ | ✅ | P | num |
| TEL-006 | Calorias totais do dia (**medidas**) | ○ | ✅ | ✅ | **D** | num |
| TEL-007 | Calorias basais | ○ | ○ | ○ | P | num |
| TEL-008 | Treinos da semana | ✅ | ✅ | ✅ | P | lista |
| TEL-009 | Volume semanal | ○ | ✅ | ✅ | P | serie |
| TEL-010 | Distribuição por modalidade | ○ | ○ | ✅ | P | pilha |
| TEL-011 | Mapa de rota do treino | ○ | ○ | ○ | P | própria |
| TEL-019 | Velocidade média/máxima por treino | ○ | ○ | ○ | P | serie |
| **TEL-020** | **Movimento fora do treino** — NOVO | ○ | ✅ | ✅ | **D+** | serie |
| **TEL-021** | **Carga de treino da semana (TRIMP)** — NOVO | ○ | ○ | ✅ | **D** | serie |

## W.4 Telemetria — cardíaco e sono — *onde o B2B brasileiro não chega*

| Código | Widget | AV | AC | PR | Cls | Rend. |
|---|---|---|---|---|---|---|
| TEL-012 | FC média do dia | ○ | ○ | ○ | **D** | num |
| TEL-013 | FC máxima | ○ | ○ | ○ | **D** | num |
| TEL-014 | FC de repouso + média móvel | ○ | ✅ | ✅ | **D** | serie |
| TEL-015 | Arquitetura do sono (leve/profundo/REM/acordado) | ✅ | ✅ | ✅ | **D** | pilha |
| TEL-016 | Série de sono total | ○ | ✅ | ✅ | **D** | serie |
| TEL-017 | Eficiência do sono | ○ | ○ | ✅ | **D** | num |
| TEL-018 | Despertares noturnos | ○ | ○ | ○ | **D** | serie |
| **TEL-022** | **Horário de dormir e de acordar** — NOVO (N37) | ○ | ✅ | ✅ | **D+** | serie |

**Trava desta seção:** nenhum widget de FC exibe faixa de referência, zona rotulada ou juízo clínico (decisão 70). Espelho descreve; alerta diagnostica.

## W.5 Cruzamentos (CRZ)

| Código | Widget | AV | AC | PR | Cls | Rend. |
|---|---|---|---|---|---|---|
| CRZ-001 | Saldo energético diário | ✅ | ✅ | ✅ | **P¹** | meta |
| CRZ-002 | Saldo energético acumulado | ○ | ✅ | ✅ | **D** | serie |
| **CRZ-003** | **Saldo acumulado × peso real** | ✅ | ✅ | ✅ | **D+** | própria |
| **CRZ-004** | **Declarado × medido (atividade)** | ✅ | ✅ | ✅ | **D+** | própria |
| CRZ-005 | Proteína/kg × massa magra no tempo | ○ | ✅ | ✅ | **D** | dupla |
| CRZ-006 | Dia de treino × dia de descanso (consumo) | ○ | ✅ | ✅ | **D** | pilha |
| **CRZ-007** | **Última refeição × início do sono** | ✅ | ✅ | ✅ | **D+** | dupla |
| **CRZ-008** | **Açúcares × sono (dia seguinte)** | ○ | ✅ | ✅ | **D+** | dupla |
| CRZ-009 | Carga de treino × FC repouso × sono | ○ | ✅ | ✅ | **D** | dupla |
| CRZ-010 | Hidratação × calorias ativas | ○ | ○ | ○ | **D** | dupla |
| CRZ-011 | Padrão por dia da semana | ○ | ✅ | ✅ | **D** | pilha |
| CRZ-012 | Distribuição calórica ao longo do dia | ○ | ○ | ✅ | **D** | pilha |
| CRZ-013 | Janela alimentar | ○ | ○ | ○ | **D** | num |
| **CRZ-014** | **Relação ritmo/esforço por modalidade** | ○ | ○ | ✅ | **D+** | serie |
| CRZ-015 | Evolução de desempenho por modalidade | ○ | ✅ | ✅ | **D** | serie |
| **CRZ-016** | **Linha do tempo sobreposta** | ✅ | ✅ | ✅ | **D+** | própria |
| CRZ-017 | Glicemia / pressão na linha do tempo | ○ | ✅ | ✅ | **D** | serie |
| CRZ-018 | TMB / basais / ativas empilhadas | ○ | ○ | ✅ | **D** | pilha |
| **CRZ-019** | **Calculado × Meta × Observado** (ME-006) | ○ | ✅ | ✅ | **D+** | própria |
| **CRZ-020** | **Jejum noturno** — NOVO | ○ | ✅ | ✅ | **D+** | num |

¹ CRZ-001 é **paridade**: MyFitnessPal + Garmin entregam desde 2015.

**Trava obrigatória desta seção.** Todos são **descritivos**: mostram os números lado a lado e a relação aritmética. Nenhum explica causa, prevê valor futuro ou recomenda conduta. CRZ-003 **nunca converte saldo em peso previsto** (a regra das 7.700 kcal/kg é grosseira; em 30 dias o ruído supera o sinal). CRZ-004 **nunca julga** o usuário. CRZ-017 nunca interpreta número clínico ao avulso. **Aplicam-se integralmente as proibições da Regra 28 revista.**

## W.6 Qualidade e confiança do dado (QLD)

| Código | Widget | AV | AC | PR | Cls | Rend. | Nota |
|---|---|---|---|---|---|---|---|
| QLD-001 | Completude (dias com telemetria + registro) | ✅ | ✅ | ✅ | **D+** | num | `processar_medias_smartwatch` já devolve `percentual_confiabilidade` |
| QLD-002 | Itens estimados no período | ○ | ✅ | ✅ | **D+** | num | flag de estimativa do N27 |
| QLD-003 | Fonte vencedora do dia | ○ | ○ | ✅ | **D+** | lista | hierarquia de fontes |
| QLD-004 | Última sincronização do wearable | ✅ | ✅ | ✅ | **D** | num | |
| QLD-005 | Score de qualidade do período | ○ | ○ | ✅ | **D+** | num | `qualidade.score` já é devolvido pelo motor V1 |
| **QLD-006** | **Cobertura de classificação de alimento** — NOVO | ○ | ✅ | ✅ | **D+** | num | obrigatório ao lado de qualquer número NOVA/FAO (`SUP-012`) |

Esta família é a regra 29 na camada visual. **O produto que diz onde não sabe é o que ganha a confiança do profissional** — e é exatamente o que falta no líder de mercado, cujo saldo acumula dupla contagem sem avisar ninguém.

## W.7 Painel do profissional (PRO)

| Código | Widget | AV | AC | PR | Cls | Rend. |
|---|---|---|---|---|---|---|
| PRO-001 | Lista de pacientes | — | — | ✅ | P | lista |
| PRO-002 | Aderência por paciente (ranking) | — | — | ✅ | P | lista |
| PRO-003 | Semáforo de engajamento | — | — | ✅ | P | lista |
| **PRO-004** | **Risco de abandono por queda de atividade** | — | — | ✅ | **D+** | própria |
| PRO-005 | Metas vencendo (vencidas / 30d / 7d) | — | — | ✅ | P | lista |
| **PRO-006** | **Pacientes com dado incompleto** | — | — | ✅ | **D+** | lista |
| PRO-007 | Antes × depois da prescrição | — | — | ✅ | **D** | dupla |
| PRO-008 | Histórico de prescrições com resultado | — | — | ✅ | **D** | lista |
| PRO-009 | Adesão por macro | — | — | ✅ | **D** | meta |
| PRO-010 | Timeline consolidada para a consulta | — | — | ✅ | **D** | própria |
| **PRO-011** | **Confiabilidade do autorrelato** (CRZ-004 clínico) | — | — | ✅ | **D+** | própria |
| PRO-012 | Resultado do Motor Metabólico V1 | — | — | ✅ | P | própria |
| **PRO-013** | **Disponibilidade energética do paciente** — NOVO | — | — | ✅ | **D+** | serie |
| **PRO-014** | **Descobertas publicadas ao paciente** — NOVO | — | — | ✅ | **D+** | lista |

## W.8 Nível 3 — IA, pago, só profissional (backlog)

IA-001 resumo da semana em linguagem natural · IA-002 detecção de padrão entre variáveis · IA-003 explicação de anomalia · IA-004 previsão de adesão e risco de abandono · IA-005 qualidade da refeição além do macro · IA-006 recomendação adaptativa de meta.

**Nenhum entra na v1.0.** Cadastrados com `disponivel = false` em todos os papéis, para o catálogo nascer completo. **Qualquer um deles exige a leitura da CFM 2.454/2026** (R42) antes de sair do backlog.

## W.9 Semeadura recomendada — ligados por padrão no avulso

**Paridade (não gastar design):** NUT-001, NUT-002, NUT-006, NUT-007, ANT-001, ANT-002, TEL-001, TEL-005, TEL-008, CRZ-001.
**Diferencial (onde vai o capricho):** NUT-012, TEL-015, CRZ-003, CRZ-004, CRZ-007, CRZ-016, QLD-001, QLD-004.

Todo o restante entra cadastrado com `ativo_padrao = false`, disponível para ligar sem tarefa de código.

## W.10 Funções de concorrente que NÃO são widget

| Função | Quem tem | Decisão |
|---|---|---|
| Chat profissional ↔ paciente | Dietbox, Nutrium, Nutrio | **Backlog priorizado** — importante para o B2B |
| Lembretes de refeição e hidratação | Nutrium, Dietbox | Entra com a gamificação (Bloco 5) |
| Metas semanais de atividade | Nutrium | Entra com a gamificação |
| Lista de compras | Dietbox, Nutrio, VibeFit | **Não se aplica ao avulso** — deriva de cardápio prescrito |
| Receitas passo a passo | Nutrium, Dietbox | Backlog |
| Repositório de exames | Nutrio | Já previsto (`anamneses_exames_laboratoriais`) |
| Exportação PDF do plano | todos | F16, backlog — é o loop viral B2B |
| **Linha do tempo de fotos de evolução** | VibeFit, Nutrium | **RECUSADO** (decisão 51) — conflita com Zero Storage |
| Videoconferência, agendamento, gestão financeira, prescrição de suplementos, periodização de treino | Dietbox, VibeFit | **B2B ou fora de escopo** |
| Journal de hábitos com impacto | WHOOP | Versão B, backlog |
| Glicemia contínua (CGM) | Oura + Dexcom | Fora de escopo; peso regulatório alto |
| **Pergunta livre sobre o próprio dado** | — | **RECUSADO para esta fase** (decisão 66) |

## W.11 Dados que faltam coletar

| Dado | Destrava | Prioridade |
|---|---|---|
| **Timestamp de início e fim do sono** | **22 templates de descoberta**, incluindo o melhor do catálogo | **Máxima — Bloco 1 (N37)** |
| **Colunas NOVA e grupo FAO** | 13 templates, NUT-013, NUT-014, QLD-006 | **Alta — Bloco 1 (N39), junto do N30** |
| **Fibra e sódio** (N30) | NUT-011 e 4 templates | **Alta — Bloco 1** |
| **Cintura já coletada, índice não calculado** | ANT-008, 4 templates | **Alta — Bloco 1 (N38), é uma divisão** |
| **Passos intradiários** | 2 templates (cadência de pico) | Média — verificar se já é gravado granular |
| **Humor / energia percebida** | Cruzamento com sono e consumo. Uma pergunta de um toque, opt-in (regra 7.2) | Média |
| **HRV persistido** | Recuperação. Aparece no diagnóstico; **confirmar se é gravado** | Média |
| **Zonas de FC por treino** | Intensidade real (hoje há média/mín/máx, falta tempo em zona) | Média |
| **Esforço percebido pós-treino (1–10)** | Separa "treino pesado" de "dia ruim"; e destravaria o TRIMP de Foster completo | Média |
| SpO2 e FC noturna | Pilar de sono | Baixa |
| Micronutrientes completos | Qualidade nutricional profunda | Backlog |
| **Exames laboratoriais interpretados** | A camada de nutrologia (Parte 5.0) | **Parado por decisão do fundador em 01/Nov** |

---

# PARTE V1 — ESPECIFICAÇÃO EXECUTÁVEL

> Blocos A–K estão **entregues**. Abaixo, só o que tem trabalho pendente.

## [PENDENTE] R25 — Desligar a detecção de anomalia de FC
Desligar detecção e alerta. Auditar as telas para garantir que nenhuma exibe faixa de referência de FC, zona de treino rotulada ou juízo clínico. Registrar a linha alerta/espelho (5.2.2) no log.
**Aceite:** nenhuma tela do app avulso usa as palavras "atenção", "alerta", "fora do normal" ou "risco" em relação a FC; a FC medida continua visível.

## [PENDENTE] N44 — Migração das chaves Supabase + `.env` versionado + CI/CD · **COM PRAZO**

**Primeiro item do Bloco 1.** Procedimento completo na Parte 6, S8.1. Quatro passos: criar as novas (fundador), trocar a publishable no cliente (Claude Code), trocar a secret no backend (Claude Code), desativar o par legado (fundador, por último).

**Na mesma tarefa, obrigatoriamente (decisão 92):** `web_painel/.env` sai do `.gitignore` e passa a ser versionado como o próprio `.env.example` já documenta, e entra um workflow mínimo de CI/CD. Sem isso a migração funciona numa máquina e nasce quebrada em qualquer clone — e a correção do endpoint de "Convidar Paciente" que vive só na máquina do fundador é a prova de que isso já acontece.

**Fora de escopo, declarado:** a migração do JWT secret legado para chaves assimétricas é **outra coisa e é opcional, sem prazo**. Não misturar.

**Aceite, em duas partes.** Depois do passo 3: o app e o Painel funcionam com as chaves novas, **com as legadas ainda ativas** — se algo quebrar, a volta é trocar a variável. Depois do passo 4: o app e o Painel continuam funcionando com o par legado **desativado**, e um clone novo do repositório sobe sem edição manual de `.env`.

## [PENDENTE] N45 — Tratar HTTP 402 no chamador do Gemini
Em `criarChamadorGeminiComFallback`: 402 ganha classe de erro própria, **não é retentado e não cai no fallback** (o saldo é da conta de faturamento — os dois níveis falham igual). Mensagem final honesta sobre pagamento pendente, no mesmo lugar onde o `ErroCotaGemini` já vive. **Nunca "Servidor Ocupado"** — é exatamente a mentira que o relatório 20260901_0003 corrigiu.
**Aceite:** simular 402 e ver a mensagem própria, uma única tentativa, sem degradar para o LITE.

## [PENDENTE] N43 — Timestamp de sono e tipo de refeição (**uma investigação, dois campos**)

**Etapa 1 — só relatar, sem alterar.** Duas perguntas na mesma consulta ao schema:
1. Em `metricas_saude_diarias` (e na função que recebe o Health Connect): os instantes de **início e fim do sono** são persistidos, ou só as durações em minutos? No Flutter, o `SleepSessionRecord` chega com `startTime`/`endTime` e eles são descartados após somar? **Decide 22 templates, incluindo o melhor do catálogo.**
2. Em `coleta_diaria`: a linha de refeição guarda o **tipo** (café/almoço/jantar) nos **quatro** métodos de registro, ou só nas favoritas? Está na coluna ou dentro do `valor_jsonb`? **Decide 7 templates.**

**Relatório, sem código.** *Nota: o horário da refeição já está confirmado — é gravado no início da refeição (decisão 94). Não é objeto desta investigação.*

**Etapa 2 — só após o relatório.** Três decisões que precisam estar na tarefa:
- **Guardar cru, derivar na consulta** (G.9). Persistir `sono_inicio` e `sono_fim` com o offset de fuso do momento da coleta. **Não** assar na gravação a regra de "a qual noite esse sono pertence" — ela muda conforme a descoberta.
- **Consolidação de segmentos declarada.** O Health Connect devolve várias sessões por noite com frequência. Regra em config: unir segmentos separados por menos de X minutos. Se a união ficar ambígua, **regra 23 — falhar visível**.
- **Sono que atravessa a meia-noite** já é tratado para outras métricas; reaproveitar, não reinventar.

**Aceite:** registrar uma noite e ver, no banco, o instante de início e de fim com o fuso, e a noite atribuída corretamente quando o sono atravessa a meia-noite. E registrar uma refeição por cada um dos quatro métodos e ver o tipo gravado nas quatro.

## [PENDENTE] N38 — WHtR opcional
Confirmar em qual bloco da anamnese está a circunferência de cintura; se existe, **não criar campo**. `WHtR = cintura_cm ÷ altura_cm`, altura da anamnese versionada (SSOT). **Faixas em `faixas_whtr`** (limite inferior, superior, rótulo, versão, fonte NICE NG7 2022) — regra 16. **Fidelidade à fonte:** as faixas valem para IMC abaixo de 35; acima disso, exibir o número e **omitir a faixa**. **Idade do dado declarada** (regra 29): data da medição ao lado. Texto descritivo, **sem conselho** — o número e o rótulo da faixa, nunca "você deveria". Disponível no app e no Painel Web.
**Aceite:** com cintura preenchida, o índice e a faixa aparecem com a data da medição; sem cintura, nada aparece e nada é pedido insistentemente.

## [PENDENTE] N30 + N39 — Fibra, sódio, NOVA e grupo FAO (**mesma passada**)
Quatro colunas em `alimentos_referencia` (`fibra_100`, `sodio_100`, `grupo_nova`, `grupo_fao`), recarga da TACO, propagação até a resposta HTTP e ao Flutter pelo mesmo caminho que `categoria_consumo` percorreu em 23/Ago.
- **Fibra e sódio: exibir sem meta** no app avulso (decisão 50). Meta exigiria fórmula explícita.
- **Grupo FAO (1–10):** o mapa vem em grande parte da **própria coluna de categoria da TACO** — é tradução categoria-a-categoria, não curadoria item a item.
- **Grupo NOVA (1–4):** a TACO é quase toda in natura e preparação caseira; grupo 4 praticamente não existe nela. **A fronteira 3/4 em itens preparados vai para backlog** (decisão 82). A métrica publicada é **"% de in natura" (grupo 1)**, inequívoca (decisão 81).
- **Regra 26 aplicável:** dado classificado por IA em massa exige amostragem humana.
**Aceite:** registrar um prato e ver fibra, sódio, perfil in natura e grupos alimentares no total do dia, com a cobertura de classificação declarada.

## [PENDENTE] N40 — Classificação automática em três camadas
Para alimento criado pelo usuário, lido de rótulo, ou vindo de recarga:
1. **Herança por similaridade** — pgvector (já existe com HNSW). Vizinhos mais próximos no catálogo curado; se a similaridade passa o limiar **e** os N vizinhos concordam, herda. Limiar e N em config.
2. **Regra determinística para NOVA 4** — o grupo 4 se define pela **lista de ingredientes**, não pelos nutrientes. Tabela `marcadores_ultraprocessamento` (aromatizante, corante, emulsificante, espessante, xarope de milho, proteína isolada, gordura hidrogenada, realçador de sabor). O OCR de rótulo já lê essa lista. **Auditável, sem IA, regra 16.**
3. **IA só quando 1 e 2 não decidem** — e então o campo fica **nulo e marcado como pendente**, o item vai para a fila de revisão (BL.1), e **o alimento não sai do cálculo em silêncio**: a métrica declara a cobertura (`SUP-012`, QLD-006).

> **Por que a camada 3 é crítica.** Se 18% das calorias vêm de alimentos não classificados e o insight diz "58% das suas calorias vêm de in natura", **o número mente**. É o mesmo padrão do `encontrarMedida` — arbitrar dado não resolvido em silêncio — em outra família. **Regra 23.**

**Aceite:** criar um alimento novo e ver a classificação herdada; criar um que não casa com nada e ver o campo pendente, o item na fila, e a cobertura declarada no número do dia.

## [PENDENTE] N31 — Ocultar prescrição no fluxo sem profissional
Em `resultado_motor_metabolico_page.dart`: condicionar a linha 302 a `energiaRecomendacao.estrategia == 'manutencao'` e ocultar o `_buildProtocoloSelector` (linha 355) quando não houver acompanhamento profissional. **Corrigir o cabeçalho do arquivo** (linhas 20–24), que afirma o oposto do que o código faz. O Painel Web não muda.
**Aceite:** anamnese com objetivo "perder peso" → a tela mostra TMB, TDEE e qualidade, **sem** card de déficit e **sem** chips de protocolo; os 4 campos continuam em branco e editáveis.

## [PENDENTE] N41a — Motor: as 4 tabelas
`templates_descobertas`, `perguntas_analiticas`, `limiares_praticos`, `descobertas_publicadas` (campos na Parte D.2) + semear `limiares_praticos` com os 8 valores iniciais. **Migration pura, zero lógica.** RLS + policy por `auth.uid()` + **GRANT explícito** em todas as quatro.
**Aceite:** inserir uma linha em `templates_descobertas` e consultá-la. Baixar o limiar de um indicador na tabela e ver o valor mudar. Nada de app envolvido.

## [PENDENTE] N41b — Motor: avaliador de gates como função pura
RPC (decisão 88) que recebe usuário e janela e devolve os candidatos que **passaram** os gates G1–G3, cada um com cobertura, dispersão e os valores calculados. **Função pura: não grava, não publica, não escolhe.** Observabilidade da regra 22: log de conclusão com duração e contagem de candidatos avaliados.
**Aceite:** rodar contra o próprio usuário do fundador e ler o JSON de saída. Um candidato cuja diferença fica abaixo do limiar prático **não aparece na lista**.

## [PENDENTE] N41c — Motor: seleção, deduplicação e cadência
**Opcional para o UAU, obrigatória para o Continuous** (D.10.2). Grava em `descobertas_publicadas`. Deduplicação por `semantic_key` (métrica, comparação, método, direção, janela). **O motor nunca ordena candidatos por tamanho da diferença** (regra 28, proibição 3) — a seleção decorre de relevância pré-declarada, objetivo da anamnese, novidade e diversidade.
**Aceite:** rodar duas vezes seguidas e confirmar que nada republica. Mudar o número na terceira casa decimal e confirmar que **continua** não republicando.

## [PENDENTE] N41d — Motor: renderizador de cartão em 4 camadas
Título, corpo, contexto, procedência (Parte 8.5), lendo uma linha de `descobertas_publicadas`. **Decisão aberta nesta tarefa:** se a substituição das `{variáveis}` acontece no Postgres ou no cliente — **preferência registrada pelo Postgres**, para que o texto publicado seja exatamente o que a tabela guarda.
**Aceite:** inserir uma linha à mão em `descobertas_publicadas` e ver o cartão na tela, com contexto e cobertura, **sem tocar em código**.

## [PENDENTE] N42 — As 9 famílias de cálculo + os 15 templates do UAU
Catálogo de Descobertas, seção 12. Treze N3, um N2 e um N1 de rodapé, sobre a carga inicial de 30 dias, em 6 telas lógicas com até 3 descobertas cada. **Nenhum N5** (precisa de duas janelas) e **nenhum N4** (grupo mínimo não fecha em 30 dias de forma confiável).

**A unidade de trabalho é a família, não o template** (D.10.1). As 9 famílias que os 15 templates exigem: concentração, estrato semanal, dia específico, dispersão, faixa habitual, distribuição interna, intervalos, repertório alimentar, e o fosso. Escritas, elas destravam **87 templates (31% do catálogo)** para semeadura posterior por `INSERT`.
**Aceite:** gerar o UAU de um usuário com 30 dias de carga e ler as 6 telas, conferindo que cada frase está em português natural, que nenhuma usa linguagem de alerta, e que a cobertura aparece no contexto de cada cartão.

## [PENDENTE] N46 — O Continuous
Gates G4/G5; `perguntas_analiticas` semeada com as 14 perguntas (5 `aprovado_fundador`, 9 `pendente_revisor`, estas com `ativo=false`); cadência com os cinco tipos (D.7); widget de descoberta recente com a data dela e a regra de **nunca anunciar o silêncio** (`SUP-019`); e os lotes de família na ordem da D.10.4.
**Aceite:** passar uma semana sem nada relevante e confirmar que a tela **não** publica cartão vazio nem mensagem de ausência — mostra a descoberta anterior com a data dela.

## [PENDENTE] N32 — `widgets_disponibilidade`
Tabela e tela de admin conforme 3.4.1. `disponivel = false` vence a configuração individual.
**Aceite:** desligar um widget para o papel avulso no admin e confirmar que ele some do app, mesmo estando ligado na configuração pessoal.

## [PENDENTE] N33 — Seis renderizadores genéricos
`num`, `serie`, `meta`, `dupla`, `pilha`, `lista`. Cada um lê `catalogo_widgets.parametros` (jsonb). **Nenhum conhece widget específico.**
**Aceite:** criar um widget novo inserindo uma linha no banco, sem tocar em código.

## [PENDENTE] N34 — Semeadura do catálogo de widgets
As linhas da Parte W, com `widgets_disponibilidade` por papel e `ativo_padrao` conforme W.9.

## [PENDENTE] N35 — Histórico alimentar detalhado
Navegação dia → refeição → itens → nutrientes, com as atividades do mesmo dia ao lado. O dado já está em `coleta_diaria` (`valor_jsonb` por refeição) e em `atividades_fisicas_treinos`. **Itens estimados carregam a marca** (regra 29).
**Aceite:** abrir um dia de duas semanas atrás e ver cada refeição com seus itens, nutrientes e horário, e os treinos daquele dia.

## [PENDENTE] N36 — Os seis cruzamentos de lógica própria
CRZ-003, CRZ-004, CRZ-007, CRZ-008, CRZ-014, CRZ-016 — mais CRZ-019 quando o R36 for resolvido, e CRZ-020 (jejum noturno) quando o N37 fechar.
**Pré-requisito resolvido:** decisão 52.
**Aceite:** ver o saldo acumulado contra a curva real de peso, e a rotina declarada contra os treinos medidos, com a marca de estimativa onde couber.

## [PENDENTE] N23 — Resumo semanal/mensal · [PENDENTE] N24 — Onboarding
Resumo simples no app (o rico/sazonal é F23, backlog). Onboarding "valor antes de fricção": tela de valor em ~5s, bifurcação "usa relógio?" em ~10s, primeiro cartão, e só depois o resto do perfil.

---

# PARTE BL — BACKLOG CONSOLIDADO

## BL.1 Nutrição e produto adiados

| Item | Motivo | Gatilho |
|---|---|---|
| **Fila de revisão de alimentos criados pelo usuário** (escopo pessoal/global, `criado_por`, `status_revisao`, `fonte='estimativa_ia'`, dedup por semântica frouxa, diário imutável, gate de sanidade 4/4/9, `alimento_canonico_id` reservado) — **agora também recebe os itens com NOVA/FAO pendentes (N40)** | Com um usuário só, o fundador é revisor e revisado | **Beta de amigos — Bloco 4.4** |
| **Fronteira NOVA grupo 3 × grupo 4 em itens preparados** + os 3 templates de ultraprocessado | Exige validação por nutricionista (decisão 82). A métrica liberada é "% de in natura" (decisão 81) | **Quando houver parceiro nutricionista** |
| **Camada de nutrologia** — exames laboratoriais exibidos e organizados no Painel Web, cruzados com a telemetria no tempo | Interpretar exame é ato médico; exibir e organizar não é. O Painel Web **não interpreta** — o nutrólogo interpreta | **Decisão do fundador: parado em 01/Nov** |
| **Pergunta livre em linguagem natural** | Decisão 66: R24 aberto, superfície regulatória nova, custo de um trimestre | Depois do beta e com billing resolvido |
| **`week_start_day` configurável** | Decisão 84 | — |
| **Chat profissional ↔ paciente** | Função de concorrente relevante ao B2B | Fase 2 B2B |
| Motor Adaptativo (recalibração de metas) | Item mais caro; risco ANVISA ao avulso | Pós-validação, só caminho profissional |
| Motor de Qualidade dos Dados (score global) | Insumo do Motor Adaptativo | Junto dele |
| Motor de Indicadores clínicos (HbA1c, lipídico, renal, HRV, VO₂) | Fora do bem-estar | Com demanda clínica |
| Motor de Protocolos Clínicos / IA Clínica | Conformidade; **exige a CFM 2.454/2026** (R42) | Pós-validação |
| Fórmulas FM-101+ (Harris-Benedict, Owen, Schofield, Henry, IOM) | V1 = Mifflin/Katch/Cunningham | População específica |
| **Biblioteca de fórmulas como tabela** (R37) + TMB-003 | Hoje o versionamento vive no JSON | Quando o profissional precisar escolher a fórmula |
| **NEAT estimado** | Falta fonte de dado; o motor usa PAL | Quando houver coleta de rotina adequada |
| **Cadência de pico de 30 minutos** | Depende de passos intradiários | Se a granularidade existir |
| **HRV** | Persistência nunca confirmada | Confirmar primeiro |
| Granularidade do consentimento (F37-fase2) | V1 usa binário | Escopo por tipo de dado |
| Endereço no cadastro | Não usado | Faturamento/CNPJ |
| Relatório rico/sazonal (F23) | V1 traz resumo simples | Pós-validação |
| Predições, benchmark populacional, indicadores compostos | Não necessárias | Pós-PMF |
| **Suporte iOS** | Sem Mac/Xcode | Quando houver ambiente |
| **Testes de `CameraCaptureView`** (R27) e **suíte de componente do Painel Web** (R34) | Mockar `CameraController` não é trivial; Painel sem suíte | Antes do beta de amigos |
| **Linha do tempo de fotos de evolução** | **RECUSADO** (decisão 51) — conflita com Zero Storage | Só com decisão explícita de reabrir storage |

*Nota: o **Módulo Clínico** saiu deste backlog pela decisão 42 — está construído e é escopo vigente (Parte 2.4).*

## BL.2 Gamificação / motor viral (Bloco 5)
F43 (Retrospectiva de Boas-Vindas, Cartão da 1ª Semana, Retrospectiva Mensal), pontos sociais, streak, ligas (F38), widget streak+anel (F18), válvula anti-culpa (F19), mensagens de ciclo do vínculo (F39), **lembretes de refeição e hidratação**, **metas semanais de atividade**. **Gatilho: depois do Motor de Descobertas, da Fase 5 de widgets e da higiene do Bloco 4.**

## BL.3 Ondas futuras
Exportação PDF+CSV / loop viral B2B (F16) · Alerta de tendência não-clínico (F17) · Modo Cuidador (F20) · Relatórios sazonais (F23) · Ciclo menstrual (F44) · Prescrição de treino + Garmin em produção · 2FA do painel (F25) · Deep link WhatsApp (F27) · `logs_acesso` populado (F28) · Dashboards N2/N3 · Alta frequência + FIFO (F35) · Índice de Bem-Estar (F31) · Biometria de abertura (F04) · Seed de exames e anomalias (F15) · **os N4 `pendente_revisor` e os 6 N4 de FC pareada**.

## BL.4 EM HOLD (⛔ Parte 4)
Score Atuarial/Sinistralidade para seguradoras (F12/F14). Fora de escopo sem revisão: chat aberto de IA sobre saúde; SDKs proprietários de wearables; feed social; expansão internacional antes do PMF; **persistência de fotos** (com a emenda da decisão 62: persistir ≠ exibir).

---

*Fim do DOCUMENTO MESTRE v9.2.1 — Orynty. Para continuidade: cole este v9.2.1 em qualquer nova sessão, **mais o `ORYNTY_CATALOGO_DESCOBERTAS_v2_1.md` quando a tarefa for de descobertas** (lembrando que ele é subordinado a este Mestre), o Plano de Marketing v1.0 quando o assunto for marca, e o `docs/motor_metabolico.txt` só quando a tarefa for do Motor. Evolução por adendo/log (`/docs/log_dev`); próxima consolidação (v10.0) sugerida **ao fim do beta de amigos** — e, desta vez, sem consolidação intermediária: o que mudar entre agora e lá vira entrada de log, não versão nova de documento.*
