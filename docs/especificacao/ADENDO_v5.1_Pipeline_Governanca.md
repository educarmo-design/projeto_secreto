# ADENDO v5.1 AO DOCUMENTO MESTRE v5.0
## Refinamentos do Pipeline de Visão, Governança de Prompt e Regra de Validação

**Data:** 16 de Julho de 2026
**Acopla-se ao:** DOCUMENTO MESTRE v5.0 (fonte única de verdade). Onde houver conflito, este v5.1 prevalece (mais recente).
**Precedência:** v5.1 > v5.0 > anteriores.
**Uso:** cole o v5.0 e, em seguida, este v5.1. Estes refinamentos serão incorporados ao corpo na próxima consolidação (v6.0).

---

# A. REFINAMENTO DO F10 — PIPELINE GEMINI / TRATAMENTO DE FOTOS

## A.1 O pipeline tem duas metades (esclarecimento)
"Pipeline Gemini" = "tratamento das fotos", e decompõe-se em:
- **Metade 1 — Tubulação Zero Storage (segurança/privacidade):** câmera nativa forçada (galeria bloqueada, antifraude) → bytes só na RAM do device → stream TLS 1.3 → Edge Function segura os bytes na RAM do servidor (nunca em disco) → chama o Gemini → recebe → **destrói a mídia da RAM imediatamente**. Serve a TODOS os tipos de foto. Nenhuma imagem toca disco em momento algum.
- **Metade 2 — Extratores específicos por tipo de captura (inteligência):** cada tipo tem prompt e tratamento próprios: prato de comida, rótulo/código de barras, visor de glicosímetro, visor de aparelho de pressão, visor de balança, e PDF de exame laboratorial. A tubulação é construída uma vez; os extratores são incrementais.

## A.2 Arquitetura "IA traduz, backend calcula" (DECISÃO — adotada de discussão externa)
Regra inegociável para dados calculáveis (calorias/macros): **o Gemini NÃO calcula, apenas identifica.** Motivo: LLM alucina em matemática; separar garante número reproduzível e auditável (importante também para o enquadramento regulatório — o app calcula por regra determinística sobre tabela pública, não "a IA achou").
- **Gemini retorna:** JSON com nome do alimento, quantidade estimada em **medidas caseiras** (colher de sopa, concha, unidade, fatia — não gramas, pois foto 2D não dá percepção de profundidade/peso confiável) e um **score de confiança**.
- **Backend calcula:** cruza os nomes com a tabela nutricional, converte medida caseira → gramas → calorias/macros deterministicamente (regra de três). Precisão 100% segundo a tabela.

## A.3 Base nutricional (nova entidade)
- **Primária: Tabela TACO** (Tabela Brasileira de Composição de Alimentos, Unicamp) — gratuita, pública, com alimentos brasileiros reais (feijão, arroz, pão de queijo, farofa). Coerente com o posicionamento Brasil-first.
- **Fallback: USDA** para industrializados/importados não cobertos pela TACO.
- Vira nova entidade de banco: **`alimentos_referencia`** (análoga a `marcadores_referencia`): nome, sinônimos/aliases para o matching do JSON, medida-caseira→gramas, e composição nutricional por 100g. Inclui tabela de conversão de medidas caseiras.

## A.4 Resolução da imagem POR TIPO DE CAPTURA (ajuste crítico)
A otimização de redimensionar no device para baixa resolução (~512px) economiza tokens **e vale para foto de comida** — mas **NÃO** para leituras que dependem de dígitos nítidos:
- **Comida:** ~512px (baixa resolução, barato). OK.
- **Visor de glicosímetro / pressão / balança e PDF de exame:** resolução ALTA o suficiente para o OCR não errar dígito. Errar um dígito de glicose/pressão é muito pior que gastar tokens. Reduzir demais destrói a legibilidade.
- Regra: a resolução de envio é função do `tipo_captura`. O redimensionamento acontece na RAM do device (compatível com Zero Storage; a imagem reduzida sobe e é destruída após a extração).

## A.5 Validações obrigatórias do extrator
- **Score de confiança:** para casos numéricos (glicose, pressão, peso), se a leitura estiver duvidosa (foto tremida, reflexo, visor parcial), devolver "não consegui ler bem, tente de novo" em vez de gravar número errado. Alimenta o campo `confianca` de `coleta_diaria`. Em saúde, não gravar > gravar errado.
- **Antifraude de imagem:** o prompt instrui o Gemini a detectar foto de tela (moiré, reflexo de vidro, impressão) e barrar — impede fotografar visor/prato de outra tela para farm de pontos.
- **Saída rígida:** Gemini responde **apenas JSON puro** (sem markdown, sem texto conversacional em volta). Tratamento de erro robusto de parsing no servidor (fallback se vier texto sujo).

## A.6 Padrão de UX do resultado (DECISÃO — "IA estima + usuário edita")
Nenhum resultado é salvo automaticamente. Tela de confirmação renderiza os itens identificados em medidas caseiras, com controles de edição, e grava só após o usuário confirmar. Reduz atrito (sem digitação) e dá controle final de exatidão ao usuário — mantendo credibilidade apesar do erro de estimativa de volume da IA.

## A.7 Modelo de IA
Mantém-se **Gemini 2.5 Flash** (coerência de stack, integração já existente, um só fornecedor). O insight aproveitado da discussão externa NÃO é trocar de modelo, é "o modelo só traduz visualmente; o backend calcula" — vale igual no Gemini. (Números de custo citados na discussão externa — ~US$ 35-45/mês para 1,5 mi de fotos — são ilustrativos, não orçamento fixo; a premissa registrada continua ~R$ 0,012/usuário/mês.)

## A.8 Sequência de construção do F10 (ordem obrigatória)
1. **Tubulação Zero Storage** + **um extrator simples de validar** (glicosímetro OU pressão — a resposta certa é um número conferível no visor), provando o fluxo ponta a ponta na RAM.
2. **Prato de comida:** extrator (JSON de alimentos + medidas caseiras + confiança) + integração TACO/USDA + cálculo determinístico (validável por números, sem UI bonita).
3. **Tela de confirmação de comida** funcionalmente completa (ver Seção B), visualmente crua.
4. **Demais extratores** incrementais (rótulo, balança) e, por último, **PDF de exame** (o mais complexo: dezenas de marcadores, normalização de nomes para chaves universais, normalização de unidades, faixa do próprio laboratório).
5. Acabamento visual (design system, Parte 8) por último.

---

# B. REGRA GERAL DE VALIDAÇÃO — "COMPLETA FUNCIONALMENTE, CRUA VISUALMENTE"

## B.1 Princípio (aplica-se a todo desenvolvimento em fase de validação)
"Tela de validação" significa **feia, não capenga**. Toda funcionalidade da tela existe e funciona na fase de validação; apenas o acabamento visual (design system, animações, polimento) fica para depois. Um agente NUNCA deve interpretar "validação" como licença para omitir funcionalidade.

## B.2 Aplicação à tela de confirmação de comida (exemplo canônico)
Na validação, a tela tem TUDO: lista de alimentos identificados, medidas caseiras, botões [+]/[−] de ajuste, adicionar alimento não detectado, remover alimento errado, recálculo determinístico via TACO refletindo na hora, score de confiança visível, gravação no `diario_alimentar_diario` só após confirmação. Fica para depois: aparência (tokens da Parte 8), animações, microinterações.

## B.3 Consequência (por que é mais barato)
Construir funcionalidade completa desde a validação torna a evolução para a versão bonita um **re-skin** (trocar aparência de componentes existentes), não uma reconstrução. Mais barato no total do que fazer uma tela "de mentira" e jogar fora.

---

# C. GOVERNANÇA DE PROMPT — RELATÓRIO OBRIGATÓRIO DE FIM DE TAREFA (atualiza Partes 0 e 10.3)

## C.1 Motivo
A causa raiz da perda de histórico já sofrida (handover não capturou decisões; auditoria teve que redescobrir) é que decisões de infraestrutura, ambiente e arquitetura tomadas pelo agente durante a execução não voltavam em formato registrável. Correção: todo agente reporta de volta, ao fim de cada tarefa, o que um agente futuro não descobriria só lendo o repositório.

## C.2 Nova regra na Parte 0 (acrescentar como item 13)
"13. **Relatório de fim de tarefa obrigatório:** ao concluir qualquer tarefa, o agente reporta em formato registrável (para o fundador colar no adendo/log) todas as decisões de infraestrutura, ambiente, configuração e arquitetura tomadas, entidades novas criadas, desvios da spec e pendências/riscos abertos."

## C.3 Template de prompt do Claude Code ATUALIZADO (substitui a Parte 10.3)
```
[MODELO RECOMENDADO: Sonnet | Haiku | Topo de linha — com 1 linha de justificativa]
[CONTEXTO]: Parte 0 do Documento Mestre v5.0 + seções relevantes à tarefa (+ v5.1 quando aplicável).
[TAREFA]: objetivo único (1 tarefa por sessão).
[ARQUIVOS]: caminhos exatos a criar/alterar.
[RESTRIÇÕES]: holds (Parte 4); segurança (Parte 6); UX (Parte 8); server-side por padrão; GRANT explícito em toda migração; sem segredos em código; sem force push; "validação = completa funcionalmente, crua visualmente" (v5.1 Seção B).
[CRITÉRIO DE ACEITE]: como o fundador (não-dev) testa, passo a passo, em linguagem simples.
[ENTREGÁVEL]:
  1. Código + explicação simples do que foi feito.
  2. Commit em branch própria + instrução de PR.
  3. RELATÓRIO DE FIM DE TAREFA (obrigatório), contendo:
     - Decisões técnicas/arquiteturais tomadas (formato: decisão | motivo) para o Log (Parte 11).
     - Mudanças de infraestrutura/ambiente/configuração NÃO visíveis no código (ex.: configs do painel Supabase, providers, secrets, variáveis de ambiente novas, GRANTs, buckets) — para paridade homolog×prod.
     - Entidades novas criadas (tabelas, views, funções, Edge Functions) — para sincronizar o schema documentado (Parte 3.4).
     - Desvios da spec (o que ficou diferente do documento e por quê).
     - Pendências e riscos deixados em aberto.
```

## C.4 Fluxo de atualização do documento
O fundador cola o "Relatório de Fim de Tarefa" no adendo/log corrente. No próximo marco, consolida-se na v6.0 (Matriz Parte 3.3 + Logs Parte 11 + Riscos Parte 12 atualizados).

---

# D. NOVOS ITENS PARA A MATRIZ (Parte 3.3) E ENTIDADES (Parte 3.4)
- **F10 (refinado):** subdividido na sequência A.8 (tubulação → glicosímetro/pressão → comida+TACO → tela → demais → PDF). Continua ⚠️→🔲 e BLOQUEADOR DE PRODUTO.
- **F45 — `alimentos_referencia` (TACO/USDA)** + tabela de conversão de medidas caseiras. Status 🔲. Necessária para o cálculo determinístico de calorias.
- **Campo `tipo_captura`** no fluxo de visão (governa resolução de imagem e extrator).

---

# E. ATUALIZAÇÃO DO LOG DE DECISÕES (Parte 11)
| Data | Decisão | Motivo |
|---|---|---|
| 16/Jul/2026 | Pipeline de comida: "IA traduz (medidas caseiras + confiança), backend calcula (TACO/USDA)" | Evita alucinação matemática do LLM; número reproduzível e auditável |
| 16/Jul/2026 | Tabela TACO primária + USDA fallback (entidade alimentos_referencia) | Alimentos brasileiros reais; Brasil-first; gratuito |
| 16/Jul/2026 | Resolução de imagem por tipo de captura (comida baixa; visores/PDF alta) | Preservar legibilidade de dígitos; errar dígito de saúde é pior que gastar token |
| 16/Jul/2026 | Manter Gemini 2.5 Flash (não trocar de modelo) | Coerência de stack; insight é "IA só traduz", vale no Gemini |
| 16/Jul/2026 | Padrão UX "IA estima + usuário edita" (não salva automático; [+]/[−]) | Credibilidade apesar do erro de volume; baixo atrito |
| 16/Jul/2026 | Regra "validação = completa funcionalmente, crua visualmente" | Evolução vira re-skin, não reconstrução; agente não omite funcionalidade |
| 16/Jul/2026 | Relatório de fim de tarefa obrigatório no template de prompt | Atacar a causa raiz da perda de histórico (infra/ambiente/decisões) |
| 16/Jul/2026 | Sequência do F10 (tubulação → extrator simples → comida → tela → PDF) | Provar cérebro antes de UI; incremental |

---

*Fim do Adendo v5.1. Para continuidade: cole v5.0 + v5.1 em qualquer nova sessão. Será incorporado ao corpo na v6.0 no próximo marco.*
