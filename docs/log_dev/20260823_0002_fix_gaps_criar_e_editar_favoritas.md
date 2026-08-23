# 20260823_0002_fix_gaps_criar_e_editar_favoritas — Fecha os 2 gaps de Favoritas (N13) achados pelo fundador testando em device

Log de Máquina (Regra 10.3 — append-only). Continuação direta do
RELATÓRIO 20260823_0001 (registro da pendência antes de começar a
trabalhar nela, pedido explícito do fundador).

## 1. Criar uma favorita direto na tela de Favoritas

Antes: o único jeito de criar uma favorita era o botão ⭐ na AppBar de
`ConfirmacaoPratoPage`, que exige fotografar/confirmar um prato
primeiro — a tela de Favoritas em si não tinha nenhum jeito de criar.

Entregue: nova `CriarFavoritaPage`, com um FAB "+" em `FavoritasPage`
abrindo ela. Reaproveita a Busca Manual de Alimentos
(`FoodSearchController`/`search-food`, Adendo v5.1 §A.3/§C.3) em vez de
duplicar busca — o usuário digita, toca num resultado pra adicionar
(100g por padrão, tocar de novo no mesmo item soma +100g em vez de
duplicar linha), ajusta gramas com +/- (passo de 10g, piso de 10g,
mesmo espírito do "nunca zera sozinho" do F10 Passo 3), remove. Ao
salvar, abre o mesmo diálogo de nome+tipo (ver item 3) e chama
`FavoritasRepository.salvar`.

**Achado que resolve um orphan code já registrado em memória**: o
Edge Function `search-food` estava marcado como "sem chamador" na
auditoria de código órfão/sem spec — `ManualFoodSearchPage` só EXIBE
resultados, nunca os usa pra nada. `CriarFavoritaPage` agora é um
chamador REAL de `FoodSearchController`/`search-food` com um propósito
completo (adicionar item), não deixa de ser órfão o cluster inteiro
mas dá um uso de produto de verdade a essa busca pela primeira vez.

Payload gerado é o MESMO formato de
`ConfirmacaoPratoController.payloadRevisado()` (itens com
nome/nome_identificado/medida/quantidade/gramas_estimados/calorias/
proteinas_g/carboidratos_g/gorduras_g/confianca, mais totais) —
`medida: 'g'`, `confianca: 1.0` (escolhido pelo usuário na busca, não
estimado por IA). Isso importa porque é o formato que o item 2 abaixo
precisa reconhecer de volta.

## 2. Editar o CONTEÚDO (itens/quantidades) de uma favorita já salva

Antes: só existia "trocar tipo"/"excluir" — a spec original (Parte
V1.H) só pedia essas duas, mas o fundador queria também editar o que
tem dentro. Nunca dava pra abrir uma favorita salva e mudar alimentos/
quantidades.

Entregue, reaproveitando em vez de duplicar:
- `ConfirmacaoPratoController` ganhou um parâmetro opcional
  `aoConfirmar` — função que sobrescreve o destino de `confirmar()`
  (por padrão grava uma refeição nova via
  `ColetaDiariaRepository.gravarRefeicao`). Guarda toda a máquina de
  estado (`salvando`/`erroSalvar`) de graça, só troca pra onde o
  resultado vai.
- `ConfirmacaoPratoPage` ganhou `FavoritaEmEdicao? favoritaEmEdicao`
  (só um `id`). Quando presente: título vira "Editar Favorita", botão
  ⭐ some (evita criar uma SEGUNDA favorita em vez de atualizar a
  atual), botão de baixo vira "Salvar alterações", e o controller é
  construído com `aoConfirmar` chamando
  `FavoritasRepository.atualizarPayload(id, payload)` no lugar de
  gravar refeição.
- `FavoritasRepository.atualizarPayload(id, payloadJsonb)` — novo
  método, mesmo padrão de `atualizarTipo` (UPDATE simples, RLS
  `alimentos_favoritos_update_own` garante dono).
- `FavoritasPage` ganhou "Editar itens" no menu de 3 pontos: faz
  `PratoRefeicaoExtracaoModel.fromJson(favorita.payloadJsonb)` (parse
  ESTRITO — funciona porque os dois lados desta ida-e-volta já são
  `payloadRevisado()`) e abre `ConfirmacaoPratoPage` em modo edição.
  Parse malformado (não deveria acontecer, mas nunca confiar) mostra
  snack de erro em vez de propagar a exceção pra tela quebrar.

Resultado: a tela inteira de edição de itens do F10 Passo 3
(incrementar/decrementar, editar peso por categoria — líquido frio/
quente, unidade/fatia, peso livre —, remover) é reaproveitada 1:1 pra
editar uma favorita, sem duplicar nenhum widget de edição.

## 3. Diálogo "nome + tipo" extraído e reaproveitado

`_DialogoSalvarFavorita` (privado, só existia dentro de
`confirmacao_prato_page.dart`) virou `DialogoNomeTipoFavorita`, público,
em `widgets/dialogo_nome_tipo_favorita.dart` — usado tanto ao favoritar
uma refeição confirmada quanto ao criar uma favorita do zero
(`CriarFavoritaPage`). Mesmo diálogo, título customizável por parâmetro
(`titulo`), zero duplicação de código de formulário.

## Verificação

- `flutter analyze`: limpo (0 erros/warnings novos — só os 2 infos
  `prefer_const_constructors` pré-existentes, código não tocado nesta
  tarefa).
- Testes novos:
  - `favoritas_repository_test.dart`: +2 (`atualizarPayload` — UPDATE
    correto pelo id, falha sem sessão).
  - `confirmacao_prato_controller_test.dart`: +4 (grupo `aoConfirmar`
    — chama o override em vez do repositório padrão, recebe o payload
    atualizado refletindo edições, expõe erro do mesmo jeito que o
    caminho padrão, comportamento padrão preservado quando `aoConfirmar`
    não é passado).
  - `confirmacao_prato_page_test.dart`: +3 (grupo `FavoritaEmEdicao` —
    título/botão mudam e ⭐ some em modo edição, salvar chama
    `atualizarPayload` e não `gravarRefeicao`, falha mantém a tela e
    mostra o erro).
  - `favoritas_page_test.dart`: +3 (FAB abre `CriarFavoritaPage` e
    recarrega ao voltar com sucesso; "Editar itens" abre
    `ConfirmacaoPratoPage` em modo edição com os itens certos; payload
    malformado mostra erro sem navegar) + 1 teste existente corrigido
    (texto do empty state mudou pra mencionar o FAB).
  - `criar_favorita_page_test.dart` (novo): 7 testes — tocar resultado
    adiciona com 100g, tocar de novo soma (não duplica), +/- ajustam
    10g respeitando o piso, remover esvazia e desabilita Salvar, salvar
    com sucesso chama `FavoritasRepository.salvar` com o payload exato
    (itens + totais calculados a partir dos macros por 100g), falha
    mostra erro sem sair da tela.
- `flutter test` (suíte inteira): **407 testes, ZERO falhas.**

## Não resolvido / próximo passo

Nada verificado em device físico ainda (trabalho local, sem fundador
testando em tempo real desta vez). Recomendo o fundador confirmar os 2
fluxos novos (criar do zero via busca, editar itens de uma favorita já
salva) no próximo teste em device antes de considerar o gap
definitivamente fechado.

Segue pendente, sem instrução de ação ainda: validação detalhada do
cálculo do card consumo×meta (N12), registrada como pendência no
RELATÓRIO 20260823_0001.
