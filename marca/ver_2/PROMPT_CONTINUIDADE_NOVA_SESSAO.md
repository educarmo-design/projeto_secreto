# PROMPT DE CONTINUIDADE — Projeto de Naming da Marca (Nova Sessão)

**Como usar este documento:** cole o conteúdo abaixo (ou peça para o Claude ler este arquivo) como primeira mensagem de uma nova sessão do Claude Code para retomar o trabalho exatamente de onde parou. Este documento está salvo em:

`C:\Users\eduardosilva\projeto_secreto\marca\ver_2\PROMPT_CONTINUIDADE_NOVA_SESSAO.md`

---

## PROMPT (copiar a partir daqui)

Você está retomando um projeto de naming de marca já em andamento. Leia este documento inteiro antes de fazer qualquer coisa. Não repita trabalho já feito — continue a partir do estado atual.

### 1. Objetivo do projeto

Encontrar o nome de uma **plataforma de saúde preventiva com inteligência artificial** que acompanha a jornada de saúde de uma pessoa **do nascimento à velhice**, organizando dados de smartwatch, exames, alimentação, glicemia, pressão arterial, sono, atividade física e medicamentos, entregando inteligência tanto para o usuário quanto para profissionais de saúde. A plataforma terá apps Android/iOS, versão web, painel profissional e APIs futuras — potencial de virar uma marca global de tecnologia.

**Posicionamento desejado:** continuidade, energia, inteligência, confiança, tecnologia humana, organização da vida, evolução, longevidade (sem usar essa palavra), premium, global. Não pode privilegiar nenhum público específico (crianças, idosos, atletas, sedentários, médicos, etc.). Deve funcionar igualmente em português, inglês e espanhol, com pronúncia simples e sem caracteres especiais.

**Regras do briefing original** (podem ter sido conscientemente flexibilizadas depois — ver seção 4): evitar raízes como vita/vital/life/live/bio/health/doctor/med/clinic/care/fit/well/pulse/track/sync/smart/longev/longo/long/safe/guardian, e evitar proximidade com marcas conhecidas (Apple, Google, Nike, etc.).

### 2. Onde está tudo (estrutura de diretórios)

```
C:\Users\eduardosilva\projeto_secreto\marca\
├── prompr.txt                              # briefing original completo do usuário (mega-prompt com todas as regras, etapas, testes obrigatórios)
├── Projeto_Naming_Global\                  # RODADA 1 — pipeline formal completo (etapas 0-6 + Conselho + Relatório)
│   └── ... (ver README interno / seção 5 do arquivo 17_DOCUMENTO_MESTRE_FINAL.md)
└── ver_2\                                   # RODADA 2 — direção emocional, ONDE ESTÁ O TRABALHO MAIS RECENTE
    ├── 01 a 15: arquivos de processo (análise fonética, gerações, verificações, famílias exploradas)
    ├── 16_LISTA_FINAL_20_avaliacao_completa.csv   # TABELA FINAL com os 20 nomes escolhidos, avaliação completa
    ├── 17_DOCUMENTO_MESTRE_FINAL.md                # RESUMO NARRATIVO COMPLETO de tudo que foi feito — LEIA ESTE PRIMEIRO
    └── PROMPT_CONTINUIDADE_NOVA_SESSAO.md          # este arquivo
```

**Leia primeiro `ver_2/17_DOCUMENTO_MESTRE_FINAL.md`** — ele resume as duas rodadas inteiras, a metodologia, os aprendizados e o mapa de concorrentes encontrado.

Também existe uma memória persistente do Claude Code (carregada automaticamente em qualquer sessão neste projeto) em:
`C:\Users\eduardosilva\.claude\projects\C--Users-eduardosilva-projeto-secreto\memory\naming-marca-concorrentes-saude.md`
— contém o mapa de concorrentes reais de saúde preventiva encontrados durante a verificação de nomes.

### 3. Estado atual (o que já foi decidido)

A lista de **20 nomes finalistas está travada** (o usuário pediu para "manter estas palavras" e não gerar mais variações por enquanto):

Luceryn · Luciun · Coriun · Branyon · Doryn · Belaryn · Duju · Voltoryn · Oxoryn · Soleryn · Photeryn · Aeriun · Jordata · Terveryn · Radieryn · Aeroryn · Radoryn · Kelnoryn · Ioneryn · Tervoryn

Ranking, significado, origem e risco de cada um estão em `ver_2/16_LISTA_FINAL_20_avaliacao_completa.csv`.

**Recomendação executiva atual:** 1º Luceryn (ou Luciun), 2º Coriun, 3º Oxoryn, 4º Branyon.

**Nenhuma decisão final foi tomada** — o usuário estava decidindo entre explorar mais variações ou avançar para testes visuais/decisão final quando esta sessão foi encerrada.

**Limite de busca externa (WebSearch) da sessão anterior foi atingido (200/200).** Se for pedido para verificar novos nomes, isso deve funcionar normalmente numa sessão nova (o limite é por sessão), mas fique atento a esgotá-lo de novo sem necessidade — priorize lotes de verificação eficientes.

### 4. Metodologia que funcionou (aplicar em qualquer nova exploração)

1. **Nunca inventar resultado de verificação de marca/domínio.** Toda alegação de "disponível" ou "colide" vem de busca real (WebSearch), nunca de suposição.
2. **Escala realista, não inflada.** O briefing original pedia milhares de candidatos; a prática consolidada foi gerar centenas com qualidade real e verificar dezenas por vez, documentando essa calibração de escopo com transparência.
3. **A família fonética com melhor taxa de disponibilidade:** raiz real e significativa (grego/latim/nórdico/céltico/PIE, ou conceito científico como volt/oxigênio/fóton/íon) + terminação líquida suave ("-eryn/-oryn/-anyon/-iun" — consoantes R, L, V, N). Evitar terminações "-is/-us/-ix" (soam B2B/corporativo, foi feedback explícito do usuário sobre Firmis/Kaelis/Skaldis).
4. **Palavras reais óbvias e mitologia conhecida de saúde/cura estão extremamente saturadas** por startups de healthtech reais — evitar reinvestir tempo nessa direção sem avisar o usuário do padrão (ver seção 5 do `17_DOCUMENTO_MESTRE_FINAL.md`).
5. **Sempre checar risco fonético/cultural multilíngue manualmente**, além da busca de colisão de marca — vários problemas graves (Vakora→"vaca" em PT, Draumis→"trauma", Sorenta→Kia Sorento, Fionara→Fiona/Shrek) só foram pegos por leitura humana atenta em PT/EN/ES, não por busca.
6. **Sempre documentar em arquivo a cada etapa** (checkpoint), nunca reiniciar do zero se algo falhar — seguir o padrão de numeração sequencial de arquivos já estabelecido em `ver_2/`.

### 5. Ferramentas/skills necessárias para continuar

- **WebSearch** — ferramenta principal para verificação real de colisão de nomes (empresas, apps, marcas). É uma ferramenta "deferred" — se não aparecer disponível diretamente, use `ToolSearch` com query `"select:WebSearch"` para carregá-la primeiro.
- **Write / Edit / Read / Bash** — para gerenciar os arquivos do projeto (CSVs de candidatos, relatórios em Markdown).
- **TaskCreate / TaskUpdate** — recomendado para acompanhar etapas se o trabalho envolver múltiplas fases (foi usado assim na Rodada 1).
- **Artifact** (opcional) — se o usuário quiser uma apresentação visual polida da lista final de nomes (ex: para mostrar a um sócio/investidor), este é o caminho — carregar a skill `artifact-design` antes de publicar.
- Nenhuma das skills genéricas do Claude Code listadas no início de uma sessão nova (dataviz, update-config, loop, schedule, claude-api, etc.) é diretamente necessária para este projeto, exceto `artifact-design`/`Artifact` se for pedida uma peça visual final, e `WebSearch`/`ToolSearch` para qualquer verificação adicional.

### 6. Como o usuário gosta de trabalhar (aprendido ao longo da sessão)

- Prefere que eu **execute e verifique de verdade**, não que eu só sugira nomes de cabeça — sempre rodar WebSearch real antes de recomendar qualquer nome.
- Dá feedback direto e curto ("gostei", "não gostei", nome específico) — não espera explicações longas antes de eu agir, apenas depois, quando reporto o resultado.
- Gosta de ver o **porquê por trás do padrão fonético**, não só a lista de nomes — análises tipo "por que esses nomes funcionam" são bem recebidas.
- Pede explicitamente para eu **registrar decisões e achados em arquivo**, não deixar só na conversa.
- Já pediu para eu sinalizar quando algo colide com uma regra que ele mesmo definiu (ex: "Longiun" tem raiz banida "long") em vez de decidir sozinho — sempre avisar e perguntar antes de quebrar uma regra anterior do próprio usuário, mesmo que ele tenha pedido "remover restrições" de forma geral.

---

**Depois de ler tudo isso, pergunte ao usuário como ele quer continuar** (ex: mais variações, testes visuais, decisão final, ou outra direção) — não presuma a próxima etapa.
