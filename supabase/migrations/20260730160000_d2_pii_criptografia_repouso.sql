-- D2 (Documento Mestre §9.1/§11.1, Parte 6) — Criptografia de PII EM REPOUSO,
-- server-side, ANTES de qualquer dado real. Move a responsabilidade de cifrar
-- `perfis_usuarios.nome/telefone/email` do CLIENTE (AES-256-GCM com chave presa
-- ao Keystore/Keychain do aparelho — CryptoStorageService) para o BANCO
-- (pgcrypto + chave no Supabase Vault), de forma transparente para os clientes.
--
-- POR QUE ISSO É UMA CORREÇÃO, não só uma migração de camada:
-- A cifra client-side era, na prática, WRITE-ONLY e device-bound. A chave nunca
-- saía do aparelho, então:
--   - o painel B2B nunca conseguiu ler o `nome` de um paciente (ciphertext
--     indecifrável) — por isso as telas de paciente giram em torno do UUID;
--   - um `nome` gravado no aparelho A jamais poderia ser lido no aparelho B;
--   - `perfis_usuarios.email` era inútil para busca (por isso o convite B2B
--     resolve e-mail->UUID por `auth.users`, ver resolver_usuario_id_por_email).
-- Pior: o painel do PROFISSIONAL grava `nome`/`email` em TEXTO PLANO (ver
-- web_painel/src/core/supabase.ts), então hoje a coluna é uma MISTURA de
-- ciphertext-de-aparelho (pacientes) e texto plano (profissionais). D2 unifica:
-- tudo passa a ser cifrado no banco, decifrável só pelo dono (via RPC) — e, no
-- futuro, por um profissional com vínculo ativo (infra pronta, ver nota final).
--
-- ESTRATÉGIA CRIPTOGRÁFICA (detalhada no RELATÓRIO):
--   - pgcrypto `pgp_sym_encrypt` (AES-256) + `armor()` -> as colunas seguem
--     sendo `text` (o painel/app não mudam de tipo), guardando um bloco
--     "-----BEGIN PGP MESSAGE-----..." ilegível para quem abrir o Studio.
--   - A chave simétrica de 256 bits é GERADA aleatoriamente aqui (nunca
--     hardcoded) e guardada no Supabase Vault (`vault.secrets`), cifrada em
--     repouso pela chave-raiz do Vault que vive FORA do schema, inacessível a
--     `authenticated`/`anon`. Só funções SECURITY DEFINER (donas = postgres)
--     leem `vault.decrypted_secrets`.
--   - Escrita: um TRIGGER `before insert/update` cifra transparentemente — todo
--     writer existente (app mobile, painel web, seed) continua enviando texto
--     plano; o banco cifra. Zero mudança na ESTRUTURA de escrita dos clientes.
--   - Leitura: RPC `meu_perfil_seguro()` (SECURITY DEFINER, escopada a
--     `auth.uid()`) decifra só a PRÓPRIA linha. A tabela-base só devolve
--     ciphertext; ninguém decifra PII de outro usuário por ela.

-- ============================================================================
-- 0. Pré-requisitos (idempotentes). Se o Vault não existir neste projeto, o
--    `create extension` abaixo falha e a migração INTEIRA reverte (roda em
--    transação) — nenhum dado é tocado num ambiente sem as extensões certas.
-- ============================================================================
create extension if not exists pgcrypto with schema extensions;
create extension if not exists supabase_vault with schema vault;

create schema if not exists private;

-- ============================================================================
-- 1. Chave no Vault — aleatória, gerada no banco, nunca no código-fonte.
--    Guardada só se ainda não existir (migração re-executável sem duplicar).
-- ============================================================================
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'pii_encryption_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'base64'),
      'pii_encryption_key',
      'D2: chave simétrica AES-256 para cifrar PII de perfis_usuarios (nome/telefone/email) em repouso.'
    );
  end if;
end;
$$;

-- ============================================================================
-- 2. Funções de cifra/decifra — SECURITY DEFINER, leem a chave do Vault.
--    `search_path=''` fecha o sequestro clássico de search_path em SECURITY
--    DEFINER (mesmo padrão de resolver_usuario_id_por_email).
--    NUNCA concedidas a authenticated/anon: só o trigger e a RPC (também
--    definer) as usam, por dentro.
-- ============================================================================
create or replace function private.pii_encrypt(p_plaintext text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  if p_plaintext is null then
    return null;
  end if;
  select decrypted_secret into v_key
    from vault.decrypted_secrets
    where name = 'pii_encryption_key'
    limit 1;
  if v_key is null then
    raise exception 'D2: chave pii_encryption_key ausente no Vault';
  end if;
  -- armor() -> texto ASCII "-----BEGIN PGP MESSAGE-----", cabe numa coluna text.
  return extensions.armor(
    extensions.pgp_sym_encrypt(p_plaintext, v_key, 'cipher-algo=aes256')
  );
end;
$$;

create or replace function private.pii_decrypt(p_ciphertext text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  if p_ciphertext is null or p_ciphertext = '' then
    return null;
  end if;
  -- Valor que não é um bloco PGP armado (ex.: linha legada em texto plano que
  -- o trigger ainda não reescreveu) volta como veio — nunca derruba a leitura.
  if left(p_ciphertext, 27) <> '-----BEGIN PGP MESSAGE-----' then
    return p_ciphertext;
  end if;
  select decrypted_secret into v_key
    from vault.decrypted_secrets
    where name = 'pii_encryption_key'
    limit 1;
  if v_key is null then
    raise exception 'D2: chave pii_encryption_key ausente no Vault';
  end if;
  return extensions.pgp_sym_decrypt(extensions.dearmor(p_ciphertext), v_key);
exception
  when others then
    -- Decifra que falha (chave trocada, bloco corrompido) nunca vaza erro nem
    -- ciphertext para a tela — devolve nulo (mesma filosofia "falha segura" do
    -- decryptSensitiveField que este mecanismo substitui).
    return null;
end;
$$;

revoke execute on function private.pii_encrypt(text) from public;
revoke execute on function private.pii_decrypt(text) from public;

-- ============================================================================
-- 3. Autoteste de ida-e-volta ANTES de tocar em qualquer dado. Se a cifra não
--    fizer round-trip (extensão/Vault mal configurados), aborta a transação
--    inteira aqui — o UPDATE destrutivo do passo 5 nunca chega a rodar.
-- ============================================================================
do $$
declare
  v_original text := 'D2 self-test — Maria da Silva / (11) 90000-0000';
  v_cipher text;
  v_back text;
begin
  v_cipher := private.pii_encrypt(v_original);
  if v_cipher is null or left(v_cipher, 27) <> '-----BEGIN PGP MESSAGE-----' then
    raise exception 'D2 self-test FALHOU: cifra não produziu bloco PGP armado';
  end if;
  if position(v_original in v_cipher) > 0 then
    raise exception 'D2 self-test FALHOU: plaintext vazou dentro do ciphertext';
  end if;
  v_back := private.pii_decrypt(v_cipher);
  if v_back is distinct from v_original then
    raise exception 'D2 self-test FALHOU: round-trip não bateu (% != %)', v_back, v_original;
  end if;
end;
$$;

-- ============================================================================
-- 4. Trigger de cifra transparente na escrita. Todo INSERT/UPDATE em
--    perfis_usuarios passa por aqui: o cliente manda texto plano, o banco cifra.
--    - INSERT: cifra todo campo PII não-nulo.
--    - UPDATE: cifra só o que MUDOU (NEW distinto de OLD) — assim um update que
--      não mexe no nome não re-cifra o ciphertext já guardado (evita
--      dupla-cifra), e um valor omitido no PATCH (NEW=OLD) é preservado.
-- ============================================================================
create or replace function private.tg_perfis_usuarios_cifrar_pii()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.nome     := private.pii_encrypt(new.nome);
    new.telefone := private.pii_encrypt(new.telefone);
    new.email    := private.pii_encrypt(new.email);
  else -- UPDATE
    if new.nome is distinct from old.nome then
      new.nome := private.pii_encrypt(new.nome);
    end if;
    if new.telefone is distinct from old.telefone then
      new.telefone := private.pii_encrypt(new.telefone);
    end if;
    if new.email is distinct from old.email then
      new.email := private.pii_encrypt(new.email);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_perfis_usuarios_cifrar_pii on perfis_usuarios;
create trigger trg_perfis_usuarios_cifrar_pii
  before insert or update on perfis_usuarios
  for each row
  execute function private.tg_perfis_usuarios_cifrar_pii();

-- ============================================================================
-- 5. Dados legados (SÓ CONTAS DE TESTE — D2 acontece "antes de qualquer dado
--    real", §9.1). Os valores atuais de nome/telefone/email são INSERVÍVEIS:
--    ou são ciphertext AES preso a um Keystore de aparelho (pacientes, jamais
--    decifrável no servidor), ou texto plano solto (profissionais). Não há como
--    convertê-los de forma consistente e honesta, então são ZERADOS — as contas
--    fake podem ser recriadas. NÃO é um TRUNCATE da tabela: preserva id,
--    nickname, is_admin, eh_profissional, vínculos, status. Só os 3 campos PII
--    saem. O trigger cifra corretamente todo cadastro NOVO daqui pra frente.
-- ============================================================================
update perfis_usuarios
  set nome = null, telefone = null, email = null
  where nome is not null or telefone is not null or email is not null;

-- ============================================================================
-- 6. Caminho de LEITURA do dono — RPC que decifra SÓ a própria linha.
--    Substitui o `select nome from perfis_usuarios` direto que o painel web
--    fazia (que agora só devolveria ciphertext). Escopada a auth.uid(): um
--    usuário jamais decifra a PII de outro por aqui. A tabela-base continua
--    legível (ciphertext) para os campos NÃO-PII que o app já lê direto.
-- ============================================================================
create or replace function public.meu_perfil_seguro()
returns table (
  id uuid,
  nome text,
  telefone text,
  email text,
  nickname text,
  eh_profissional boolean,
  tipo_profissional public.tipo_profissional_saude,
  status_aprovacao public.status_aprovacao_usuario,
  is_admin boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  select
    p.id,
    private.pii_decrypt(p.nome)     as nome,
    private.pii_decrypt(p.telefone) as telefone,
    private.pii_decrypt(p.email)    as email,
    p.nickname,
    p.eh_profissional,
    p.tipo_profissional,
    p.status_aprovacao,
    p.is_admin
  from public.perfis_usuarios p
  where p.id = auth.uid();
end;
$$;

revoke execute on function public.meu_perfil_seguro() from public;
grant execute on function public.meu_perfil_seguro() to authenticated;

-- GRANT explícito da tabela mantido (Parte 0.10) — inalterado, reafirmado aqui
-- para o registro: a base segue legível/gravável pelo dono (RLS auth.uid()=id),
-- só que os 3 campos PII agora entram/saem cifrados via trigger/RPC.
grant select, insert, update on perfis_usuarios to authenticated;
