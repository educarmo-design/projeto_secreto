# RELATÓRIO 20260916_0001 — Motor v1 Backend + UI (SSOT, Câmera, Rótulo)

**Data:** 2026-09-16
**Branch:** `feat/motor-v1-backend-ui` (a partir de `feat/app-anamnese-metas`, ainda não mesclada em `main` — este trabalho depende diretamente da captura de peso/altura/sexo entregue nela)
**Persona:** Arquiteto Fullstack e Banco de Dados (Mestre v8.0)

## Contexto

O fundador definiu regras arquiteturais estritas em `docs/motor_metabolico.txt` (documento novo, 3512 linhas, lido por completo): a Anamnese vira a **fonte única da verdade** para peso/altura (nunca mais atributo permanente do perfil), e o Motor Metabólico precisa ser centralizado no backend, implementando TMB-001 (Mifflin-St Jeor), TDEE por dia da semana, e proibido de gerar metas automaticamente (ME-005).

## Item 1 — Ajustes de UI

### Câmera

Botões da tela de captura (`CameraCaptureView`) subiram de `bottom: 32` para `bottom: 42` (+10px, dentro da faixa pedida de 8–12px/~2mm).

### Rótulo Nutricional

Substituído o JSON cru (`SelectableText`/`JsonEncoder.withIndent`) por um card nutricional tipado e **editável**: novo modelo `RotuloExtracaoModel` (espelha o contrato real de `extract-metric-photo` para `X-Tipo-Aparelho: rotulo`, lido do código-fonte da Edge Function — `porcao_descricao`/`calorias_kcal`/`proteinas_g`/`carboidratos_g`/`gorduras_g`/`ingredientes_principais`), 4 `TextFormField`s pré-preenchidos e editáveis (o usuário pode corrigir um número que a IA leu errado — "validar os dados antes de gravar no banco"), aviso visual quando o backend sinaliza possível foto de tela, chips com os ingredientes principais.

**"Gravar no banco" — achado real**: antes desta tarefa, rótulo nunca persistia nada (o botão "Confirmar" só fechava a tela, `_capturarEExibir` trata retorno nulo como "nada a mostrar"). `ColetaDiariaRepository` ganhou `gravarLeituraRotulo()`, mesmo padrão exato de `gravarLeituraAparelho` (uma linha em `coleta_diaria`, `atributo: 'rotulo_nutricional'`, `valor_jsonb` = payload já revisado pelo usuário) — sem tabela nova, reaproveitando a infraestrutura EAV já existente e testada.

## Item 2 — SSOT: peso/altura deixam de ser atributo de perfil

### Migration (`20260916120000_motor_v1_ssot_peso_altura_anamnese.sql`)

1. **Aditivo**: `anamneses` ganha `peso_kg`, `altura_cm`, `peso_data_medicao`, `peso_origem` — cada preenchimento de anamnese agora é o snapshot oficial de peso/altura daquele momento (nunca sobrescrito, mesmo princípio de `anamneses_trg_versionar`).
2. **Destrutivo, no mesmo arquivo/transação**: `perfis_usuarios` perde `peso_kg`/`altura_cm`.
3. **Correção do consumidor legado**: `calcular_motor_metabolico` (3 consumidores reais em produção: `validar_e_salvar_meta`, Flutter, Painel Web) lia `altura_cm` direto de `perfis_usuarios` — corrigido para ler da última anamnese com o campo preenchido, **contrato de saída (nomes de campo do jsonb) 100% preservado**. `peso_kg` desse RPC já vinha de `metricas_saude_diarias`, não precisou mudar.

**Verificado ao vivo contra o banco real** (atleta1000@teste.com, autenticado de verdade via magic link): `select peso_kg, altura_cm from perfis_usuarios` devolve 400 (coluna não existe, confirmando o DROP); `calcular_motor_metabolico` continua respondendo sem quebrar (usou Katch-McArdle, que nem precisa de altura, nesse teste específico). Dados de teste limpos ao final.

### Refatoração Flutter (varredura completa — 8 arquivos que liam/escreviam `perfis_usuarios.peso_kg`/`altura_cm` identificados e corrigidos)

- **`AnamneseRepository.salvarAnamnese`**: peso/altura confirmados na Anamnese agora vão DIRETO na própria linha de `anamneses` (não mais upsert em `perfis_usuarios` + `metricas_saude_diarias`, que era o design da tarefa anterior — 20260915_0003 — antes desta arquitetura SSOT existir). `buscarDadosFisicosAtuais` (pré-preenchimento do formulário) passa a ler altura/peso da última anamnese com os dois campos preenchidos, não mais de `perfis_usuarios`/`metricas_saude_diarias`.
- **`PerfilUsuarioRepository`**: `buscarAlturaCm`/`atualizarAlturaCm` removidos (coluna não existe mais); novo `buscarAlturaCmDaUltimaAnamnese()` (somente leitura — a única forma de mudar a altura agora é preencher uma Anamnese).
- **`PerfilUsuarioPage`** ("Meus Dados Físicos"): a altura deixou de ser um campo editável — vira texto somente-leitura ("179 cm" ou uma dica pra preencher uma Anamnese). Data de nascimento/sexo biológico continuam editáveis ali (não fizeram parte do pedido de remoção).
- **`HealthSyncService._buscarAlturaMetros`** (inferência de IMC durante sync de wearable): trocado de `perfis_usuarios.altura_cm` para a última anamnese com altura preenchida.
- **`CadastroController._persistirPerfil`**: parou de gravar `peso_kg` em `perfis_usuarios` (o campo continua sendo perguntado na Etapa 1 do cadastro — fora do escopo desta tarefa remover a pergunta — mas agora só vai para `auth.users.user_metadata`, um JSONB livre não afetado pela remoção da coluna; nunca mais é a fonte oficial do Motor).
- **`web_painel/src/core/types/database.ts`**: tipos `altura_cm`/`peso_kg` removidos do `Row` de `perfis_usuarios` (limpeza de tipo — confirmado que nenhum componente do Painel Web lê essas colunas diretamente; `MotorMetabolicoCard.tsx`/`InserirMedicaoModal.tsx` só consomem via RPC/`metricas_saude_diarias`, ambos preservados).

**Achado honesto, não escondido**: a tarefa citava "ex: cálculo de água no Dashboard" como exemplo de consumidor de peso/altura a corrigir. Auditoria completa (grep por padrões de cálculo de meta de hidratação por peso) não encontrou nenhum cálculo desse tipo em lugar nenhum do app — a tela de hidratação (`registro_hidratacao_page.dart`) usa um tamanho de copo configurável (ml), não uma meta calculada a partir do peso. Não inventado nem "corrigido" algo que não existe (Regra 26); o consumidor real de altura+peso identificado e corrigido foi o cálculo de IMC (`perfil_usuario_page.dart`/`HealthSyncService`).

## Item 3 — Motor Metabólico Centralizado V1

Nova RPC `calcular_motor_metabolico_v1(p_usuario_id uuid)`, aditiva (não substitui a legada), implementando `docs/motor_metabolico.txt` à risca:

- **TMB-001 (Mifflin-St Jeor)** como única fórmula da V1 (o pedido explícito da tarefa) — peso/altura vêm da última anamnese válida (SSOT).
- **TDEE por dia da semana**, Decomposição ou PAL conforme dado disponível, **nunca as duas somadas no mesmo dia** (regra explícita do documento, "evitando dupla contagem"): dias com `anamneses_atividades_dias` usam `TMB + EAT + TEF`; dias sem atividade estruturada usam `TMB × PAL` (PAL padrão 1.2, parâmetro versionado `PAL-001-sedentario-v1`).
- **Gap documentado no próprio código, não escondido**: o documento pede NEAT separado do EAT, com prioridade "smartwatch > passos > atividades manuais > rotina ocupacional informada". Este app não coleta o campo "Rotina diária" (sedentário/pouco ativo/.../trabalho intenso) que o próprio documento define como fonte do NEAT — logo NEAT nunca é estimável individualmente hoje. Seguindo a regra do próprio documento ("quando não houver dados suficientes para estimar o NEAT... não deverá inventar... deverá utilizar o PAL"), a Decomposição desta V1 é `TMB + EAT + TEF` (sem termo de NEAT inventado) — registrado como backlog explícito.
- **Registra fórmula/versão/parâmetros/estratégia** no próprio JSON de saída: `motor_versao`, `formula_tmb` (código/nome/versão), `estrategia_tdee`, `parametros` (PAL usado + versão, percentual de TEF), `tdee_por_dia` (com a estratégia de CADA dia individualmente), `tdee_medio`, `insumos` (incluindo `anamnese_id` de onde veio o dado), `avisos`, `calculado_em`.
- **APENAS calcula e retorna (ME-005/ME-006)**: nenhum `insert`/`update`/`delete` na função — não chama `validar_e_salvar_meta` nem `gerar_sugestao_meta`, não escreve em `objetivos_alimentares`/`sugestao_meta`/`anamneses`. Ainda não consumida por nenhuma tela Flutter/Web (entrega desta tarefa é 100% backend, conforme ARQUIVOS/TAREFA item 3 — "backend puro").

**Verificado ao vivo, matemática conferida manualmente** (atleta1000@teste.com): anamnese de teste com peso=80kg, altura=178cm, idade real (51 anos, calculada de `data_nascimento`), 1 atividade (Corrida MET 8.0, 45min, segunda-feira). TMB = 10×80 + 6.25×178 − 5×51 + 5 = **1662.5** ✓ (bate exato). Segunda-feira (decomposição): EAT = 8.0×80×0.75 = 480; TDEE = 1662.5+480+166.25 = **2308.75** → arredondado 2308.8 ✓. Demais 6 dias (PAL): 1662.5×1.2 = **1995.0** ✓ (todos batem). TDEE médio = (2308.75 + 6×1995)/7 = **2039.8** ✓. **1 bug de precisão achado e corrigido no caminho**: a 1ª versão arredondava o TEF pra 1 casa decimal ANTES de somá-lo no TDEE do dia, introduzindo um desvio de ~0.05 kcal — corrigido pra arredondar só na saída (`tef_estimado`), nunca nos valores intermediários usados em soma. Dados de teste limpos do banco ao final (confirmado: 0 anamneses/atividades residuais para o usuário de teste).

## Verificação

- `flutter analyze` — limpo nos arquivos tocados; os 30 avisos do projeto inteiro são todos pré-existentes.
- `flutter test` — **468/468**, zero regressão. Testes atualizados/reescritos: `perfil_usuario_repository_test.dart`, `perfil_usuario_page_test.dart`, `health_sync_service_test.dart` (3 testes de inferência de IMC), `anamnese_repository_test.dart` (3 testes de peso/altura/sexo), `confirmacao_prato_controller_test.dart`/`confirmacao_prato_page_test.dart` (fake manual de `ColetaDiariaRepository` precisou do novo método `gravarLeituraRotulo`).
- `deno check`/`deno test` — não aplicável: nenhum arquivo de Edge Function tocado nesta tarefa (só lido `extract-metric-photo/index.ts` pra confirmar o contrato JSON do rótulo).

## ACEITE (conferido item a item)

- ✅ Câmera ajustada (+10px nos botões).
- ✅ Rótulo legível sem JSON (card nutricional editável).
- ✅ `perfis_usuarios` não tem mais `peso_kg`/`altura_cm` (confirmado com uma consulta real ao banco, 400 esperado).
- ✅ RPC `calcular_motor_metabolico_v1` calcula exatamente o que o documento pede (TMB-001, TDEE por dia via PAL/Decomposição, sem dupla contagem) e nunca sobrescreve tabela de meta nenhuma (nenhum `insert`/`update`/`delete` na função, matematicamente verificado + lido o corpo inteiro da função).

## Entregável

- Migration `supabase/migrations/20260916120000_motor_v1_ssot_peso_altura_anamnese.sql` (já aplicada e testada contra o banco remoto real).
- Código Flutter refatorado (8 arquivos + 1 modelo novo) e Painel Web (1 arquivo de tipos).
- Branch `feat/motor-v1-backend-ui`, a partir de `feat/app-anamnese-metas` (dependência real — este trabalho modifica a captura de peso/altura entregue lá), **não mesclada** (Regra 18).
