# 20261123_0002 — N43 Etapa 2: instantes do sono + tipo da refeição nos 4 métodos

**Data:** 2026-11-23
**Branch:** `feat/n43-etapa2-sono-instantes-tipo-refeicao` (a partir de `main` em `cf91ad9`, com o PR #26 já mesclado)
**Persona:** Dados/Backend + Flutter (Mestre v9.2.1 — Parte 3.5 G.2/G.3/G.9; regras 10, 16, 17, 21, 22, 23, 25, 27, 29)
**Base:** investigação em `20261123_0001_investigacao_n43_etapa1_sono_e_tipo_refeicao.md` (mesclada, PR #26). **Correção importante desta tarefa:** as 360 refeições antigas citadas na Etapa 1 são, na verdade, **120** (ver seção de correção naquele log).

## Contexto

O fundador antecipou a Etapa 2 do N43 para começar a acumular histórico real: (1) persistir início/fim do sono (que era descartado) e (2) persistir o tipo da refeição nos 4 métodos de registro.

## O que mudou

### Banco — migration `20261123100000_n43_etapa2_sono_instantes_e_tipo_refeicao.sql` (aplicada com `supabase db push --linked`)
- `metricas_saude_diarias`: `sono_inicio` e `sono_fim` (`timestamptz`, UTC), `sono_offset_minutos` (integer, fuso vigente em `sono_inicio`), `sono_segmentos_qtd` (smallint). CHECKs: início/fim andam juntos; fim ≥ início; offset entre −840 e 840; qtd ≥ 1; instantes exigem offset.
- `coleta_diaria`: `tipo_refeicao` (text), CHECK nos 4 valores (`cafe_da_manha`, `almoco`, `lanche`, `jantar` — os mesmos de `alimentos_favoritos`) e CHECK "só em `atributo = 'refeicao'`". **Nulo permitido** (ver riscos).
- `configuracoes_sistema`: nova linha `cliente_sono_uniao_segmentos_minutos` = `30` + **policy `configuracoes_sistema_select_cliente`** (SELECT para `authenticated`, só chaves com prefixo `cliente_`). Necessária porque, até hoje, essa tabela só era legível por administrador; sem ela o app comum não leria o parâmetro.
- Regra 10 (RLS + policy + GRANT): RLS reafirmado nas 3 tabelas (as policies por `auth.uid()` já existentes cobrem as colunas novas); `REVOKE ALL … FROM anon` nas 3 (mesma causa do achado do N44: o `anon` tinha DML por default privileges); `GRANT` nominal a `authenticated`.
- **Nenhuma função/RPC criada ou alterada** ⇒ a postura da decisão 97 para funções não foi necessária.

### App — sono
- `lib/features/dashboard/data/services/sono_segmentos.dart` (novo): `consolidarSegmentosDeSono` — função pura. Une intervalos separados por **menos** que a janela (e sempre os que se tocam/sobrepõem); se sobrar mais de um segmento a noite é **ambígua** e a função **não escolhe** nenhum.
- `health_sync_service.dart`: `_mesclarPorDia` agora junta os intervalos crus de cada dia e `_aplicarInstantesDeSono` grava `sono_inicio`/`sono_fim` (UTC), `sono_offset_minutos` (via `_offsetParaInstante`, o histórico de fuso que já existia) e `sono_segmentos_qtd`. `_lerJanelaUniaoSonoMinutos` lê a janela de `configuracoes_sistema` (só quando o lote tem sono). **Os minutos por estágio e a `data_referencia` não foram tocados** (heurística das 15h intacta — G.9: "a que noite pertence" não é assado na gravação).
- Fonte dos instantes: **os limites dos próprios estágios** (`dateFrom`/`dateTo` já lidos no sync), não `SLEEP_SESSION`. Motivo: nenhuma permissão/leitura nova; `SLEEP_SESSION` continua fora do sync pela decisão antiga documentada. Os estágios (incluindo "acordado") cobrem de deitar a acordar.

### App — tipo da refeição
- Coluna dedicada em vez de chave de `valor_jsonb` — escolha documentada: domínio fechado vira CHECK; é filtro natural dos templates; e `payloadRevisado()` também é o `payload_jsonb` reaproveitável das favoritas, então o tipo da refeição consumida não pode vazar para dentro dele.
- `ColetaDiariaRepository.gravarRefeicao` ganhou `required TipoRefeicao tipoRefeicao` e grava `tipo_refeicao`.
- `ConfirmacaoPratoController`: novo estado `tipoRefeicao`, `selecionarTipo`, parâmetro `tipoRefeicaoInicial`; `confirmar()` **recusa gravar sem tipo** e mostra o aviso na tela (regra 23). Editar o conteúdo de uma favorita (`aoConfirmar`) não exige tipo.
- `ConfirmacaoPratoPage` (funil único dos 4 métodos): seletor com 4 chips, **sem valor padrão** (nunca sugere pela hora do dia). Oculto ao editar uma favorita.
- `FavoritasPage._usarFavorita`: passa `favorita.tipoRefeicao` como `tipoRefeicaoInicial` ⇒ favorita já abre com o tipo selecionado.
- i18n (pt/en/es): `tipo_refeicao_label` e `tipo_refeicao_obrigatorio`.
- Painel web: tipos de `metricas_saude_diarias` em `database.ts` e comentário de `AdminConfiguracoes.tsx` atualizados (regra 27; a tela já edita a nova chave sem mudança de código).

## Decisões | motivo
1. **Instantes pelos limites dos estágios** (não `SLEEP_SESSION`): zero permissão nova, sem mudar o que o sync lê.
2. **Noite ambígua não é arbitrada**: grava só `sono_segmentos_qtd > 1` e deixa os instantes nulos — o sinal fica visível no banco (regra 23). O caso típico é noite + cochilo no mesmo `data_referencia`.
3. **Config ilegível não vira janela chutada** (regra 16/23): sem a janela, o sync grava os minutos normalmente, **não** grava instantes e registra o motivo no log.
4. **Janela inicial = 30 min**: valor semente no banco, editável no painel (Admin › Configurações). É uma escolha minha — o fundador pode ajustar sem deploy.
5. **Tipo obrigatório só no app, nulo permitido no banco**: um `CHECK … NOT VALID` exigindo tipo quebraria o registro de refeições em qualquer app antigo ainda instalado. Endurecer depois do rollout.
6. **Sem retroativo** (regra 23): as **120** refeições antigas ficam com `tipo_refeicao` nulo (confirmado: 120 de 120 sem tipo).

## Infra/config
`supabase db push --linked` aplicou a migration. Nenhuma Edge Function tocada ⇒ **sem `functions deploy`** e sem exigência da regra 22.

## Entidades novas
Colunas: `sono_inicio`, `sono_fim`, `sono_offset_minutos`, `sono_segmentos_qtd` (em `metricas_saude_diarias`), `tipo_refeicao` (em `coleta_diaria`). Linha de configuração `cliente_sono_uniao_segmentos_minutos`. Policy `configuracoes_sistema_select_cliente`. Arquivo `sono_segmentos.dart`. Nenhuma tabela, função ou RPC nova.

## Verificação (medida nesta máquina e em produção)
- `flutter analyze`: 30 itens = teto do CI (0 erros). `flutter test`: **620 passam** (594 antes; +8 da união de segmentos, +7 do sync de sono, +6 do controller, +5 da tela). `tsc -b` do painel: ok.
- **Produção, com a conta de teste e linhas descartáveis (removidas depois):** refeição com tipo `jantar` aceita; `brunch` rejeitado (`coleta_diaria_tipo_refeicao_valido`); tipo em `agua_ml` rejeitado (`…_so_em_refeicao`); refeição **sem** tipo ainda aceita (app antigo não quebra); noite completa (início, fim, offset −180, qtd 1) aceita; instantes sem offset, fim antes do início e só-início rejeitados pelos CHECKs; estado ambíguo (qtd 2, instantes nulos) aceito. Policy nova: `anon` negado; usuário comum logado lê **só** `cliente_sono_uniao_segmentos_minutos` (não vê `idade_minima_anos` etc.).
- **Não verificado por mim:** uma sincronização real do Health Connect no aparelho e o registro real por foto/áudio/texto/favorita na tela — dependem do dispositivo do fundador (ver "Como o fundador testa").

## Desvios
- A pergunta pediu "ler SLEEP_SESSION e/ou limites dos estágios": usei só os limites dos estágios (decisão 1).
- A Etapa 1 e o prompt da Etapa 2 citavam 360 refeições antigas: o número real é 120 (erro de contagem da Etapa 1, corrigido naquele log).
- Um teste existente (`salvar como favorita sem nome preenchido…`) precisou de um localizador escopado ao diálogo, pois a tela agora tem dois textos "Café da manhã" (o chip e o item do diálogo). Não muda o que o teste verifica (regra 24).
- Os 4 testes e fakes de `gravarRefeicao` ganharam o parâmetro `tipoRefeicao` obrigatório (assinatura nova); não é mudança de especificação.

## Problemas encontrados
- Contagem inflada da Etapa 1 (acima).
- `metricas_saude_diarias` **não tem policy de DELETE** para o usuário: uma linha de teste minha ficou no banco e foi removida com acesso administrativo (`id` 9300, `origem = 'teste_n43'`). Conferido: 0 linhas de teste restantes nas duas tabelas. Não alterei essa política (o app nunca apaga métricas).

## Riscos mapeados
- **Janela de sync parcial:** `_lerEGravar` alinha o início da leitura à meia-noite local do último sync. Se uma sincronização rodar no meio da noite e a seguinte só começar depois da meia-noite, o início da noite fica fora da janela e o `upsert` pode sobrescrever `sono_inicio` com um instante posterior — o MESMO limite que já existe hoje para `minutos_sono`; não foi alterado nem piorado, mas os instantes herdam a mesma fragilidade.
- **Noites já sincronizadas** não têm instantes e só os ganham se o Health Connect ainda tiver o histórico e um novo sync cobrir aquela data.
- **Cochilo no mesmo dia da noite** torna a noite ambígua (instantes nulos, `sono_segmentos_qtd = 2`) até haver uma regra de negócio para isso — decisão do fundador.
- Refeições antigas e as gravadas por apps antigos seguem sem tipo; endurecer com CHECK `NOT VALID` só depois do rollout.
- Qualquer valor em chave `cliente_*` é legível por todo usuário logado.

## Como o fundador testa
1. **Sono:** recompile o app (`flutter run --dart-define-from-file=config_local.json`), rode a sincronização do Health Connect e confira em `metricas_saude_diarias` que a noite de ontem tem `sono_inicio`, `sono_fim`, `sono_offset_minutos` (ex.: −180) e `sono_segmentos_qtd = 1`, e que `minutos_sono`/leve/profundo/REM/acordado seguem iguais aos de antes — inclusive numa noite que passa da meia-noite.
2. **Refeição:** registre uma por foto, uma por áudio, uma por texto e uma por favorita. Em cada uma a tela de confirmação deve mostrar os 4 chips **sem nenhum marcado** (foto/áudio/texto) e, na favorita, o tipo dela **já marcado**. Tocar em Confirmar sem escolher deve mostrar o aviso e não gravar.
3. Em `coleta_diaria`, as 4 novas linhas devem ter `tipo_refeicao` igual ao escolhido (`select tipo_refeicao, origem, criado_em from coleta_diaria where atributo = 'refeicao' order by id desc limit 4`).
4. As 120 refeições antigas devem continuar com `tipo_refeicao` nulo.
5. (Opcional) Em Admin › Configurações do painel, o parâmetro `cliente_sono_uniao_segmentos_minutos` aparece e pode ser ajustado.

## Performance
Uma leitura extra (1 linha de `configuracoes_sistema`) por sincronização, e só quando o lote tem sono; ordenação de poucos intervalos por dia em memória; sem consulta nova na tela de refeição; sem índice novo (tabelas pequenas — 120 refeições; reavaliar índice em `(usuario_id, tipo_refeicao, data_coleta)` quando os templates por tipo forem consultas pesadas).

## Arquivos
Novos: `supabase/migrations/20261123100000_n43_etapa2_sono_instantes_e_tipo_refeicao.sql`, `lib/features/dashboard/data/services/sono_segmentos.dart`, `test/features/dashboard/data/services/sono_segmentos_test.dart`.
Alterados: `health_sync_service.dart`, `coleta_diaria_repository.dart`, `confirmacao_prato_controller.dart`, `confirmacao_prato_page.dart`, `favoritas_page.dart`, `assets/i18n/{pt,en,es}.json`, `web_painel/src/core/types/database.ts`, `web_painel/src/features/admin/components/AdminConfiguracoes.tsx`, testes (`health_sync_service_test`, `confirmacao_prato_controller_test`, `confirmacao_prato_page_test`, `favoritas_page_test`), log da Etapa 1 (mesclagem + correção) e este log + `INDICE.md`.
