# 20261120_0003 — N44 (fechamento): auditoria de segredos/segurança + R25 (desligar anomalia de FC)

**Data:** 2026-11-20
**Branch:** `feat/n44-fechamento-auditoria-segredos-r25` (a partir de `main` com os PRs #23 e #24 mesclados)
**Persona:** Segurança/DevOps + Regulatório (Mestre v9.2.1 — Parte 6, S8/S8.1, decisão 70 / R25, decisão 97)

## Contexto

Fecha o N44 (merge do PR #23 registrado no log 0001, decisão 96) e executa duas frentes: (1) auditoria contra vazamento de chaves e contra exposição de funções no banco; (2) R25 — desligar a detecção/alerta de anomalia de frequência cardíaca (FC) no app avulso, mantendo só o valor medido pelo relógio ("alerta diagnostica; espelho descreve").

## Parte 1 — Auditoria de vazamento de chaves e segurança

**Escopo varrido:** os 586 arquivos rastreados e os **325 commits** de todo o histórico (todas as refs), por categoria, sem imprimir valores.

| Categoria | Arquivos rastreados (HEAD) | Histórico |
|---|---|---|
| `sb_secret_…` | nenhum | nenhum |
| `service_role` (JWT) | nenhum | nenhum |
| Chave Gemini/Google (`AIza…`, `AQ.…`) | nenhuma | nenhuma |
| Tokens genéricos (GitHub, AWS, Slack, `sk-`, chave privada PEM) | nenhum | não varrido no histórico |
| JWT `anon` (legado) | `docs/auditoria/20260729.txt` | só esse arquivo e versões antigas de `web_painel/.env.example` |
| `sb_publishable_…` (pública por desenho) | `web_painel/.env` | só `web_painel/.env` |

- A **única chave JWT achada em todo o repositório é a `anon` legada** (role decodificada localmente = `anon`). O fundador a **desativou em 2026-11-20T20:29Z** (a API responde `Legacy API keys are disabled`), então o vazamento histórico dela está neutralizado. **O histórico não foi reescrito** (sem force push). `docs/auditoria/20260729.txt` é documento antigo de auditoria e foi mantido como registro.
- **Cliente com chave privilegiada:** nenhuma ocorrência de `service_role`/`sb_secret` em `lib/` ou `web_painel/src` fora de comentários; nenhuma variável `VITE_*` com secret/service/Gemini.
- **`.gitignore` × `.env*`:** conferido. Versionados: `.env.example`, `web_painel/.env` (só valores públicos), `web_painel/.env.example`, `web_painel/.env.local.example`, `config_local.example.json`. Ignorados: `web_painel/.env.local` (guarda `SUPABASE_SECRET_KEY` e `GEMINI_API_KEY` reais), `config_local.json`, `.env` da raiz.
- **`config_local.example.json`:** a cópia de trabalho do fundador tinha uma `sb_publishable_…` REAL no arquivo de exemplo (não commitada; o HEAD tinha o placeholder). Restaurado ao placeholder com `git checkout`. O valor é público, mas um exemplo não deve carregar a chave real.
- **CI:** o guarda `.github/scripts/verificar_segredos.sh` (log 0001) já cobre `sb_secret_` e JWT `service_role`; não precisou de mudança.
- **IDs:** o *project ref* do Supabase aparece nas URLs públicas (`*.supabase.co`) — público por natureza; não tratado como segredo.

### FALHA REAL ENCONTRADA E CORRIGIDA — enumeração de contas por RPC anônima

- **O quê:** `public.resolver_usuario_id_por_email(text)` (SECURITY DEFINER, lê `auth.users`) era executável pelo papel `anon`. Com a chave publicável (pública), qualquer pessoa chamava `POST /rest/v1/rpc/resolver_usuario_id_por_email` e recebia o **UUID** de qualquer e-mail cadastrado (e `null` para um inexistente). Confirmado em produção antes da correção.
- **Causa:** a migration 20260713210000 fazia `revoke execute … from public`, mas o Supabase concede EXECUTE a `anon`/`authenticated` por *default privileges* (grants explícitos), que `revoke from public` não remove. A intenção documentada ("só service_role") nunca foi verdadeira.
- **Correção:** migration `20261120120000_revoga_execute_anon_funcoes_rpc.sql`, aplicada com `supabase db push --linked`: (1) `resolver_usuario_id_por_email` → só `service_role`; (2) 14 RPCs que só fazem sentido logado (`admin_*`, `anamnese_historico_peso`, `calcular_motor_metabolico{,_v1}`, `gerar_sugestao_meta`, `iniciar_rascunho_anamnese`, `processar_medias_smartwatch`, `profissional_*`, `validar_e_salvar_meta`) → revogado de `anon`, com `GRANT` explícito a `authenticated` (decisão 97). Todas já eram SECURITY DEFINER com `SET search_path` e validavam `auth.uid()`/`eh_admin()` no corpo; a revogação é defesa em profundidade.
- **Verificado:** como `anon`, `resolver_usuario_id_por_email` agora responde `42501 permission denied`; como usuário logado também nega (só service_role); logado, `meu_perfil_seguro`, `eh_admin` e `admin_listar_vinculos` seguem respondendo 200; **Convidar Paciente** (`manage-professional-link`, que chama o resolver com a chave secreta) respondeu `404 "Paciente não encontrado."` para e-mail inexistente — a função só devolve esse 404 se a RPC executou sem erro (erro de RPC vira exceção/500), então o caminho do service_role está íntegro.
- **Tabelas:** todas as tabelas de `public` têm RLS ligado e ao menos 1 policy; como `anon`, as leituras testadas devolveram `[]`.

### Pendências de segurança registradas (não corrigidas aqui, de propósito)

- `eh_admin` (usada por policies com roles `{public}`), `tem_permissao`, `meu_perfil_seguro`, `validar_macro_personalizado`, `match_alimentos`, `calcular_idade` seguem executáveis por `anon`. Revogar `eh_admin` pode quebrar avaliação de RLS; `tem_permissao(uuid,text)` permite consultar permissões de um UUID conhecido (baixo risco). Mover as RPCs administrativas para fora do schema exposto é refatoração própria (decisão 97) — **item separado**.
- Os *default privileges* do projeto ainda concedem EXECUTE a `anon` em funções novas: toda migration futura precisa de `revoke … from public, anon` explícito.
- `supabase/config.toml` só declara `verify_jwt` para 3 funções; `search-food` e `manage-professional-link` usam o padrão (`true`, conferido nos deploys do N44). Declarar explicitamente é higiene.

## Parte 2 — R25: desligar detecção/alerta de anomalia de FC

**Auditoria:** a detecção vivia só no app (`HealthSyncService._detectarEregistrarAnomalias`, ramo `frequencia_cardiaca_fora_faixa`: faixa 40–120 bpm, severidade `atencao`/`critico`). **Não há** trigger, função SQL nem Edge Function que gere alerta de FC (o comentário em `extract-metric-photo` só cita a checagem do app). As telas de FC (`historico_telemetria_page`, `historico_treinos_page`, `teste_frequencia_cardiaca_page`) só mostram o número + "bpm"/rótulo do campo — **sem faixa, zona rotulada ou palavra proibida**. Varredura das 3 línguas (`assets/i18n/{pt,en,es}.json`): a única ocorrência de vocabulário proibido foi `teaser_insight_placeholder` ("3 alertas preventivos…"), na tela de teaser de conversão — não é FC, mas "alerta" está na lista de proibidos do app avulso.

**Mudanças:**
- `health_sync_service.dart`: removido o ramo de FC e as 4 constantes de faixa (`_fcForaTreino*`, `_fcCritico*`); a Caixa Preta segue só para glicose/pressão (fora do escopo R25 — ver desvios). Documentação reescrita (Regra 27), substituindo o aviso regulatório antigo. Nova constante `HealthSyncService.tipoAnomaliaFcDesativado`.
- **Histórico não apagado:** as linhas antigas de FC continuam em `eventos_anomalias_saude`. Para não reaparecerem, `IntelligenceController._buscarAnomalias` (insight preventivo/Gemini) e `HealthScoreEngine._contarAnomalias` (pontuação) passaram a excluí-las com `.neq('tipo_anomalia', …)`.
- i18n: "alertas" → "insights" nos 3 idiomas do teaser.
- **Testes (Regra 24):** os 4 testes da antiga "Caixa Preta de FC" exigiam o INSERT com severidade atencao/critico — documentavam o alerta clínico que a decisão 70 manda remover; por isso foram **substituídos** (não só atualizados) por 5 testes: FC 155/165/30/72 fora de treino e 155 durante treino **não gravam nada**, e o valor medido segue espelhado (`linhas.single['frequencia_cardiaca']`).
- Nenhuma Edge Function tocada ⇒ **sem `supabase functions deploy`**. Migration aplicada com `db push --linked` (acima).

## Verificação

- `flutter analyze`: 30 itens (29 infos + 1 warning antigo) = teto do CI; 0 erros.
- `flutter test`: **594 passam** (antes 593; −4 testes de alerta de FC, +5 de espelho).
- Banco: probes como anon, logado e service_role descritos acima.
- **Não verificado por mim:** exibição visual das telas no aparelho e uma sincronização real de wearable (dependem do dispositivo do fundador) — ver "Como o fundador testa".

## Desvios

- Regra 22 (X-Request-Id/log de conclusão) não aplicada: nenhuma Edge Function foi tocada.
- Comentário defasado em `supabase/functions/extract-metric-photo/index.ts` (cita "checagem de anomalia de frequência cardíaca do app"): **não editado** de propósito, para não forçar novo deploy e a Regra 22 numa função de ~3 mil linhas por causa de um comentário.
- Glicose/pressão críticas continuam gerando `eventos_anomalias_saude` (R25 e decisão 70 citam FC; o mesmo princípio pode alcançar esses sinais) — **decisão do fundador**.
- O painel web (profissional, B2B) ainda lista `eventos_anomalias_saude` com `tipo_anomalia`; não é o app avulso e dados antigos de FC continuam visíveis ali — decisão do fundador se deve filtrar.

## Problemas encontrados

- A falha da RPC `resolver_usuario_id_por_email` (acima).
- A cópia local de `config_local.example.json` carregava a chave publicável real (restaurada).
- Um teste de glicose/pressão não existia para o laço de anomalias (a Caixa Preta de glicose/pressão não tem cobertura própria); removi o ramo de FC sem poder provar por teste que glicose/pressão seguem gravando — mudança é a remoção localizada de um bloco `if`, mas fica registrado.

## Riscos mapeados

- A revogação de EXECUTE a `anon` não afeta usuários logados (testado), mas qualquer fluxo não logado futuro que dependa dessas RPCs deixará de funcionar.
- A pontuação de saúde passa a ignorar anomalias antigas de FC (a penalidade, de até 0,20, pode diminuir para quem tinha muitas).
- Os fallbacks de chave legada (N44) viraram código morto após o Passo 4.

## Como o fundador testa

1. Leia a seção "Parte 1" deste log (varredura sem valores).
2. No app avulso, abra as telas com FC (histórico de telemetria, histórico de treinos, teste de FC) e confirme que os bpm do relógio aparecem normalmente.
3. Confirme que nenhuma tela/banner/notificação de FC mostra "normal/alterada", zona rotulada, "atenção", "alerta", "fora do normal", "risco" ou "procure um médico".
4. Rode uma sincronização do wearable e confirme que não surge alerta de FC (e nenhuma linha nova `frequencia_cardiaca_fora_faixa` em `eventos_anomalias_saude`).
5. No painel, teste **Convidar Paciente** com um e-mail real e um inexistente.

## Performance

Menos trabalho por sincronização (ramo de FC removido do laço) e duas consultas com um filtro `neq` a mais; sem impacto mensurável.

## Arquivos

`supabase/migrations/20261120120000_revoga_execute_anon_funcoes_rpc.sql` (novo); `lib/features/dashboard/data/services/health_sync_service.dart`; `lib/features/intelligence/data/services/health_score_engine.dart`; `lib/features/intelligence/presentation/controllers/intelligence_controller.dart`; `assets/i18n/{pt,en,es}.json`; `test/features/dashboard/data/services/health_sync_service_test.dart`; `docs/log_dev/20261120_0001_…` (seção de mesclagem), este log e `INDICE.md`.
