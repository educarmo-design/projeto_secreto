-- RELATÓRIO 20260825_0003 — pedido do fundador: investigação completa de
-- outras atividades que possam sofrer o mesmo bug do treino de força
-- (RELATÓRIO 20260820_0002 — código nativo do Android/iOS ausente do
-- dicionário rejeita a FK de `atividades_fisicas_treinos.tipo_atividade_
-- codigo`, silenciosamente engolido pelo `catch` best-effort do loop de
-- sincronização) + cadastro completo do catálogo.
--
-- Investigação: `HealthWorkoutActivityType` (pacote `health` 13.3.1,
-- lib/src/heath_data_types.dart) tem 3 seções — "Both" (43, já semeadas em
-- 20260811160000, inclui BIKING), "iOS only" (35) e "Android only" (20) —
-- mais o valor catch-all `OTHER`, fora de qualquer seção = 99 códigos no
-- total (contagem exata, não estimativa — enumerado programaticamente
-- linha a linha do enum de verdade). Só 47 estavam cadastrados (as 43
-- "Both" + os 4 de força de 20260820100000) — 52 códigos
-- plataforma-específicos ficavam de fora (33 iOS-only + 18 Android-only +
-- OTHER), cada um deles capaz de reproduzir exatamente o mesmo bug
-- silencioso assim que o usuário certo registrasse aquele treino
-- específico no wearable certo. Esta migration fecha essa lacuna inteira
-- de uma vez.
--
-- Por que isto e não uma camada de tradução no código: `nome_codigo`
-- espelha `HealthWorkoutActivityType.name` 1:1, por desenho, desde
-- 20260811160000 ("sem camada de tradução no meio") — o dicionário É a
-- allowlist da FK. Resolver "não pode ser hardcode" nesta arquitetura
-- significa cadastrar os códigos que faltam AQUI (configurável, editável
-- pelo Admin em runtime via `AdminAtividadesFisicas.tsx`), não escrever um
-- `switch` de normalização no Dart.
--
-- Achado bônus (documentado, não uma ação de código): o pacote já resolve
-- sozinho o par BIKING(Android)/"cycling"(iOS) — emite o mesmo código
-- `BIKING` nas duas plataformas (comentário no enum: "This also entails
-- the iOS version where it is called CYCLING") — não existe uma entrada
-- `CYCLING` separada, então não há nada a cadastrar aqui. Já os outros 2
-- pares comentados no próprio enum como "a mesma coisa" SÃO códigos
-- distintos de verdade (ROCK_CLIMBING Android / CLIMBING iOS,
-- RUNNING_TREADMILL Android / RUNNING iOS-mas-RUNNING-já-existe) — cada um
-- precisa da própria linha (a FK é por código exato), e por isso ganham o
-- MESMO `nome_exibicao` entre si abaixo, só pra deixar visível no Admin
-- que são a mesma atividade do ponto de vista do usuário.

-- =============================================================================
-- 1) Metadado de plataforma — não influencia a FK/sincronização (que
-- continua sendo só por `nome_codigo`), é só documentação estruturada pra
-- nunca mais depender de "alguém lembrar de conferir o enum inteiro" —
-- uma consulta cobre a pergunta "que códigos daquela plataforma faltam?"
-- de novo, se o pacote `health` ganhar mais tipos no futuro.
-- =============================================================================
alter table tipos_atividades_fisicas
  add column if not exists plataforma text
    not null default 'ambas'
    check (plataforma in ('ambas', 'android', 'ios'));

comment on column tipos_atividades_fisicas.plataforma is
  'Em qual seção do enum HealthWorkoutActivityType o código vive (Both/iOS only/Android only) — só documentação, a FK de atividades_fisicas_treinos usa nome_codigo, não esta coluna. RELATÓRIO 20260825_0003.';

update tipos_atividades_fisicas set plataforma = 'android'
  where nome_codigo in ('STRENGTH_TRAINING', 'WEIGHTLIFTING');

update tipos_atividades_fisicas set plataforma = 'ios'
  where nome_codigo in ('FUNCTIONAL_STRENGTH_TRAINING', 'TRADITIONAL_STRENGTH_TRAINING');

-- =============================================================================
-- 2) iOS only (33 códigos faltantes — os outros 2 da seção, FUNCTIONAL_
-- STRENGTH_TRAINING/TRADITIONAL_STRENGTH_TRAINING, já entraram em
-- 20260820100000)
-- =============================================================================
insert into tipos_atividades_fisicas (nome_codigo, nome_exibicao, plataforma) values
  ('BARRE', 'Barre', 'ios'),
  ('BOWLING', 'Boliche', 'ios'),
  ('CLIMBING', 'Escalada', 'ios'),
  ('COOLDOWN', 'Volta à Calma', 'ios'),
  ('CORE_TRAINING', 'Treino de Core', 'ios'),
  ('CROSS_TRAINING', 'Treino Cruzado (Cross Training)', 'ios'),
  ('DISC_SPORTS', 'Frisbee / Esportes com Disco', 'ios'),
  ('EQUESTRIAN_SPORTS', 'Hipismo / Esportes Equestres', 'ios'),
  ('FISHING', 'Pesca', 'ios'),
  ('FITNESS_GAMING', 'Fitness Gaming (Jogos Ativos)', 'ios'),
  ('FLEXIBILITY', 'Flexibilidade / Alongamento', 'ios'),
  ('HAND_CYCLING', 'Ciclismo Adaptado (Handbike)', 'ios'),
  ('HUNTING', 'Caça', 'ios'),
  ('LACROSSE', 'Lacrosse', 'ios'),
  ('MIND_AND_BODY', 'Mente e Corpo', 'ios'),
  ('MIXED_CARDIO', 'Cardio Misto', 'ios'),
  ('PADDLE_SPORTS', 'Esportes de Remo / Paddle', 'ios'),
  ('PICKLEBALL', 'Pickleball', 'ios'),
  ('PLAY', 'Brincadeira Ativa', 'ios'),
  ('PREPARATION_AND_RECOVERY', 'Preparação e Recuperação', 'ios'),
  ('SNOW_SPORTS', 'Esportes na Neve', 'ios'),
  ('SOCIAL_DANCE', 'Dança Social', 'ios'),
  ('STAIRS', 'Escadas', 'ios'),
  ('STEP_TRAINING', 'Step', 'ios'),
  ('SURFING', 'Surfe', 'ios'),
  ('TAI_CHI', 'Tai Chi', 'ios'),
  ('TRACK_AND_FIELD', 'Atletismo', 'ios'),
  ('WATER_FITNESS', 'Hidroginástica', 'ios'),
  ('WATER_SPORTS', 'Esportes Aquáticos', 'ios'),
  ('WHEELCHAIR_RUN_PACE', 'Corrida em Cadeira de Rodas', 'ios'),
  ('WHEELCHAIR_WALK_PACE', 'Caminhada em Cadeira de Rodas', 'ios'),
  ('WRESTLING', 'Luta Livre', 'ios'),
  ('UNDERWATER_DIVING', 'Mergulho', 'ios')
on conflict (nome_codigo) do nothing;

-- =============================================================================
-- 3) Android only (18 códigos faltantes — os outros 2 da seção,
-- STRENGTH_TRAINING/WEIGHTLIFTING, já entraram em 20260820100000)
-- =============================================================================
insert into tipos_atividades_fisicas (nome_codigo, nome_exibicao, plataforma) values
  ('BIKING_STATIONARY', 'Bicicleta Ergométrica', 'android'),
  ('CALISTHENICS', 'Calistenia', 'android'),
  ('DANCING', 'Dança', 'android'),
  ('FRISBEE_DISC', 'Frisbee / Esportes com Disco', 'android'),
  ('GUIDED_BREATHING', 'Respiração Guiada', 'android'),
  ('ICE_SKATING', 'Patinação no Gelo', 'android'),
  ('PARAGLIDING', 'Parapente', 'android'),
  -- Mesmo nome de exibição de CLIMBING (iOS) — comentário do próprio enum:
  -- "on iOS this is the same as CLIMBING".
  ('ROCK_CLIMBING', 'Escalada', 'android'),
  ('ROWING_MACHINE', 'Remo Ergométrico', 'android'),
  -- Mesma observação: "on iOS this is the same as RUNNING" — RUNNING já é
  -- "Corrida" (seção Both); esteira ganha o sufixo pra diferenciar.
  ('RUNNING_TREADMILL', 'Corrida (Esteira)', 'android'),
  ('SCUBA_DIVING', 'Mergulho com Cilindro (Scuba)', 'android'),
  ('SKIING', 'Esqui', 'android'),
  ('SNOWSHOEING', 'Caminhada com Raquete de Neve', 'android'),
  ('STAIR_CLIMBING_MACHINE', 'Subida de Escadas (Máquina)', 'android'),
  ('SWIMMING_OPEN_WATER', 'Natação em Águas Abertas', 'android'),
  ('SWIMMING_POOL', 'Natação em Piscina', 'android'),
  ('WALKING_TREADMILL', 'Caminhada (Esteira)', 'android'),
  ('WHEELCHAIR', 'Cadeira de Rodas', 'android')
on conflict (nome_codigo) do nothing;

-- =============================================================================
-- 4) OTHER — catch-all fora de qualquer seção do enum, comum às duas
-- plataformas (o pacote emite isto quando o SO reporta um tipo que a lib
-- ainda não mapeou por nome).
-- =============================================================================
insert into tipos_atividades_fisicas (nome_codigo, nome_exibicao, plataforma) values
  ('OTHER', 'Outro', 'ambas')
on conflict (nome_codigo) do nothing;
