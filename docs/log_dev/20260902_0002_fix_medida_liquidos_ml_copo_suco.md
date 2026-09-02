# RELATÓRIO 20260902_0002 — "Copo de suco" e a Grandeza Errada (g vs ml) na Resolução Manual

**Data**: 2026-09-02
**Branch**: `fix/medida-liquidos-ml` (parte de `main`, já com a cadeia `fix/hotfix-ui-matematica-n27` + `fix/performance-ux-registro` + `fix/gemini-timeout-progress` mesclada — commit base `8359079`)
**Referências**: Documento Mestre v8.0, Parte V1 H (N27 — Falhar Visível), Regra 23 (nunca arbitrar).

## Contexto

O fundador relatou: "um copo de suco" não reconhece a medida "copo", e a UI de resolução manual pede o preenchimento em "gramas" em vez de "ml". Tarefa pedia 3 coisas: (1) auditoria de match — por que "copo" falha; (2) correção de grandeza no frontend (líquido pede "ml", não "g"); (3) garantir que `categoria_consumo` chega no payload do item pendente.

## Auditoria de Match — por que "copo" falha (evidência real, não suposição)

Consultei o catálogo real do banco (service role, só leitura) e reproduzi `calcularPrato`/`encontrarAlimento`/`encontrarMedida` localmente contra ele, para várias frases plausíveis ("suco", "suco de laranja", "suco de manga", "suco de limão", etc. — script descartável, não faz parte do código de produção). Achado: **os dois mecanismos que a tarefa pediu para avaliar existem de verdade, em casos diferentes**:

1. **Limitação real da tabela `alimentos_medidas_caseiras` (achado principal, bate com o relato)**: "Limão, cravo, suco" e "Limão, galego, suco" casam corretamente como `categoria_consumo: 'liquido_frio'`, mas a ÚNICA medida cadastrada para os dois é "colher de sopa" (15g) — nunca "copo". Faz sentido de produto (suco de limão concentrado se usa às colheradas, não ao copo), mas por Regra 23 o sistema corretamente RECUSA arbitrar uma medida "copo" que não existe — o item cai em `itensNaoReconhecidos` com `motivo: 'medida_nao_encontrada'`. **Este é o cenário que reproduz exatamente o sintoma relatado**: alimento líquido, corretamente identificado, sem "copo" cadastrado.
2. **Achado extra, mais grave, fora do escopo desta tarefa (registrado, não corrigido)**: `encontrarAlimento` tem 3 aliases cadastrados como a palavra solta `"suco"` (Laranja valência, Laranja pêra, Uva concentrado) — qualquer busca tipo `"suco de X"` para uma fruta SEM entrada própria no catálogo (testado com "manga" e "abacaxi") casa por SUBSTRING com um desses aliases genéricos (`"suco de abacaxi".includes("suco")`) e devolve os macros de OUTRA fruta, silenciosamente, sem erro nenhum — pior que "medida não encontrada": é um cálculo nutricional errado sem aviso algum. Também achei que "suco de manga" (Manga não tem entrada "suco" própria) casa com "Manga, polpa, congelada" (`categoria_consumo: 'peso_livre'`, só "sachê" cadastrado) — outro tipo de match errado, aqui gerando `medida_nao_encontrada` mas com a categoria ERRADA (sólido em vez de líquido). **Não toquei no algoritmo de `encontrarAlimento`/aliases genéricos nesta tarefa** — é uma mudança de maior risco (afeta o catálogo inteiro, 637 alimentos), fora do que foi pedido (a tarefa pediu para AVALIAR, não reescrever o casamento por substring), e merece revisão própria do fundador antes de qualquer curadoria em massa (Regra 26).

Conclusão da auditoria: **os dois** — tabela (para limão) e algoritmo (para manga/abacaxi) — mas o fix pedido (contrato HTTP + UX ml/g) resolve corretamente o caso 1 e pelo menos evita que o caso 2 mostre "gramas" quando a categoria (mesmo errada) já é conhecida; o caso 2 continua sendo um risco de dado errado silencioso, documentado aqui para decisão futura do fundador.

## Causa raiz do "pede gramas" (contrato HTTP incompleto)

O RELATÓRIO 20260823_0004 já tinha corrigido `categoria_consumo`/`unidade_medida_padrao`/`medida_padrao_nome`/`medida_padrao_qtd` para os itens JÁ RESOLVIDOS (`itens`/`ItemPratoCalculado`) — mas nunca para os itens NÃO reconhecidos (`itens_nao_reconhecidos`/`ItemPratoNaoReconhecido`), um contrato inteiramente separado (`calcularPrato`/`resolverComBuscaSemantica`). Mesmo quando o alimento já tinha sido casado corretamente como líquido (caso do limão acima), esses 4 campos nunca eram propagados — o Flutter não tinha como saber, e o diálogo de resolução manual sempre assumia "gramas".

## Correções

**Backend** (`extract-metric-photo/index.ts`): `ItemPratoNaoReconhecido` ganhou os mesmos 4 campos de `ItemPratoCalculado`; os 4 pontos que constroem esse objeto (`calcularPrato` × 2, `resolverComBuscaSemantica` × 2) e a serialização HTTP (`itens_nao_reconhecidos`) agora propagam `categoria_consumo`/`unidade_medida_padrao`/`medida_padrao_nome`/`medida_padrao_qtd`, espelhando exatamente o que já existia para `itens`.

**Frontend** (Flutter): `ItemPratoNaoReconhecidoModel` ganhou os mesmos 4 campos + parsing. Extraída `_unidadeParaCategoria` (função de nível de arquivo em `confirmacao_prato_page.dart`, reaproveitando a mesma decisão que `_unidadeBase` já usava para o badge dos itens resolvidos) — `_ItemNaoReconhecidoTile` agora usa essa função para: (a) o rótulo/sufixo do campo de peso manual ("Peso (ml)" em vez de "Peso (gramas)"); (b) a lista de medidas cadastradas exibidas no diálogo (ex.: "colher de sopa (15ml)", não "15g").

**Dois achados extras corrigidos no caminho, mesma causa raiz (Regra 23/UX)**:
- `ConfirmacaoPratoController.resolverComPesoManual` gravava a medida sempre como `'${valor}g'`, mesmo para um líquido — agora deriva a unidade do próprio item (`_unidadeParaItemNaoReconhecido`) e grava `'${valor}ml'` quando é o caso.
- `_promoverItemResolvido` (mesmo controller) nunca copiava `categoriaConsumo`/`unidadeMedidaPadrao`/`medidaPadraoNome`/`medidaPadraoQtd` para o item promovido — resultado: mesmo resolvendo certo, o badge do card (RELATÓRIO 20260901_0003) voltava a mostrar "g" depois de resolver um líquido manualmente. Corrigido copiando os 4 campos na promoção. **Achado por teste automatizado, não por inspeção** — o teste "digitar 240 resolve com badge '240ml'" falhou na primeira tentativa exatamente por causa deste bug, confirmando que era real antes de existir qualquer suposição.
- `_botaoEditarCustomizado` (botão "Customizar" nos cartões de líquido frio/quente, já existentes desde 20260830_0001) já recebia `unidade: 'ml'` como parâmetro mas nunca repassava para `_mostrarDialogoEditarPeso` — o diálogo de "Customizar" de um suco/café/chá sempre pedia "Peso (gramas)". Corrigido threading o parâmetro (`unidade` com default `'g'`, preservando os 2 call sites de sólido/fatia inalterados).

Nova chave i18n `confirmacao_prato.peso_com_unidade` ("Peso ({{unidade}})") substitui `peso_gramas` (removida — sem mais nenhum uso) nos 3 idiomas.

## Testes

- **Deno**: nenhuma mudança de comportamento fora do contrato aditivo — `extract-metric-photo` 119/119, `deno check` limpo.
- **Flutter**: 8 testes novos — 1 no modelo (`ItemPratoNaoReconhecidoModel.fromJson` parseia os 4 campos novos + 2 asserts extras no teste "sem os campos de N27" confirmando `isNull`), 5 em `confirmacao_prato_page_test.dart` (medida cadastrada mostra "ml" não "g"; campo manual pede "Peso (ml)"; resolver com valor manual gera badge "240ml"; item sólido não regride — continua "Peso (g)"/"g"; botão "Customizar" de um líquido já resolvido também pede "ml"), 1 em `confirmacao_prato_controller_test.dart` (`resolverComPesoManual` grava medida em "ml" E propaga a categorização pro item promovido). `flutter analyze` limpo nos 6 arquivos tocados (2 infos pré-existentes, mesmas linhas de sempre, só deslocadas). `flutter test test/features/nutrition test/features/dashboard`: **364/364**, zero regressão.

## Análise e sugestão de merge

Mudança aditiva no contrato HTTP (novos campos opcionais, nenhum campo removido/renomeado) — não quebra nenhum cliente antigo. A correção de UI é puramente de rótulo/formatação (nenhuma mudança na matemática: densidade ~1 já era assumida em todo o app desde o badge de 20260901_0003). Recomendo mesclar em `main` assim que o fundador autorizar. Depois do merge, lembrete de sempre: `supabase functions deploy extract-metric-photo` (sem CI/CD no repo).

**Não corrigido nesta tarefa, registrado para decisão futura**: os aliases genéricos demais ("suco" solto, possivelmente outros como "leite"/"arroz" em outras linhas — não auditados) que causam falso-positivo de casamento em `encontrarAlimento` para frutas sem entrada própria no catálogo (achado do caso "manga"/"abacaxi" acima) — risco real de cálculo nutricional silenciosamente errado, maior que o de "medida não encontrada". Requer decisão de curadoria (remover aliases genéricos demais ou adicionar as entradas de suco que faltam) antes de qualquer mudança de código no algoritmo de match.
