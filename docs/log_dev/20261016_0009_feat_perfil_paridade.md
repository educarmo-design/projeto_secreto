# Paridade de Perfil Flutter↔Web — auditoria cruzada (achado: o Web não tem o que se pediu)

**Tipo:** Auditoria obrigatória (feita antes de qualquer código) + feature.

## Auditoria do Painel Web — resultado real

A tarefa partiu da premissa "a busca de CEP e o formulário de perfil já
estão implementados no Painel Web (React)". **Essa premissa está
incorreta** — confirmado por leitura completa do código antes de
escrever qualquer linha:

- `grep -rli "viacep\|cep" web_painel/src` só encontra uma menção: o tipo
  gerado `cep: string | null` em `database.ts` (um tipo TypeScript, não
  UI nenhuma).
- `grep -rln "perfis_usuarios" web_painel/src` lista 9 arquivos — nenhum é
  uma tela de "editar meu perfil". São: `App.tsx`/`core/supabase.ts`
  (sessão), `LoginPage.tsx` (formulário de CADASTRO/solicitação de acesso
  de PROFISSIONAL, não edição de perfil existente), e 4 telas `Admin*`
  (um admin curando o perfil de OUTROS usuários, nunca self-service).
- O único formulário com campos parecidos (`LoginPage.tsx`,
  `FormularioSolicitarAcesso`) tem: email, senha, nome, tipoProfissional,
  telefone, registroProfissional (registro no conselho profissional),
  dataNascimento. **Zero CEP, zero endereço.** Grava via
  `supabase.from('perfis_usuarios').insert(...)` (ou via
  `user_metadata`/`garantirPerfilPendente` quando a confirmação de e-mail
  está pendente) — é cadastro ÚNICO, nunca re-editável depois pelo próprio
  usuário no Web.
- Não existe, em lugar nenhum do Painel Web, uma tela de "meu perfil"
  self-service para o profissional logado editar os próprios dados.
  `obterProfissionalAtual()` só LÊ (`meu_perfil_seguro()`) pra decidir se
  a sessão tem acesso ao painel — nunca escreve.

**Conclusão da auditoria**: não há "paridade com o Web" a buscar aqui —
o Web não tem o recurso. O que de fato existia, nunca trazido para
`MeuPerfilPage`, é o telefone/endereço completo que o **próprio cadastro
do app Flutter** (`CadastroController`/`CadastroPage`) já coleta e grava
em `perfis_usuarios` desde sempre, com busca ViaCEP já implementada e
funcionando ali. Esta tarefa trouxe ESSES campos pra `MeuPerfilPage`,
reaproveitando a infraestrutura real que já existe — não inventando nada
do Web.

## Mapeamento de campos (RPC `meu_perfil_seguro` + tabela `perfis_usuarios`)

| Campo | Onde já existia | Trazido agora pra `MeuPerfilPage`? |
|---|---|---|
| `nome` | RPC `meu_perfil_seguro()` (PII cifrada) | Já estava (RELATÓRIO 20261016_0005) |
| `email` | RPC `meu_perfil_seguro()` (PII cifrada) | Já estava, somente leitura |
| `telefone` | RPC `meu_perfil_seguro()` (PII cifrada) — **já vinha na RPC, nunca lido** | **Novo** (editável) |
| `cep` | Coluna plana, cadastro (`CadastroController`) | Já estava |
| `logradouro`/`bairro`/`cidade`/`estado` | Colunas planas, cadastro (`CadastroController`) | **Novo** (editável, com busca ViaCEP) |
| `eh_profissional`/`tipo_profissional` | RPC `meu_perfil_seguro()` | Já estava, somente leitura |
| `data_nascimento`/`sexo_biologico` | `perfis_usuarios`, editável em **`PerfilUsuarioPage`** ("Meus Dados Físicos") | **Decisão: não duplicar** (ver abaixo) |
| `registro_profissional` | Só no cadastro de PROFISSIONAL (Web/Flutter) | Fora de escopo — `MeuPerfilPage` é a tela do paciente/atleta |
| `nickname` | `perfis_usuarios`, usado por vínculos/ranking | Fora de escopo (não citado na tarefa; uniqueness/identidade pública merece decisão própria) |
| `geo_ranking_id` | Calculado só no cadastro, a partir do CEP | **Limitação conhecida**: não recalculado ao editar o endereço aqui (ver abaixo) |

### Por que `data_nascimento`/`sexo_biologico` não foram duplicados

A tarefa cita "Data de Nascimento, Gênero" como exemplo de campo que
poderia existir no Web (não existe) — mas esses 2 campos **já são
editáveis no Flutter**, numa tela dedicada e deliberada
(`PerfilUsuarioPage`, "Meus Dados Físicos"), que os trata como insumo do
Motor Metabólico (N07), com sua própria trava de maioridade e IMC. Editar
os mesmos 2 campos em DUAS telas diferentes do mesmo app criaria risco de
divergência visual sem nenhum ganho — a decisão foi manter um único lugar
editável para eles, intocado por esta tarefa.

### Limitação conhecida: `geo_ranking_id`

Calculado só no cadastro, a partir do CEP, para bucketing de ranking
geográfico (`GeoRankingId.fromBrazil`). Editar o endereço em
`MeuPerfilPage` não recalcula esse bucket — se o usuário mudar de cidade
depois do cadastro, o ranking geográfico continua refletindo a cidade
antiga. Fora do escopo desta tarefa (gamificação/ranking é uma decisão de
produto separada); registrado aqui para não ficar escondido.

## Implementação

- `PerfilContaResumo`: novos campos `telefone`/`logradouro`/`bairro`/
  `cidade`/`estado`.
- `PerfilUsuarioRepository.buscarPerfilConta()`: passa a ler `telefone`
  da RPC (já vinha, só não era consumido) e `logradouro`/`bairro`/
  `cidade`/`estado` no MESMO `.select()` que já buscava `cep` (zero
  consulta nova).
- `PerfilUsuarioRepository.atualizarNomeECep()` → renomeado para
  **`atualizarDadosConta()`**, agora recebendo `telefone`/`logradouro`/
  `bairro`/`cidade`/`estado` além de `nome`/`cep` — mesmo `.upsert()`,
  mesmas colunas de sempre, **zero coluna nova, zero RPC nova**
  (Restrição da tarefa).
- `MeuPerfilPage`: novos campos de formulário — Telefone, CEP (já
  existia), Rua, Bairro, Cidade/Estado (lado a lado). Busca automática de
  endereço: novo parâmetro injetável `cepController` que reaproveita
  **literalmente o mesmo `CadastroController`** do cadastro (nenhuma 2ª
  implementação da chamada ao ViaCEP) — ao digitar 8 dígitos no CEP,
  preenche Rua/Bairro/Cidade/Estado e move o foco pra Rua.
  - **Sobre "mover o cursor pro Número"**: não existe coluna/campo de
    número de residência em `perfis_usuarios`, nem no cadastro, nem no
    Web (confirmado na auditoria) — criar uma violaria a Restrição
    explícita ("não criar coluna nova"). O foco move pra Rua (Logradouro),
    onde o usuário pode completar o número manualmente — mesmo padrão
    informal já usado no cadastro.

## Verificação

- `flutter analyze`: 30 issues (linha de base, zero novo).
- `flutter test`: **554/554** (era 550/550, +4 novos) — testes de
  `buscarPerfilConta`/`atualizarDadosConta` atualizados para os novos
  campos, e `meu_perfil_page_test.dart` reescrito com cobertura de
  validação (telefone/endereço vazios) e 2 testes dedicados ao ViaCEP
  (sucesso preenche os 4 campos; CEP inexistente mostra aviso, não quebra
  a tela) — usando `http.Client` mockado, nunca rede de verdade.
- `web_painel`: nenhum arquivo alterado (a auditoria confirmou não haver
  nada a trazer de lá) — nenhuma verificação adicional necessária.

## Banco de dados

Nenhuma migration nova, nenhuma RPC nova — Restrição da tarefa cumprida
integralmente: todas as colunas usadas (`telefone`, `logradouro`,
`bairro`, `cidade`, `estado`) já existiam em `perfis_usuarios` desde o
schema original, já gravadas pelo cadastro.

Branch `feat/perfil-paridade-web`, a partir de `main`.
