# Telas de Perfil, Histórico de Anamnese e Motor Metabólico — auditoria de teste em campo

**Tipo:** Feature nova (3 telas pedidas) + 1 achado "já existia, zero código
necessário". Contexto: o fundador está testando o app na rua com dados reais
de smartwatch acumulados e pediu 3 visualizações de auditoria/acompanhamento
para não perder esse histórico com um reset e ter controle total do teste.

## Item 3 — Histórico do Motor Metabólico: **já existia, nenhum código necessário**

Antes de escrever qualquer coisa, audite o que já existe (sempre o primeiro
passo nesta base). `MetaBemEstarRepository.buscarHistoricoMetas()`
(`meta_bem_estar_repository.dart`) e sua renderização em
`MetaBemEstarPage._buildHistorico` **já implementam exatamente o pedido**:

- Resultado ATUAL (calorias + macros P/C/G) sempre visível no topo, em todo
  estado da tela (bloqueada por carência, bloqueada por prescrição
  profissional, ou formulário liberado) — não só quando bloqueada.
- Lista completa do histórico de `objetivos_alimentares` (QUALQUER
  `status_vigencia`, mais recente primeiro), rotulada "Atual"/"Anterior" —
  exatamente "como a prescrição evoluiu ao longo do tempo".

A tarefa também sugeria `sugestao_meta` como fonte alternativa — essa tabela
existe (RLS própria, confirmada), mas é só o rastro de CÁLCULOS do Motor
(nunca a meta realmente salva); nada no app lê essa tabela hoje.
`objetivos_alimentares` via `buscarHistoricoMetas()` já é a fonte certa (a
meta de fato vigente/histórica, não um cálculo de passagem) e já cobre o
ACEITE da tarefa por completo. Implementar uma 2ª visualização a partir de
`sugestao_meta` seria duplicar informação sem necessidade — não foi feito.

**Nenhum arquivo deste item foi tocado.**

## Item 1 — Tela de Perfil (`MeuPerfilPage`)

Nova tela, distinta de `PerfilUsuarioPage` ("Meus Dados Físicos" — data de
nascimento/sexo biológico/altura, insumo do Motor Metabólico): esta é sobre a
IDENTIDADE da conta.

- **Leitura**: email, tipo de perfil (paciente, ou profissional com o tipo
  traduzido), lista de profissionais com vínculo **ativo** — tudo somente
  leitura, sem caminho de escrita para nenhum dos três.
- **Edição**: Nome e CEP, com botão Salvar — exatamente a Restrição da
  tarefa ("o usuário só pode editar Nome e CEP no Perfil").

### Achado de arquitetura: `nome`/`email` são PII cifradas em repouso

`perfis_usuarios.nome`/`telefone`/`email` são cifradas AES-256 por um
trigger (D2, `20260730160000_d2_pii_criptografia_repouso.sql`) — um
`.select('nome, email')` direto devolveria ciphertext ilegível. A única
leitura decifrada é a RPC `meu_perfil_seguro()` (SECURITY DEFINER, escopada a
`auth.uid()`), que **já existia no banco desde D2 mas nunca tinha um
chamador em lugar nenhum do app** (confirmado por busca — zero ocorrências em
`lib/`). Esta tarefa é a primeira a chamá-la.

`cep` NÃO é PII cifrada (coluna plana) — lida/gravada direto, mesmo padrão
do resto de `PerfilUsuarioRepository`.

### Decisão de escopo: sem autocomplete de endereço via ViaCEP

O cadastro (`CadastroController`) tem um fluxo completo de busca de endereço
por CEP (ViaCEP) que preenche logradouro/bairro/cidade/estado automaticamente.
A Restrição da tarefa é editar só Nome e CEP — reaproveitar o fluxo de
ViaCEP aqui ampliaria o escopo (edição de endereço completo) além do pedido.
Optei por um campo de texto simples para CEP (validação: 8 dígitos), sem
autocomplete. Se o fundador quiser o fluxo completo de endereço depois, é uma
tarefa separada e explícita.

### Vínculos ativos: nova consulta (gap que já existia)

`GerirVinculosPage`/`VinculosService.carregarConvitesPendentes()` só listam
convites **pendentes** (aceitar/recusar) — não existia nenhuma leitura de
vínculos já **ativos** em lugar nenhum do app. Novo método
`VinculosService.carregarVinculosAtivos()` (`status = 'ativo'`, mesmo padrão
de join em memória com a view `perfis_profissionais_vinculados` que o método
de convites pendentes já usa) + novo modelo `VinculoAtivoModel`.

### Arquivos

- `lib/features/dashboard/data/repositories/perfil_usuario_repository.dart`:
  novo modelo `PerfilContaResumo`; novos métodos `buscarPerfilConta()`
  (RPC `meu_perfil_seguro` + leitura de `cep`) e `atualizarNomeECep()`.
- `lib/features/vinculos/data/models/vinculo_ativo_model.dart` (novo).
- `lib/features/vinculos/data/services/vinculos_service.dart`: novo método
  `carregarVinculosAtivos()`.
- `lib/features/dashboard/presentation/pages/meu_perfil_page.dart` (novo).
- `lib/features/dashboard/presentation/pages/configuracoes_perfil_page.dart`:
  novo item de menu "Meu Perfil", primeiro da lista.
- i18n: namespace `meu_perfil.*` novo em pt/en/es.

## Item 2 — Detalhe de Anamnese (`AnamneseDetalhesPage`)

`HistoricoAnamnesesPage` já listava todas as anamneses passadas, mas os
cards eram inertes (sem `onTap`) — confirmado por leitura de código antes de
mudar qualquer coisa. Restrição da tarefa: "Nenhuma anamnese passada pode ter
seus dados sobrescritos" — esta tela é **100% somente leitura**, sem NENHUM
campo editável, sem botão de salvar.

### Novo método de repositório: ler UMA anamnese específica, por id

`AnamneseRepository` já tinha `buscarAnamneseAtiva()` (só a vigente) e
`buscarHistoricoAnamneses()` (lista resumida) — faltava "uma anamnese
específica, qualquer uma, com todos os campos". Novo
`buscarAnamnesePorId(String anamneseId)`: lê a linha inteira de `anamneses`
(`.eq('usuario_id', usuarioId)` como defesa em profundidade, além da RLS que
já restringe a leitura ao próprio dono) + resolve em paralelo as relações N:N
(problemas de saúde, alergias, atividades por dia da semana, medicamentos,
suplementos, exames laboratoriais) com os nomes já traduzidos via embed do
PostgREST — mesmo padrão de `buscarAnamneseAtiva()`.

Novo modelo `AnamneseDetalheModel` + função `dadosComplementaresDeJson()`
(leitura inversa de `DadosComplementaresAnamnese`, que até esta tarefa só
sabia ser GRAVADA via `salvarAnamnese` — nunca tinha sido lida de volta do
banco) em `anamnese_models.dart`.

### UI: seções que desaparecem quando vazias, nunca um "—" inventado

Regra 23 ("falhar visível, nunca arbitrar") aplicada ao inverso aqui: uma
anamnese antiga, preenchida antes de um bloco existir, não tem a maioria dos
~35 campos complementares. Cada seção (Dados Físicos, Condições de Saúde,
Alimentação, Atividade, Sono, Metas) só aparece se tiver pelo menos um campo
preenchido — sem mostrar um rótulo com valor "—"/vazio por padrão.

A maioria dos rótulos de campo **já existia** em i18n (reaproveitados de
`AnamneseSelfServicePage`, a tela que preenche esses mesmos campos) — só os
títulos de seção e as 3 mensagens de estado (erro/não encontrada/tentar de
novo) são chaves novas (`anamnese_detalhe.*`, pt/en/es).

### Arquivos

- `lib/features/nutricao/data/models/anamnese_models.dart`: novo modelo
  `AnamneseDetalheModel` + função `dadosComplementaresDeJson()`.
- `lib/features/nutricao/data/repositories/anamnese_repository.dart`: novo
  método `buscarAnamnesePorId()`.
- `lib/features/nutricao/presentation/pages/anamnese_detalhes_page.dart`
  (novo).
- `lib/features/nutricao/presentation/pages/historico_anamneses_page.dart`:
  `onTap` no card do histórico, abre `AnamneseDetalhesPage`.
- i18n: namespace `anamnese_detalhe.*` novo em pt/en/es.

## Banco de dados

**Nenhuma migration nova.** Toda leitura usa RPC/tabelas/RLS que já
existiam: `meu_perfil_seguro()` (existia desde D2, sem chamador até agora),
`vinculos_profissional_paciente` (policy `vinculos_select_participantes` já
permite o paciente ler os próprios vínculos em qualquer status), `anamneses`
e as 6 tabelas N:N relacionadas (RLS "own or vinculado ativo" já cobre
leitura do próprio dono). Nenhuma Policy/RPC nova foi necessária.

## Verificação

- `flutter analyze`: 30 issues (linha de base, zero novo).
- `flutter test`: **534/534** (era 524/524, +10 novos — 3 em
  `anamnese_repository_test.dart` para `buscarAnamnesePorId`, 4 em
  `anamnese_detalhes_page_test.dart`, 1 em `historico_anamneses_page_test.dart`
  confirmando a navegação pelo id correto, e 7 em `meu_perfil_page_test.dart`,
  incluindo validação de nome/CEP vazios/inválidos e confirmação de que
  nada é gravado quando a validação falha, e `verify()` do payload exato
  enviado a `atualizarNomeECep` no caminho de sucesso).

Sem deploy pendente — nenhuma Edge Function foi alterada.

Branch `feat/telas-perfil-historico`, a partir de `main`.
