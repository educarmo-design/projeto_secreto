# RELATÓRIO 20260830_0001 — N27 + N28 + N14: falhar visível, nunca arbitrar

**Data:** 2026-08-30
**Branch:** `fix/falhar-visivel-medida-n27-n28-n14` (não mesclada em `main` — ver "Estado das branches" no fim)
**Pedido:** Prompt de Execução formal (Bloco A, Tarefa 4), contexto Documento Mestre v8.0 Parte 0 (Regras 16, 23, 24, 26) e Parte V1 H (N27, N28, N14).

## Contexto — por que isto é uma tarefa só

O Mestre v8.0 (30/Ago) identificou, revisando esta mesma sessão de trabalho, o
**risco nº1 do projeto (R23)**: `encontrarMedida` (Edge Function
`extract-metric-photo`) arbitrava uma medida quando a pedida não casava com
nenhuma cadastrada — e o RELATÓRIO 20260825_0001 (eu mesmo, tarefa anterior)
tinha reescrito os 6 testes que provavam isso para *validar* o chute em vez
de questionar se o chute era o próprio bug. Esse é o incidente de origem da
Regra 24 ("teste que documenta bug não vira especificação") citado por nome
no Mestre. N27 (corrigir o chute), N28 (amostrar as 1.056 medidas geradas
por IA que nunca foram conferidas) e N14 (tirar o peso típico do hardcode)
são tratados como o mesmo bug — "o app inventando quantidade sem avisar" —
por isso uma tarefa só, não três.

## O que foi feito

### N27 — `encontrarMedida` falha visível, nunca arbitra

`supabase/functions/extract-metric-photo/index.ts`: `encontrarMedida` tinha
4 camadas — (1) match exato, (2) match substring, (3) fallback pra
"primeira medida cadastrada do alimento" (F46, "FIX 31/jul"), (4) fallback
pra peso genérico de 100g ou peso padrão da categoria. As camadas 3 e 4
foram **removidas**. Sem match exato/substring, a função volta a devolver
`null` — exatamente o comportamento anterior ao "FIX 31/jul", que aquele
fix trocou por um chute silencioso.

Isso sozinho não bastava: `resolverComBuscaSemantica` tinha um comentário
afirmando que esse `null` era "inalcançável na prática" (só existia por
exigência do TypeScript) — corrigido, porque agora é um caminho real e
frequente.

**Contrato expandido** (`ItemPratoNaoReconhecido`/resposta HTTP): quando
`motivo === 'medida_nao_encontrada'`, o alimento JÁ foi casado (só a
medida que faltou) — o contrato agora carrega `alimento_casado` + macros
por 100g + `medidas_disponiveis` (as medidas que ESSE alimento realmente
tem cadastradas), pra o Flutter resolver manualmente sem um novo
round-trip ao servidor.

### Flutter — resolução manual (ACEITE)

`_ItemNaoReconhecidoTile` deixou de ser só informativo: quando o alimento
já foi casado, ganhou um botão "Resolver" que abre um diálogo com (a) as
medidas cadastradas do alimento, tocáveis, e (b) um campo de peso manual em
gramas. `ConfirmacaoPratoController` ganhou `resolverComMedidaCadastrada`/
`resolverComPesoManual`, que promovem o item da lista de não reconhecidos
para a lista normal (marcado como estimativa, mesmo padrão âmbar já usado
pelos outros itens estimados) — **sem bloquear o resto do prato**: o
registro da refeição só é bloqueado se `itens` (a lista confirmada) ficar
vazia, nunca por sobrar algo em `itensNaoReconhecidos`. O total da refeição
(`_TotaisBar`) ganhou um ícone de aviso (`⚠️`, com tooltip) quando qualquer
item confirmado é estimativa.

Quando o alimento em si não foi achado (`motivo: 'alimento_nao_encontrado'`,
sem casamento nenhum), o item continua só informativo — resolver esse caso
exigiria busca manual de alimento (fluxo do `ManualFoodSearchPage`/
`search-food`), que é uma integração maior e fica de fora desta tarefa por
decisão de escopo, registrada aqui em vez de silenciada.

### N14 — peso típico fora do hardcode

Auditoria (servidor + app) do que "peso típico, faixa ou fator" ainda
estava fixo em código:

| Onde | O que era | O que virou |
|---|---|---|
| `encontrarMedida` (servidor) | `100g (est.)` genérico + peso padrão de categoria, aplicados **sem confirmação do usuário** | Removidos — é exatamente o N27 acima. Esse era o caso citado pelo R17/Regra 16 no Mestre. |
| `confirmacao_prato_page.dart`, `_mostrarDialogoEditarPeso` | `?? 100` espalhado em 2 lugares (valor inicial do campo de peso) | Extraído para `_pesoInicialQuandoDesconhecidoGramas` (constante nomeada e documentada) — mas **não** movido pra tabela: é só o texto de largada de um campo que o usuário sempre edita antes de salvar, nunca um valor usado em cálculo sem confirmação. |
| `confirmacao_prato_page.dart`, botões de tamanho rápido (líquido frio 200/500/700ml, líquido quente café 50ml/chá 200ml) | Literais soltos em 2 métodos | Extraídos para 5 constantes nomeadas e documentadas no topo da classe |

**Decisão registrada** (mesmo espírito do N27: "se alguma camada tiver
justificativa real, relatar antes de manter — não manter por inércia"): os
5 tamanhos de botão NÃO foram movidos para uma tabela no banco nesta
tarefa. Motivo: são escolhas **ativas e visíveis** do usuário (o usuário
toca "Médio" sabendo que é 500ml), não um valor aplicado sem confirmação —
categoricamente diferente do risco que motivou remover o fallback de
`encontrarMedida`. O custo de uma migration + tela admin nova não se paga
só por estes 5 valores hoje; reavaliar se a lista de tamanhos precisar
crescer ou variar por alimento. Isso é uma decisão, não uma omissão —
registrada para o fundador aprovar ou reverter.

Também verificado e descartado como fora de escopo: `_tamanhoCopoMl = 200`
em `registro_hidratacao_page.dart` já é um campo editável pelo usuário na
própria tela (documentado como "padrão 200ml, CONFIGURÁVEL" desde o N16) —
não é o mesmo tipo de hardcode.

### N28 — amostragem das medidas caseiras geradas por IA

Script novo `scripts/amostrar_medidas_caseiras.ts` (Deno, mesma convenção
de `scripts/gerar_csv_medidas_pendentes.ts`) consulta
`alimentos_medidas_caseiras` inteira (confirmado: **1.056 linhas**, batendo
com o número do Mestre), sorteia sem reposição (Fisher-Yates, sem seed
fixo) e imprime. Rodado uma vez nesta tarefa com a service role key local
(`web_painel/.env.local`, nunca commitada).

**Amostra de 50 (das 1.056), avaliação manual de plausibilidade** — nenhuma
correção foi aplicada no banco, conforme a Regra 26 pede ("medir e
reportar, não corrigir em massa"):

| id | alimento | medida | gramas | avaliação |
|---|---|---|---|---|
| 299 | Abadejo, filé, congelado, assado | filé | 120g | plausível |
| 305 | Abóbora, cabotiá, cozida | concha | 100g | plausível |
| 312 | Abóbora, moranga, refogada | concha | 90g | plausível |
| 314 | Abobrinha, italiana, cozida | colher de sopa | 25g | plausível |
| 328 | Acerola, polpa, congelada | sachê/pacote | 100g | plausível |
| 363 | Ameixa, em calda, enlatada, drenada | unidade | 30g | plausível |
| 419 | Banana, nanica, crua | unidade | 90g | plausível |
| 438 | Batata, frita, chips, industrializada | pacotinho individual | 30g | plausível |
| 440 | Batata, inglesa, cozida | pedaço | 50g | plausível |
| 464 | Biscoito, doce, recheado c/ morango | pacotinho | 36g | plausível |
| 480 | Bolo, pronto, milho | fatia | 60g | plausível |
| 497 | Caju, cru | unidade grande | 150g | plausível |
| 523 | Capuccino, pó | colher de sopa | 15g | plausível |
| 526 | Cará, cozido | colher de servir | 60g | plausível |
| 532 | Carne, bovina, acém, moído, cozido | colher de sopa | 25g | plausível |
| 545 | Carne, bovina, bucho, cozido | concha | 80g | plausível |
| 590 | Carne, bovina, fraldinha, c/ gordura, cozida | fatia | 70g | plausível |
| **599** | **Carne, bovina, língua, crua** | **peça** | **800g** | **⚠️ questionável — "peça" é o órgão cru inteiro, não uma porção de refeição real; peso em si é plausível pra uma língua bovina, mas a MEDIDA escolhida não é o que alguém reportaria comendo** |
| 606 | Carne, bovina, músculo, sem gordura, cozido | pedaço | 40g | plausível |
| 685 | Cocada branca | unidade | 50g | plausível |
| 700 | Corvina de água doce, crua | filé | 120g | plausível |
| 712 | Couve, manteiga, refogada | colher de servir | 40g | plausível |
| 780 | Feijão tropeiro mineiro | colher de servir | 60g | plausível |
| 782 | Feijão, broto, cru | colher de sopa | 10g | plausível |
| 790 | Feijão, fradinho, cozido | colher de servir | 60g | plausível |
| 802 | Feijão, rajado, cozido | concha | 130g | plausível |
| 807 | Feijão, rosinha, cozido | colher de sopa | 25g | plausível |
| 814 | Fermento em pó, químico | colher de chá | 5g | plausível |
| 815 | Fermento em pó, químico | colher de sopa | 15g | plausível |
| 824 | Frango, com açafrão | colher de sopa | 30g | plausível |
| 865 | Goiaba, doce, cascão | fatia | 30g | plausível |
| 866 | Goiaba, doce, cascão | colher de sopa | 20g | plausível |
| 886 | Iogurte, sabor pêssego | potinho | 170g | plausível (bate com pote real de mercado) |
| 888 | Jabuticaba, crua | porção | 100g | plausível |
| 907 | Laranja, baía, suco | copo americano | 200g | plausível |
| 951 | Lingüiça, frango, frita | unidade | 45g | plausível |
| 982 | Mandioca, crua | pedaço médio | 80g | plausível |
| 1004 | Manteiga, com sal | colher de sopa | 15g | plausível |
| **1015** | **Margarina, c/ óleo hidrogenado, sem sal** | **colher de sopa** | **10g** | **⚠️ questionável — inconsistente com a manteiga acima (mesma "colher de sopa", 15g); margarina tem densidade parecida à da manteiga, esperado ~13-15g, não 10g** |
| 1071 | Óleo, de canola | colher de sopa | 13g | plausível |
| 1076 | Óleo, de milho | fio | 5g | plausível |
| 1085 | Ovo, clara, cozida/10min | colher de sopa | 15g | plausível |
| 1098 | Pão de queijo | unidade | 30g | plausível |
| 1113 | Pastel, de queijo, cru | unidade | 80g | plausível |
| 1132 | Pescada, filé, c/ farinha, frito | porção | 150g | plausível |
| 1142 | Pimentão, amarelo, cru | colher de sopa | 15g | plausível |
| 1156 | Pipoca, c/ óleo de soja, sem sal | xícara | 10g | plausível |
| 1166 | Porco, bisteca, frita | unidade | 100g | plausível |
| 1196 | Queijo, minas, meia cura | fatia | 30g | plausível |
| 1200 | Queijo, parmesão | colher de sopa | 10g | plausível |

**Taxa de erro medida: 0/50 (0%) claramente errado** (nenhum valor fora de
ordem de grandeza) **+ 2/50 (4%) questionável** (id 599 e id 1015, acima —
um problema de escolha de MEDIDA, não de peso; um de inconsistência de
peso entre itens análogos). Nenhuma das 50 linhas amostradas tinha
`revisao_necessaria=true` — bate com a taxa de autoavaliação da IA
(12/1.056 ≈ 1,1%) ser baixa demais pra ser o único sinal confiável, como o
Mestre já suspeitava, mas a taxa REAL de erro encontrada por conferência
humana (4% questionável, 0% claramente errado) é **bem melhor do que o
`revisao_necessaria` sozinho sugeria** — não é um catálogo confiável a
100%, mas também não está tão ruim quanto "só 1% foi checado" soa.
**Recomendação para o fundador:** corrigir manualmente as 2 linhas
encontradas (id 599: reconsiderar a medida "peça" pra língua bovina crua;
id 1015: ajustar margarina colher de sopa pra ~13-15g) é opcional e de
baixo risco — não é urgente, mas fica registrado. Não recomendo rodar uma
segunda curadoria em massa por IA só por causa desta amostra: a taxa de
erro encontrada não justifica o custo/risco de regenerar as 1.056 linhas
de novo.

## Decisões técnicas

| Decisão | Motivo |
|---|---|
| Remover as camadas 3/4 de `encontrarMedida` em vez de só "avisar e manter" | Regra 23 é explícita: nunca arbitrar, nem com aviso — o item precisa ficar de fato não resolvido |
| Enriquecer `ItemPratoNaoReconhecido` só quando `motivo === 'medida_nao_encontrada'` | O alimento já foi casado nesse caso — dado grátis, sem I/O extra. Quando `alimento_nao_encontrado`, não há nada pra carregar |
| Item resolvido manualmente ganha `confianca: 1.0` fixo | O peso agora é escolha explícita do usuário, não um chute da IA — não faz sentido esse item derrubar `confiancaMinima` da refeição |
| Botões de tamanho de líquido NÃO viraram tabela no banco | Escolha ativa e visível do usuário, não arbitração silenciosa — risco categoricamente diferente do que motivou o N27. Decisão registrada, não omissão |
| N28: sortear e reportar, nunca corrigir em massa | Regra 26 explícita — decisão de correção em lote é do fundador |
| Resolver manualmente é reservado a itens com alimento já casado | `alimento_nao_encontrado` exigiria busca manual de alimento — integração maior, fora do escopo desta tarefa |

## Infra/config

Nenhuma migration nova. Nenhum secret novo. Script novo
`scripts/amostrar_medidas_caseiras.ts` (ferramenta de auditoria, reusável
para futuras rodadas do N28 — usa `SUPABASE_SERVICE_ROLE_KEY`, já existente
em `web_painel/.env.local`).

## Entidades novas

Nenhuma. `MedidaCaseiraModel` (Flutter) é um DTO novo, não uma entidade —
espelha `MedidaCaseiraCatalogo` que já existia no servidor.

## Desvios de spec

Nenhum desvio do que o Mestre pediu — a única decisão de escopo (botões de
líquido não virarem tabela) está documentada acima como decisão, não como
desvio silencioso.

## Problemas encontrados

- N28: 2 linhas questionáveis em 50 (detalhe na tabela acima) — não
  corrigidas nesta tarefa, por desenho (Regra 26).
- Nenhum bug novo encontrado no código auditado além do que já se sabia
  (o próprio R23).

## Riscos mapeados + mitigação

- **R23 (crítico, do Mestre) — mitigado por esta tarefa.** `encontrarMedida`
  não arbitra mais; os 6 testes que validavam o chute foram reescritos
  pra validar o comportamento correto (Regra 24).
- **R17 (médio, do Mestre) — fechado para o caso que motivou o risco**
  (peso genérico/de categoria no servidor). Os 5 valores de UI (tamanhos de
  bebida) continuam hardcoded por decisão registrada acima — risco residual
  baixo (escolha visível do usuário), não crítico.
- **Novo risco residual, não crítico:** itens com `motivo:
  'alimento_nao_encontrado'` continuam sem caminho de resolução manual
  nesta tela — usuário só pode remover a refeição do registro daquele item
  ou registrar sem ele. Mitigação futura: reaproveitar
  `ManualFoodSearchPage`/`search-food` (já existentes para outro fluxo) num
  botão "Buscar alimento" nesse tipo de item — não implementado aqui por
  ser uma integração maior, fora do escopo declarado desta tarefa.
- **N28 residual:** 1.006 das 1.056 linhas nunca foram conferidas por
  humano (só a amostra de 50). Taxa de erro medida (4% questionável, 0%
  claramente errado) é tranquilizadora mas não é cobertura total —
  amostragens futuras periódicas continuam valendo a pena.

## Como o fundador testa (ACEITE)

1. Fotografar um prato com um item de medida incomum (ex.: um alimento do
   catálogo com poucas medidas cadastradas, pedindo uma medida que ele não
   tem — ex.: "1 xícara de feijão", já que o feijão só tem "colher de
   sopa"/"concha" cadastradas).
2. Esperado: o item aparece na seção "Não reconhecidos", com botão
   "Resolver" visível (porque o alimento FOI casado, só a medida não).
3. Tocar "Resolver": abre diálogo com as medidas reais do feijão + campo de
   peso manual.
4. Escolher uma medida OU digitar um peso: o item some de "Não
   reconhecidos" e aparece na lista normal, marcado com o aviso âmbar de
   estimativa.
5. O total da refeição mostra o ícone `⚠️` (com tooltip explicando que
   inclui estimativa).
6. Confirmar a refeição inteira funciona normalmente — o item resolvido
   entra junto, nenhum bloqueio.

## Como a performance foi tratada

Sem impacto material. O contrato ganhou campos a mais na resposta HTTP só
para itens não resolvidos com `medida_nao_encontrada` (tipicamente uma
minoria ou zero itens por prato) — aumento de payload desprezível (algumas
dezenas de bytes por item, sem novas queries: os dados já estavam
carregados em memória no `catalogo`). Nenhuma chamada de rede nova foi
adicionada em nenhum fluxo — a resolução manual do Flutter é 100% local
(mesma filosofia de "IA estima + usuário edita" da Parte 11.3, já usada
pelos outros itens estimados). O script de amostragem N28 é uma ferramenta
offline (rodada manualmente, fora do caminho de produção).

## Verificação

- `deno check` limpo em `index.ts`/`index_test.ts`/`amostrar_medidas_caseiras.ts`.
- Deno: **100/100 passando** (4 falhas antigas viraram 4 passes depois da
  reescrita dos testes; 0 regressão).
- `flutter analyze`: 0 erros, mesmos avisos pré-existentes de sempre (nenhum
  novo introduzido por esta tarefa — os 2 únicos avisos que sobram em
  `confirmacao_prato_page.dart` são de código que esta tarefa não tocou).
- Flutter: **440/440 passando** (suíte inteira), incluindo +5 testes de
  controller, +5 de página e +2 de model novos para a resolução manual e o
  contrato expandido.

## Estado das branches

Trabalho feito inteiramente em `fix/falhar-visivel-medida-n27-n28-n14`,
criada a partir de `main` no início desta tarefa. **Não mesclada.**

**Instruções de PR:**

```
git push -u origin fix/falhar-visivel-medida-n27-n28-n14
gh pr create --base main --head fix/falhar-visivel-medida-n27-n28-n14 \
  --title "fix: encontrarMedida falha visível (N27) + amostragem N28 + hardcode N14" \
  --body "Ver docs/log_dev/20260830_0001_falhar_visivel_medida_n27_n28_n14.md"
```

**Sugestão de merge:** seguro fazer merge em `main` — suíte inteira verde
(Deno 100/100, Flutter 440/440), sem migration pendente, sem mudança
destrutiva (o contrato só GANHA campos opcionais; clientes antigos que
ignorem os campos novos continuam funcionando). Por Regra 18, esta é só
uma sugestão — o merge em si espera autorização explícita do fundador.
Por Regra 9.1.1 (sequenciamento), não empilhar o Bloco C (dashboards, N21+)
em cima desta branch antes do merge: N27 muda o formato do dado que os
dashboards vão consumir.
