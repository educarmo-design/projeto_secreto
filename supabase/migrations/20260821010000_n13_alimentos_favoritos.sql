-- N13 (Documento Mestre v7.0, Parte V1.H) — Favoritas de alimentos/pratos:
-- "Favoritas por tipo (café/almoço/jantar/lanche), múltiplas; marcar como
-- favorita ao registrar; manutenção no perfil (excluir/trocar tipo).
-- Favorita salva COM a medida customizada e volta pronta."
--
-- `payload_jsonb` guarda o MESMO formato que `coleta_diaria.valor_jsonb`
-- já usa pra `atributo='refeicao'` (itens + totais, ver
-- ConfirmacaoPratoController.payloadRevisado()) — reusar uma favorita é só
-- pegar esse JSON de volta e mandar pro mesmo gravador
-- (ColetaDiariaRepository.gravarRefeicao), sem recalcular nada: "volta
-- pronta" da spec, literalmente.

create table alimentos_favoritos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users (id) on delete cascade,

  -- Texto livre (não enum), mesmo raciocínio de coleta_diaria.atributo —
  -- só 4 valores reais na v1.0, mas CHECK em vez de enum Postgres pra não
  -- precisar de migration nova se a lista crescer.
  tipo_refeicao text not null
    check (tipo_refeicao in ('cafe_da_manha', 'almoco', 'lanche', 'jantar')),

  -- Nome dado pelo usuário ao salvar (ex.: "Meu almoço de segunda") — nunca
  -- inferido automaticamente do primeiro item, pra não travar num rótulo
  -- ruim quando o prato tem vários itens.
  nome text not null,

  payload_jsonb jsonb not null,

  criado_em timestamptz not null default now()
);

comment on table alimentos_favoritos is
  'N13 — refeições salvas como favoritas pelo usuário, pra reaproveitar sem repetir foto/digitação. payload_jsonb é o mesmo formato de coleta_diaria.valor_jsonb (atributo=refeicao).';
comment on column alimentos_favoritos.payload_jsonb is
  'Cópia exata do payload que ConfirmacaoPratoController.payloadRevisado() já produz (itens + totais) — usar a favorita é reenviar isto pra ColetaDiariaRepository.gravarRefeicao sem recalcular.';

create index idx_alimentos_favoritos_usuario_tipo
  on alimentos_favoritos (usuario_id, tipo_refeicao, criado_em desc);

alter table alimentos_favoritos enable row level security;

create policy "alimentos_favoritos_select_own"
  on alimentos_favoritos for select
  using (auth.uid() = usuario_id);

create policy "alimentos_favoritos_insert_own"
  on alimentos_favoritos for insert
  with check (auth.uid() = usuario_id);

create policy "alimentos_favoritos_update_own"
  on alimentos_favoritos for update
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

create policy "alimentos_favoritos_delete_own"
  on alimentos_favoritos for delete
  using (auth.uid() = usuario_id);

grant select, insert, update, delete on alimentos_favoritos to authenticated;
