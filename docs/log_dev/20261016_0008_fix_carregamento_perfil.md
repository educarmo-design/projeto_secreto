# "Meu Perfil" não trazia as informações do usuário — tela carregava vazia, sem erro

**Tipo:** Bug real, confirmado no device físico.

## Diagnóstico do Frontend (Flutter) — await/setState corretos, mas um `null` silencioso virava "sucesso vazio"

`MeuPerfilPage._carregar()` já aguardava `_repository.buscarPerfilConta()`
corretamente (`await`), já gerenciava `_status` (`carregando`/`sucesso`/
`erro`) via `setState`, e já mostrava `CircularProgressIndicator` durante o
carregamento (Restrição desta tarefa já estava, sem saber, satisfeita). O
`catch` também não escondia nada — qualquer exceção virava `_status =
erro`, visível.

O problema real: `buscarPerfilConta()` podia devolver `null` SEM lançar
exceção nenhuma, e `_carregar()` tratava esse `null` como um resultado
válido — `_status` ia pra `sucesso` do mesmo jeito, só que com todo campo
vazio/"Não informado"/"—". Pra quem olha a tela, isso é indistinguível de
"nada carregou" — exatamente o relatado.

## Diagnóstico do Backend (RPC `meu_perfil_seguro`) — achado real

`meu_perfil_seguro()` faz `where p.id = auth.uid()` e devolve
`returns table(...)` — se não existir linha em `perfis_usuarios` para este
usuário, a RPC responde CORRETAMENTE com uma lista JSON vazia (`[]`), não
um erro. A versão anterior de `buscarPerfilConta()` tratava lista vazia
exatamente como "ninguém logado" (`return null`).

Isto é o MESMO achado já documentado (e corrigido para outros campos) em
`PerfilUsuarioRepository.atualizarDataNascimento` — conta real encontrada
nesta base (`atleta1000@teste.com`) com `auth.users` cheio de dados mas
ZERO linha em `perfis_usuarios` (provisionada fora do fluxo normal de
cadastro). A Tela de Perfil (RELATÓRIO 20261016_0005, PR #10) foi a
primeira a chamar `meu_perfil_seguro()` — e a primeira a reintroduzir esse
mesmo gap, sem querer, numa função nova.

## Correção

`PerfilUsuarioRepository.buscarPerfilConta()`:

- Quando `meu_perfil_seguro()` devolve lista vazia (perfil ainda não
  existe, não "ninguém logado"): **cria a linha** via
  `.upsert({'id': usuarioId}, onConflict: 'id')` — mesmo padrão seguro já
  usado no resto da classe (idempotente, nunca sobrescreve nada que já
  exista, RLS `perfis_usuarios_insert_own` já permite) — e devolve um
  `PerfilContaResumo` com o **e-mail da sessão de autenticação**
  (`_supabase.auth.currentUser?.email`, sempre disponível, nunca cifrado)
  em vez de `null`/tela vazia. Nome/tipo de perfil/CEP ficam vazios de
  verdade (ainda não há nada pra mostrar) — nunca inventados.
- Mesmo fallback para o caso da linha já existir mas `perfis_usuarios.email`
  estar nulo (cadastro antigo, ou nunca confirmado) — nunca mais mostra
  "Não informado" se o Supabase Auth já sabe o e-mail de quem está logado.

Nenhuma mudança em `MeuPerfilPage` foi necessária — o `await`/`setState`/
spinner já estavam corretos; a correção pertence inteiramente à camada de
dados.

## Verificação

- `PerfilUsuarioRepository` ganhou cobertura de teste que não existia antes
  desta tarefa para `buscarPerfilConta`/`atualizarNomeECep` (gap real,
  achado ao investigar: nenhum dos dois tinha teste dedicado desde que
  foram criados no PR #10) — 4 testes novos para `buscarPerfilConta`
  (incluindo o cenário exato do bug: RPC vazia → cria a linha → cai pro
  e-mail da sessão) + 2 para `atualizarNomeECep`.
- `flutter analyze`: 30 issues (linha de base, zero novo).
- `flutter test`: **550/550** (era 544/544, +6 novos).

## Banco de dados

Nenhuma migration nova — `perfis_usuarios_insert_own` já permitia o
`upsert` usado na correção.

Branch `fix/carregamento-meu-perfil`, a partir de `main`.
