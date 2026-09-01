# RELATÓRIO 20260901_0001 — Higiene de chaves (R6/R15) + view perfis_pacientes_vinculados (R1)

**Data:** 2026-09-01
**Branch:** `fix/higiene-chaves-view-b5-b6` (não mesclada — ver "Estado das branches")
**Pedido:** Bloco B, itens 5 e 6 (Mestre v8.0 Parte 9.1): rotacionar a Service Role Key (R6), consolidar a `GEMINI_API_KEY` duplicada (R15), aplicar `security_invoker` na view `perfis_pacientes_vinculados` (R1).

**Escopo real entregue nesta tarefa: R15 (consolidado) + R6 (preparado, rotação em si pendente do fundador). R1 foi PAUSADO por decisão explícita do fundador** — ver seção dedicada abaixo, é o achado mais importante deste relatório.

## R1 — por que foi pausado (achado crítico)

Investigação (Regra 2 — investigar antes de presumir) encontrou uma contradição real entre o pedido e o histórico do próprio código:

- A view nasceu (`20260709180000_painel_web_profissional_rls.sql`) com `security_invoker = true`.
- Isso causou um bug real: com `security_invoker = true`, as tabelas-base são lidas com o papel de QUEM CONSULTA — então a RLS nativa de `perfis_usuarios` (que só libera `auth.uid() = id`) barrava o profissional, e a view devolvia **zero linhas para todo mundo**. "A lista de pacientes do painel web nunca funcionou."
- A migration `20260713140000_saneamento_grants_e_unificacao_rls.sql` corrigiu isso de propósito, com uma explicação técnica extensa no próprio SQL: `security_invoker = false` (+ `security_barrier = true`) faz a view rodar como o dono (bypassa RLS), e o `WHERE EXISTS (...vínculo ativo...)` da view passa a ser a autorização real — **decisão deliberada, já revisada, não um descuido**.

Reintroduzir `security_invoker = true` sem mais nada reproduziria exatamente esse bug, quebrando o próprio ACEITE do pedido ("Painel B2B lista os pacientes corretamente"). A única forma de fazer `security_invoker = true` funcionar é adicionar uma policy de RLS em `perfis_usuarios` autorizando o profissional por vínculo ativo — mas:

- `perfis_usuarios` tem `grant select ... to authenticated` amplo (toda a tabela, não só a view).
- A tabela tem colunas sensíveis que a view **nunca expõe**: `email` (texto plano), `nome`/`telefone`/`logradouro`/`bairro`/`cidade`/`estado`/`cep` (cifrados em repouso desde o D2, mas ainda assim dados que a view foi desenhada para nunca vazar — ver comentário original: "expõe 4 campos e NUNCA nome/telefone/email/endereço").
- Uma policy de RLS não sabe diferenciar "acesso vindo da view" de "acesso vindo de uma query direta na tabela" — qualquer policy que autorize o profissional por vínculo abriria a tabela **inteira** (todas as colunas) pra ele, não só os 4 campos da view. Isso seria um vazamento de PII **pior** do que o risco que R1 tenta fechar.

Apresentei essa contradição ao fundador com 3 opções (manter+blindar com testes / implementar mesmo assim com o risco de PII / pausar). **Decisão do fundador: pausar R1 nesta tarefa**, avançar só com R6+R15. A view continua exatamente como está hoje (`security_invoker = false`, `security_barrier = true`, WHERE por vínculo) — nenhuma linha de SQL foi tocada. Nenhuma regressão, nenhuma mudança de comportamento no Painel B2B.

**Registrado para retomar depois, com mais tempo de desenho:** a forma correta de resolver R1 de verdade (não só marcar uma flag) provavelmente exige separar as colunas sensíveis de `perfis_usuarios` numa tabela própria que profissionais NUNCA têm grant nenhum, deixando `perfis_usuarios` só com o que é seguro expor por RLS direta — um refactor de schema, não um flag flip. Fora do escopo de "horas de trabalho".

## R15 — GEMINI_API_KEY consolidada

**Achado:** a chave não estava duplicada entre Edge Functions (confirmado via `supabase secrets list` — existe exatamente UMA `GEMINI_API_KEY` no projeto, compartilhada por `extract-metric-photo` e `search-food`, como deveria). A duplicação real é entre **essa secret do projeto** e **`web_painel/.env.local`** (cópia local, usada pelos scripts administrativos `curar_catalogo_alimentos_ia.ts`/`seed_food_embeddings.ts`, que rodam fora do runtime das Edge Functions e por isso não conseguem ler a secret do projeto diretamente). As duas cópias eram mantidas manualmente, sem nenhuma sincronização — exatamente o mesmo padrão de risco já documentado no cabeçalho de `seed_food_embeddings.ts` para `EMBEDDING_MODEL_NAME` ("troque a secret da Edge Function pro mesmo valor depois, ou os três lados divergem de novo").

**Correção:** `web_painel/.env.local` passa a ser a ÚNICA fonte onde o valor é digitado — novo script `web_painel/scripts/sincronizar_gemini_secret.ts` (`npm run secrets:sync-gemini`) lê o valor de lá e empurra pro secret do projeto via `supabase secrets set --env-file <temp>`. A API de secrets do Supabase nunca devolve o valor em texto puro de volta (confirmado: `supabase secrets list` só mostra um hash) — por isso a sincronização só pode ir NESSA direção, nunca "puxar" do Supabase pro local.

Testado de ponta a ponta nesta tarefa (rodei o script de verdade): sincronizou com sucesso, `{"count":1,"message":"Finished supabase secrets set."}`, sem deixar arquivo temporário residual (`finally` confirmado limpando o diretório temp mesmo em caso de falha).

`.env.example`/`.env.local.example` atualizados para deixar claro qual arquivo é a fonte de verdade de cada coisa (a versão anterior tinha as duas chaves elevadas duplicadas nos DOIS arquivos-modelo, um convite a colar o valor real no lugar errado).

## R6 — Service Role Key: preparado, rotação pendente do fundador

**O que eu confirmei/fiz:**
- Auditoria completa (árvore de trabalho + `git log --all -p` nos arquivos `.env`/`.env.local`): **zero ocorrência da chave real em qualquer arquivo rastreado, em qualquer commit do histórico.** `.env.local` está corretamente no `.gitignore` (via `web_painel/.gitignore`, confirmado com `git check-ignore -v`).
- Todo consumo da chave no código é via `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` (Edge Functions, quando alguma precisa) ou `process.env.SUPABASE_SERVICE_ROLE_KEY` (scripts, carregado de `.env.local` via `dotenv`) — nunca um literal.

**O que eu NÃO posso fazer** (e por quê, pra ficar registrado em vez de silenciosamente pulado): rotacionar a chave em si — gerar um valor novo e invalidar o antigo — é uma ação exclusiva do Dashboard do Supabase (ou de um token de Management API com escopo de escrita, que esta sessão não tem — confirmado: o CLI logado só lista secrets/API keys, não tem subcomando de criar/rotacionar). Nenhuma ferramenta que tenho acesso executa essa ação.

**Achado no caminho (transparência obrigatória — Regra 15 do Mestre):** ao investigar como listar as API keys atuais pra entender o sistema de chaves do projeto, rodei `supabase projects api-keys` (propositalmente SEM `--reveal`) — mesmo assim o comando devolveu a `anon key` e a `service_role key` **legadas** em texto pleno (só a chave nova `sb_secret_...` veio mascarada). Isso não vazou pra fora desta sessão/conversa, mas os valores ficaram visíveis no histórico dela. Reportado ao fundador em tempo real; ele optou por eu preparar tudo e ele mesmo rotacionar pelo Dashboard.

**Achado estrutural relevante pra R6:** o projeto já tem, desde a criação (09/Jul), o sistema NOVO de API keys do Supabase provisionado em paralelo ao legado — `sb_publishable_...` (substituto do anon key) e `sb_secret_...` (substituto do service_role key). O sistema novo permite rotação cirúrgica (revoga/gera sem invalidar sessões de usuário já logadas); o sistema legado (JWT) só rotaciona girando o **JWT secret inteiro**, o que invalida de uma vez a anon key, a service_role key, E todo token de sessão de usuário já emitido (todo mundo precisa logar de novo). O código hoje consome as chaves **legadas** (`SUPABASE_SERVICE_ROLE_KEY`/`SUPABASE_ANON_KEY`) em todo lugar — migrar pro sistema novo permitiria rotações futuras muito mais seguras, mas é uma mudança maior (toca Flutter, painel web, todos os scripts) que o fundador decidiu deixar pra depois.

### Passo a passo pra rotacionar (fundador executa)

1. **Dashboard → Project Settings → API.**
2. Localizar "Service Role Key" (legada) → botão de gerar/rotacionar o JWT secret. **Aviso real de impacto:** isso troca a `anon key` TAMBÉM (mesmo JWT secret) e invalida toda sessão de usuário ativa (todo mundo — inclusive você testando o app — precisa logar de novo). Fazer isso fora de horário de teste ativo.
3. Copiar o novo valor de `service_role key`.
4. Atualizar `web_painel/.env.local` (`SUPABASE_SERVICE_ROLE_KEY=<novo valor>`) — usado pelos scripts administrativos.
5. **Edge Functions:** não precisam de nenhum comando manual — `SUPABASE_SERVICE_ROLE_KEY` é uma secret auto-gerenciada pela própria plataforma (confirmado: apareceu em `supabase secrets list` com `updated_at` recente sem eu ter rodado `secrets set` pra ela) e é sincronizada automaticamente quando a chave rotaciona pelo Dashboard.
6. Se a `anon key` também mudou (mesmo JWT secret): atualizar `VITE_SUPABASE_ANON_KEY` em `web_painel/.env` e o equivalente no app Flutter (`lib/core/config/` ou onde a chave estiver configurada — não localizei nesta tarefa por estar fora do escopo de R6; próxima tarefa se isso for necessário).
7. Confirmar: `npx supabase secrets list` deve mostrar `SUPABASE_SERVICE_ROLE_KEY` com `updated_at` novo.

## Decisões técnicas

| Decisão | Motivo |
|---|---|
| R1 pausado em vez de forçar security_invoker=true | Reintroduzir seria reproduzir um bug já corrigido (zero linhas) OU abrir PII pior (email/nome/telefone via query direta) — decisão de produto/regulatória, não técnica pura; escalada ao fundador |
| Sincronização de GEMINI_API_KEY é sempre local → Supabase, nunca o contrário | A API de secrets do Supabase não devolve valor em texto puro (só hash) — fisicamente não dá pra "puxar" |
| Script de sync escreve um arquivo temporário com só 1 variável, não usa `--env-file .env.local` direto | Evita empurrar `SUPABASE_SERVICE_ROLE_KEY` (ou qualquer outra var futura do arquivo) como efeito colateral não pedido |
| `execSync` com string única em vez de `execFileSync` com array + `shell:true` | Node 24 despreza array+shell (argumentos não escapados) — evitável aqui porque só há 1 valor interpolado, gerado pelo próprio script, nunca entrada externa |
| Não tentei rotacionar a chave via Management API | Sem token de escrita disponível nesta sessão — confirmado que o CLI logado só lista, nunca cria/rotaciona |

## Infra/config

- Novo script `web_painel/scripts/sincronizar_gemini_secret.ts` + comando `npm run secrets:sync-gemini`.
- `web_painel/.env.example`/`.env.local.example` atualizados (documentação, sem mudança de valor).
- **Nenhuma migration.** Nenhuma secret nova criada — `GEMINI_API_KEY` foi apenas re-sincronizada (mesmo valor, confirmação de que os dois lados batem).

## Entidades novas

Nenhuma.

## Desvios de spec

- **R1 não implementado** — desvio explícito, autorizado pelo fundador em tempo real (ver seção dedicada acima). Não é um "pulei sem avisar": é a decisão registrada da pergunta feita durante a tarefa.
- Item 6 do ACEITE ("Painel B2B lista os pacientes corretamente respeitando o novo contexto RLS da view") não se aplica — não há contexto novo, a view não mudou.

## Problemas encontrados

- **Exposição acidental das chaves legadas (anon + service_role) em texto pleno** durante minha própria investigação (`supabase projects api-keys` sem `--reveal` ainda assim revelou as legadas) — reportado no ato, motivo real pra rotacionar logo, não só "porque estava há 23 dias aberto".
- Bug do Node no Windows (`execFileSync`/`npx`/`npx.cmd` incompatíveis entre si) — corrigido no próprio script antes de entregar, não deixado quebrado.

## Riscos mapeados + mitigação

- **R1 (alto, do Mestre) — continua ABERTO, sem mudança de status.** Mitigação real exige separar colunas sensíveis de `perfis_usuarios` numa tabela própria antes de qualquer tentativa de `security_invoker=true` — registrado como trabalho futuro, não estimado nesta tarefa.
- **R6 (alto/rápido, do Mestre) — parcialmente mitigado.** Auditoria de hardcode fechada (zero achados, histórico incluído); rotação em si aguarda o fundador. Risco elevado brevemente por causa da exposição no meu próprio comando de investigação — mitigação: rotacionar o quanto antes agora que o passo a passo está pronto.
- **R15 (alto/rápido, do Mestre) — fechado.** As duas cópias sincronizadas e confirmadas iguais; processo repetível documentado.
- **Risco novo, baixo:** o script de sync depende do CLI estar logado/linkado localmente (`supabase login`/`supabase link`) — se não estiver, falha com erro claro do próprio CLI (não silencioso).

## Como o fundador testa (ACEITE)

- **"A plataforma sobe localmente sem falhas de Auth"**: não há mudança de RLS/Auth nesta entrega (R1 pausado) — nada a testar aqui além do que já funcionava.
- **"O Painel B2B lista os pacientes corretamente"**: inalterado, mesma view de sempre.
- **"O registro por IA (foto/texto) continua funcionando"**: a chave sincronizada é a MESMA chave (só confirmei que os dois lados batem, não troquei o valor) — nenhuma mudança de comportamento esperada. Testar uma foto/texto de refeição normalmente confirma.
- **Rotação de fato**: seguir o passo a passo da seção R6 acima quando o fundador tiver uma janela sem teste ativo (todo mundo desloga).

## Como a performance foi tratada

Sem impacto — nenhum código de produção (Edge Functions, Flutter) foi tocado. O script de sync é uma ferramenta administrativa offline, roda uma vez por rotação de chave, não no caminho de produção.

## Verificação

- `web_painel`: `tsc -b` limpo (exit 0). `npm run lint`: 2 avisos pré-existentes em `seed_taco_completa.ts` (arquivo não tocado nesta tarefa), zero problema no arquivo novo.
- Script de sync testado de ponta a ponta contra o projeto real (não só lido) — sucesso confirmado, sem resíduo em disco.
- Nenhum arquivo Deno (Edge Functions)/Flutter tocado — suítes dessas camadas não re-executadas (fora do escopo desta entrega).

## Estado das branches

Trabalho em `fix/higiene-chaves-view-b5-b6`, criada a partir de `main`. **Não mesclada.**

**Instruções de PR:**

```
git push -u origin fix/higiene-chaves-view-b5-b6
gh pr create --base main --head fix/higiene-chaves-view-b5-b6 \
  --title "fix: consolida GEMINI_API_KEY duplicada (R15) + prepara rotação da Service Role Key (R6)" \
  --body "Ver docs/log_dev/20260901_0001_higiene_chaves_view_bloco_b.md — R1 (security_invoker) PAUSADO por decisão do fundador, ver relatório."
```

**Sugestão de merge:** seguro mesclar — mudança pequena, só documentação + 1 script administrativo novo, zero código de produção tocado, zero migration. **Mas o Bloco B do Mestre (item 6, R1) continua aberto** — não marcar R1 como resolvido no board/checklist; só R6 (preparado, rotação pendente) e R15 (fechado) avançaram. Por Regra 18, aguarda autorização explícita antes do merge em si.
