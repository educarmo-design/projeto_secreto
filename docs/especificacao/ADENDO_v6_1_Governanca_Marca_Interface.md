# ADENDO v6.1 AO DOCUMENTO MESTRE v6.0
## Governança de Prompts, Frente de Marca/Naming, Interface e Onboarding

**Data:** 30 de Julho de 2026
**Acopla-se ao:** DOCUMENTO MESTRE v6.0 (fonte única de verdade). Onde houver conflito, este v6.1 prevalece (mais recente).
**Precedência:** v6.1 > v6.0 > anteriores.
**Uso:** cole o v6.0 e, em seguida, este v6.1. Será incorporado ao corpo na próxima consolidação (v7.0, sugerida ao fim da rodada de teste fake do app).

---

# A. GOVERNANÇA DE PROMPTS DO ECOSSISTEMA (correções registradas)

Os prompts que operam o projeto foram revisados e devem ser mantidos em versão coerente com o Documento Mestre. Estado atual (30/Jul/2026):

## A.1 Artefatos de prompt vigentes
- **PROMPT DE CONTINUIDADE v6.1** (consultor estratégico — este chat). Estrutura completa herdada do original do fundador; atualizado com: papéis novos (A.2), estado real de 30/Jul (backend F10 pronto; tarefa nº1 = F10 Passo 3), riscos R6/R15/R1/R-E4/R9/R13 no topo, e a Frente de Marca (Seção B). Kit de sessão: este prompt + v6.0 (+ Plano de Marketing só em marca).
- **PROMPT MESTRE DO GEMINI v6** (gerente de projeto). Estrutura rica herdada do original do fundador; 11 papéis; regras 0.13/0.14/0.15/0.2 embutidas; fila de prioridades vigente; processamento do Relatório de Fim de Tarefa de volta em log + Matriz. Kit de sessão: este prompt + v6.0. **Correção crítica registrada:** a "primeira ação" do prompt antigo mandava gerar o "Passo 1 do F10" — mas os Passos 1 e 2 já estão prontos (backend); a primeira ação vigente é gerar o **F10 Passo 3** (tela do prato). Usar o prompt antigo teria feito o Gemini planejar a reconstrução de algo existente.
- **PROMPT DE NAMING** (chat dedicado de branding — Seção B.4). Autocontido (não exige anexar documentos); carrega o desafio multi-público, a metáfora da árvore e a lista de nomes proibidos.

## A.2 Papéis acrescidos ao consultor estratégico e ao gerente de projeto
Além dos papéis do v5.0/v6.0, ambos os prompts passam a acumular: **Especialista em Crescimento de SaaS / Funil de Assinatura**; **Designer de Produto** (onboarding que entrega valor nos primeiros 30 segundos); **Engenheiro de UI Sênior** (implementação fiel do Design System, re-skin sem reconstrução).

## A.3 Regra de manutenção
Toda alteração relevante de comportamento/prioridade do projeto exige revisão sincronizada dos três artefatos de prompt na mesma sessão (evitar deriva entre eles — mesma classe de problema do schema drift, R9, aplicada a prompts).

---

# B. FRENTE DE MARCA / NAMING (Fase 0 do Plano de Marketing v1.0)

## B.1 Requisito central do nome
A solução atende, com UMA marca-mãe (públicos = "modos" do produto, nunca marcas separadas): atleta/smartwatch; cidadão comum com ou sem smartwatch; sênior/cuidado clínico; **crianças desde o nascimento** (a vida inteira registrada); e **visão internacional futura** (pt/en/es). Logo o nome NÃO pode ancorar em esporte, idade, aparelho ou termo clínico.

## B.2 Metáfora de marca escolhida
**A árvore:** anéis de crescimento (a vida registrada ano a ano, do nascimento à velhice), a seiva, longevidade SEM o radical "longev". O território de marca deriva daí. (Guardar para a história de marca na identidade visual.)

## B.3 Nomes DESCARTADOS por colisão (não repropor nem variações próximas)
Viora, Longeva, Longevo, Longevia, VitaLonga, Perena/Perene, Anelo.
**Lição registrada:** todo radical latino de "vida/longevidade" já tem dono no segmento de saúde/bem-estar — preferência forte por nomes inventados de 2-3 sílabas com metáfora, filtrados no Registro.br (mais barato) antes do INPI.

## B.4 Lote em filtro pelo fundador
Alvora, Oriva, Nascor, Seiva, Vionda, Kadenza, Anira, Vitalu, Umbu. Processo (Parte 2.1 do Plano): Registro.br → handles Instagram/TikTok → busca fonética no INPI (classes 9/42/44, incluir vizinhos) → teste de pronúncia com 5 pessoas ("baixa o ___ aí" / "o ___ da minha mãe"). Sobreviventes → decisão do fundador → registrar nome + data + evidência dos filtros → comprar domínio e reservar handles no mesmo dia → landing de waitlist ganha endereço.

## B.5 Concorrente adicionado à Parte 1.5 (monitorar)
**AIA Longeva** (Google Play): plataforma de longevidade com IA que faz upload de exames, biomarcadores, integração com wearables e insights — muito próxima da nossa tese. Nosso fosso diferencial permanece: Brasil-first (TACO, PDF de labs BR), B2B, e o loop profissional→prescrição→Garmin, que eles não têm. Também na paisagem: Longevital (app alemão, biomarcadores+wearables) e Viva Longevidade (Bradesco Seguros, BR).

---

# C. CAMADAS DE INTERFACE (Engenheiro de UI + Diretor de Produto)

Refina a regra "validação = completa funcionalmente, crua visualmente" (Parte 0.14) esclarecendo QUANDO o acabamento visual entra, em 3 camadas com datas:
- **Camada 1 — Tema e tokens (fazer JÁ, ~1-2 tarefas):** aplicar a Parte 8.3 (grafite #0E1114, acento único, escala 12/14/16/18/22/28/34, grade 8pt, tokens semânticos) no ThemeData central do Flutter e no tema do painel. Faz TODAS as telas cruas nascerem com cara do produto sem tocar tela por tela; evita re-skin caro depois. Custo baixo, benefício permanente.
- **Camada 2 — Componentes e layout definitivos:** após a rodada de teste fake, quando se souber quais telas sobrevivem.
- **Camada 3 — Assinaturas visuais (anel HealthScore, ilustrações, animações):** ANTES do beta de amigos — motivo de Growth, não de estética: os vídeos da Fase 1 do Plano de Marketing são gravados com o app real; app feio demais contamina o feedback e inviabiliza a matéria-prima de vídeo.

---

# D. ORDEM DE VALIDAÇÃO E GAMIFICAÇÃO (Diretor de Produto + Growth)

- **Ordem de construção na fase de validação:** entrada de dados → relatórios/consultas → insights → gamificação. Coerente com a Parte 9.1 (F10 Passo 3 = entrada; F34 = persistência; painel/histórico = consulta).
- **Ressalva inegociável de Growth:** a gamificação (streak, Retrospectiva de Boas-Vindas, cartões — F43) precisa estar VIVA **antes do beta de amigos**. Ela é o motor de retenção, e retenção é exatamente o que o beta existe para medir; testar sem ela mede a retenção de um produto incompleto e leva a conclusão errada. "Gamificação por último" vale dentro do teste solo do fundador, não como corte para o beta.
- Nota: a **Retrospectiva de Boas-Vindas é insight** (momento mágico do dia 1), não gamificação — cabe já no passo de insights.

---

# E. ONBOARDING "VALOR ANTES DE FRICÇÃO" (Designer de Produto)

Princípio: o usuário deve sentir o valor nos primeiros 30 segundos, antes de qualquer formulário longo. Esboço (detalhamento vira spec própria quando entrar na fila):
1. **Tela 0 (~5s):** frase de valor + botão único "Começar". Cadastro mínimo (e-mail/senha ou social). Os campos ricos do Cadastro Dinâmico (idade, profissional etc.) saem da porta de entrada e viram etapa pós-valor (progressive profiling).
2. **Bifurcação de valor imediato (~10s):** "Usa relógio/pulseira?" → **Sim:** conectar Health Connect → carga de 30 dias → "preparando sua retrospectiva..." → primeiro cartão do Uau do Dia 1. → **Não:** "Fotografe seu prato ou o visor do seu aparelho" → foto → resultado na tela (o F10).
3. **Só após o primeiro "uau":** pedir o resto do perfil, apresentar streak e convite.
Custo: reordenar telas existentes + adiar campos (não é construção nova). Convive com o R14 (cadastro social sem perfil), pois empurra o perfil para depois de qualquer forma.

---

# F. PRESENÇA WEB / FASE 0 (Growth + Sentinela Jurídica)

- Landing de waitlist é a Fase 0 do Plano de Marketing (fundação silenciosa, custo ~zero). **Ordem:** naming primeiro (não comprar domínio antes de decidir o nome); domínio + handles no mesmo dia da decisão.
- **Hosting:** preferência por Cloudflare Pages (já na stack, grátis, e a waitlist grava em tabela Supabase com mecanismo "indique e suba na fila"). A conta Hostinger do fundador serve, mas usar só se quiser o e-mail profissional do domínio — evitar adicionar fornecedor sem necessidade.
- **Guarda-corpos jurídicos:** landing sem claim médico (vocabulário permitido: organizar, acompanhar, entender padrões, bem-estar); formulário de e-mail exige aviso de privacidade simples (LGPD vale desde o 1º e-mail captado); nunca a palavra "anônimo". Landing discreta + SEO maturando NÃO dispara o gatilho de CNPJ; divulgação ativa/campanha pública dispara (Parte 1.10). SEO leva meses — começar agora é o timing certo.

---

# G. ATUALIZAÇÃO DO LOG DE DECISÕES (Parte 11 do v6.0)
| Data | Decisão | Motivo |
|---|---|---|
| 30/Jul/2026 | Papéis acrescidos (Growth/SaaS, Designer de Produto, Engenheiro de UI) ao consultor e ao gerente | Cobrir funil/onboarding/UI com a mesma senioridade do resto |
| 30/Jul/2026 | Prompts do ecossistema revisados p/ v6.0; primeira ação do Gemini corrigida p/ F10 Passo 3 (não Passo 1) | Passos 1-2 já prontos; prompt antigo mandaria reconstruir o existente |
| 30/Jul/2026 | Regra: alteração de comportamento/prioridade exige revisão sincronizada dos 3 prompts | Evitar deriva entre prompts (schema drift aplicado a prompts) |
| 30/Jul/2026 | Metáfora de marca = a árvore (anéis/seiva; longevidade sem "longev") | Único território que cobre do nascimento ao sênior + internacional |
| 30/Jul/2026 | Naming: preferir inventado 2-3 sílabas; filtrar no Registro.br antes do INPI; radical latino de vida/longevidade proibido (saturado) | 7 colisões seguidas comprovaram a saturação |
| 30/Jul/2026 | Camadas de interface: tokens/tema JÁ; componentes pós-teste fake; assinaturas visuais antes do beta de amigos | Re-skin barato; matéria-prima de vídeo exige app decente no beta |
| 30/Jul/2026 | Gamificação viva ANTES do beta de amigos (não é corte para o beta) | É o motor de retenção — a métrica que o beta mede |
| 30/Jul/2026 | Onboarding "valor antes de fricção" em 30s; progressive profiling | Momento mágico no dia 1; menor atrito de entrada |
| 30/Jul/2026 | Fase 0 de marketing iniciada: naming → domínio/handles → landing waitlist (Cloudflare) | Custo zero; SEO leva meses; não dispara gatilho de CNPJ |
| 30/Jul/2026 | AIA Longeva adicionado aos concorrentes a monitorar | Faz exames+wearables+IA; validar diferencial Brasil-first/B2B/Garmin |

---

*Fim do Adendo v6.1. Para continuidade: cole v6.0 + v6.1 em qualquer nova sessão. Será incorporado ao corpo na v7.0 no próximo marco.*
