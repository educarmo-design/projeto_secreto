-- anonymous_users: profile_data JSONB storage backing the app's profile-aware
-- routing (perfil_uso). Referenced by lib/core/router/app_router.dart and
-- lib/core/supabase/supabase_client.dart but missing from the initial core
-- schema migration, which only added the flat-column perfis_usuarios table.
-- ============================================================================

create table anonymous_users (
  id uuid primary key references auth.users (id) on delete cascade,
  profile_data jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);

alter table anonymous_users enable row level security;

create policy "anonymous_users_select_own"
  on anonymous_users for select
  using (auth.uid() = id);

create policy "anonymous_users_insert_own"
  on anonymous_users for insert
  with check (auth.uid() = id);

create policy "anonymous_users_update_own"
  on anonymous_users for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Required for ProfileRefreshListenable's postgres_changes subscription in
-- app_router.dart to receive perfil_uso updates in real time.
alter publication supabase_realtime add table anonymous_users;
