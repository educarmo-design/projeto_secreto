# 20260821_0001_card_consumo_meta_e_n15_aparelho_por_foto — Card consumo × meta (N12) + persistência de aparelho por foto (N15)

Log de Máquina (Regra 10.3 — append-only). Modo autônomo (fundador
dormindo, autorização ampla dada na conversa: "qualquer pergunta que
aparecer daí pra frente é sim, desde que não gere problema pro
projeto"). Continuação da fila de backlog Fase 4-5 do Documento Mestre
v7.0 — depois de N16 (hidratação), fundador pediu pra desenvolver os 4
itens restantes do bloco H/I: card consumo×meta, favoritas (N13), editar
unidade de medida, N15 aparelho por foto. Este relatório cobre os 2
primeiros (mais simples/autocontidos); os 2 seguintes ficam em
relatório(s) separado(s).

## 1. Card consumo × meta (N12)

Spec (Documento Mestre Parte V1.H): "Card consumo × meta: ao longo do
dia, quanto falta / quanto passou."

Decisão de arquitetura: **sem tabela/coluna nova** — reaproveita
infraestrutura já pronta dos dois lados:
- **Consumo**: soma `valor_jsonb->totais` de todas as linhas
  `coleta_diaria` (`atributo='refeicao'`) de hoje — novo
  `ColetaDiariaRepository.buscarConsumoHoje()`, mesmo padrão de
  `buscarHistoricoAgua` (poucas linhas/dia, soma em Dart, não RPC).
- **Meta**: novo `MetaBemEstarRepository.buscarMetaEfetivaAtual()` —
  extrai a MESMA regra de precedência que `MetaBemEstarPage._carregar`
  já usa (profissional ativo sempre vence; senão a última meta própria)
  pra não duplicar a regra numa segunda tela.

UI: novo 10º id na Fábrica de Widgets já existente
(`DashboardWidgetId.consumoMeta`/`ConsumoMetaCard`) — calorias
consumido/meta, "faltam X kcal" ou "X kcal acima da meta", barra de
progresso, macros (proteína/carbo/gordura) quando a meta os define. Só
leitura/resumo, sem botão de ação (a tela de definir/editar meta já
existe própria, `MetaBemEstarPage`). `null` de meta = "defina sua meta"
(não erro); `null` de consumo = "carregando" — os dois estados nunca
mostram "0" antes da primeira leitura real.

Recarrega automaticamente depois de qualquer captura de prato
(`MainNavigationPage._capturarEExibir` agora chama
`_carregarConsumoMeta()` ao final, sempre — custo desprezível quando não
houve mudança, e `pratoRefeicao` confirma a refeição numa navegação
aninhada que este método nem enxerga o retorno, então "sempre recarrega
ao terminar a captura" é mais simples e correto que tentar adivinhar se
mudou).

## 2. Persistência de aparelho por foto (N15)

Spec: balança/pressão arterial/glicosímetro extraídos por foto
persistem em `coleta_diaria`, igual à refeição/hidratação.

**ACHADO REAL** (não suposição, confirmado lendo o código): até esta
tarefa, `HealthPayloadDialog`'s botão "Confirmar" só dava
`Navigator.pop()` — nenhuma chamada ao Supabase em lugar nenhum. O dado
extraído se perdia ao fechar o diálogo, mesmo o usuário "confirmando".
As 3 telas que abrem esse diálogo (`MainNavigationPage`,
`RegistrarMetricaPage`, `SeniorDashboardPage`) nunca sabiam disso.

Corrigido: novo `ColetaDiariaRepository.gravarLeituraAparelho()` —
`valor_jsonb` = `HealthPayloadModel.toJson()` inteiro (mesmo padrão de
`gravarRefeicao`, uma leitura atômica não fragmentada em EAV puro),
`atributo` = `'balanca'`/`'pressao_arterial'`/`'glicosimetro'` (texto
livre, resolvido pelo chamador — a classe não depende do enum
`TipoAparelho` de `dashboard`). `showExtractedDataDialog` renomeado pra
`mostrarDialogoConfirmarLeituraAparelho`: agora grava ao confirmar e
mostra snack de sucesso/erro (mesmo padrão de feedback de
`RegistroHidratacaoPage`) — as 3 telas atualizadas pro novo nome/
comportamento.

## Verificação

- `flutter analyze`: limpo (0 erros/warnings novos).
- `coleta_diaria_repository_test.dart`: +8 testes (`gravarLeituraAparelho`
  grava campos certos/falha sem login; `buscarConsumoHoje` soma/zero sem
  refeição/zero sem login).
- `meta_bem_estar_repository_test.dart`: +2 testes
  (`buscarMetaEfetivaAtual` — profissional vence com short-circuit
  verificado por contagem de chamada; sem profissional cai pra própria,
  as duas consultas rodam).
- `health_payload_dialog_test.dart` (novo): 4 testes — confirmar grava
  com o atributo certo e mostra snack de sucesso; cancelar nunca chama o
  repositório; falha mostra a mensagem de erro do repositório;
  glicosímetro mapeia pro atributo certo.
- Precisou atualizar 2 fakes `implements ColetaDiariaRepository`
  pré-existentes (`confirmacao_prato_controller_test.dart`/
  `confirmacao_prato_page_test.dart`) com os 2 métodos novos
  (`UnimplementedError`, nunca exercitados) — mesma mecânica já vista em
  tarefas anteriores.
- `flutter test` (suíte inteira): 359 testes passando (+11 desde o
  relatório anterior), mesmas 11 falhas pré-existentes e não
  relacionadas de `confirmacao_prato_page_test.dart` — nenhuma falha
  nova.

## Não resolvido / próximo passo

Nada verificado em device físico (fundador dormindo). Seguindo pra N13
(favoritas) e edição de unidade de medida — relatório(s) separado(s).
