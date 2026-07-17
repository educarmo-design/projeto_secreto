/**
 * Seed de demonstração — Painel B2B (Supabase Cloud / hospedado).
 *
 * Contraparte de `supabase/seed.sql` para o projeto Supabase HOSPEDADO: o
 * `seed.sql` só roda via `supabase db reset`/`db start` LOCAL, porque insere
 * direto em `auth.users` — algo que o Postgres do Supabase Cloud rejeita com
 * `42501 must be owner of table users` (a tabela pertence ao role
 * `supabase_auth_admin`; o role `postgres` do SQL Editor não tem privilégio
 * de escrita nela, com ou sem TRUNCATE). A única forma suportada de criar
 * usuários de autenticação no Cloud é a Admin API do GoTrue
 * (`auth.admin.createUser`), por isso este script existe em separado.
 *
 * Cria os mesmos 10 pacientes fictícios do `seed.sql` (mesmos e-mails/dados,
 * mas com UUIDs gerados pelo Supabase Auth — a Admin API não aceita forçar
 * um `id` específico como o INSERT bruto local faz), vinculados ao
 * profissional cadastrado com o e-mail `educarmo@gmail.com`, com 6 meses de
 * métricas diárias — para validar Sidebar/DashboardLayout, "Meus
 * Pacientes/Alunos" e os gráficos de `PatientDetails`.
 *
 * Como rodar:
 *   1. cd web_painel
 *   2. Copie `VITE_SUPABASE_URL` de `.env`/`.env.example` e adicione, no
 *      mesmo `.env` (já ignorado pelo git), a variável
 *      `SUPABASE_SERVICE_ROLE_KEY=<service_role key do projeto>` — pegue-a
 *      em Project Settings > API no painel do Supabase. NUNCA coloque essa
 *      chave em `VITE_...` (isso a exporia no bundle do navegador) nem a
 *      commite.
 *   3. npm run seed:cloud
 *
 * Idempotente: reexecutar não duplica nada — verifica por e-mail antes de
 * criar cada `auth.users`, usa `upsert` nas tabelas com constraint única
 * (`perfis_usuarios`, `metricas_saude_diarias`, `progresso_gamificacao`) e
 * um `delete` prévio tagueado por `tipo_plano = 'seed_demo_baseline'` antes
 * do insert em `planejamento_clinico` (mesma tag do `seed.sql`).
 * `vinculos_profissional_paciente` tem um índice único parcial
 * (`where status <> 'encerrado'`), que o `upsert` do PostgREST não consegue
 * mirar (Postgres exige o mesmo predicado no ON CONFLICT de um índice
 * parcial) — por isso aqui é select-then-insert/update manual em vez de
 * upsert, ao contrário do `seed.sql`.
 */
import 'dotenv/config';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const PROFISSIONAL_EMAIL = 'educarmo@gmail.com';
const TAG_PLANO = 'seed_demo_baseline';
const DIAS_HISTORICO = 182;
const SEED_PATIENT_PASSWORD = 'SeedPaciente#2026';

interface PacienteSeed {
  idx: number;
  email: string;
  nomeDisplay: string;
  dataNascimento: string;
  sexoBiologico: 'feminino' | 'masculino';
  geoRankingId: string;
  pesoBaseKg: number;
}

const PACIENTES: PacienteSeed[] = [
  { idx: 1, email: 'ana.paula.ferreira@pacientes.seed.dev', nomeDisplay: 'Ana Paula Ferreira', dataNascimento: '1988-03-14', sexoBiologico: 'feminino', geoRankingId: 'SP', pesoBaseKg: 68.4 },
  { idx: 2, email: 'bruno.henrique.costa@pacientes.seed.dev', nomeDisplay: 'Bruno Henrique Costa', dataNascimento: '1975-11-02', sexoBiologico: 'masculino', geoRankingId: 'RJ', pesoBaseKg: 84.2 },
  { idx: 3, email: 'carla.souza.lima@pacientes.seed.dev', nomeDisplay: 'Carla Souza Lima', dataNascimento: '1992-07-21', sexoBiologico: 'feminino', geoRankingId: 'MG', pesoBaseKg: 61.9 },
  { idx: 4, email: 'diego.almeida.santos@pacientes.seed.dev', nomeDisplay: 'Diego Almeida Santos', dataNascimento: '1980-01-30', sexoBiologico: 'masculino', geoRankingId: 'RS', pesoBaseKg: 91.5 },
  { idx: 5, email: 'elisa.martins.rocha@pacientes.seed.dev', nomeDisplay: 'Elisa Martins Rocha', dataNascimento: '1998-09-09', sexoBiologico: 'feminino', geoRankingId: 'PR', pesoBaseKg: 58.7 },
  { idx: 6, email: 'felipe.oliveira.dias@pacientes.seed.dev', nomeDisplay: 'Felipe Oliveira Dias', dataNascimento: '1968-05-17', sexoBiologico: 'masculino', geoRankingId: 'BA', pesoBaseKg: 79.3 },
  { idx: 7, email: 'gabriela.pereira.nunes@pacientes.seed.dev', nomeDisplay: 'Gabriela Pereira Nunes', dataNascimento: '2001-12-05', sexoBiologico: 'feminino', geoRankingId: 'SC', pesoBaseKg: 55.2 },
  { idx: 8, email: 'henrique.barbosa.melo@pacientes.seed.dev', nomeDisplay: 'Henrique Barbosa Melo', dataNascimento: '1985-04-23', sexoBiologico: 'masculino', geoRankingId: 'PE', pesoBaseKg: 88.0 },
  { idx: 9, email: 'isabela.carvalho.moraes@pacientes.seed.dev', nomeDisplay: 'Isabela Carvalho Moraes', dataNascimento: '1990-08-11', sexoBiologico: 'feminino', geoRankingId: 'CE', pesoBaseKg: 64.6 },
  { idx: 10, email: 'joao.vitor.ribeiro@pacientes.seed.dev', nomeDisplay: 'João Vitor Ribeiro', dataNascimento: '1977-02-28', sexoBiologico: 'masculino', geoRankingId: 'DF', pesoBaseKg: 95.8 },
];

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Variável de ambiente ${name} não configurada — veja as instruções no topo de scripts/seed_cloud.ts.`);
  }
  return value;
}

/** `VITE_SUPABASE_URL` no .env deste repo já veio com `/rest/v1/` no final (usado assim pelo cliente do app); a Admin API precisa só da origem. */
function baseSupabaseUrl(): string {
  return new URL(requireEnv('VITE_SUPABASE_URL')).origin;
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

async function findUserIdByEmail(admin: SupabaseClient, email: string): Promise<string | null> {
  const perPage = 200;
  for (let page = 1; ; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
    if (error) throw new Error(`listUsers: ${error.message}`);
    const match = data.users.find((u) => u.email?.toLowerCase() === email.toLowerCase());
    if (match) return match.id;
    if (data.users.length < perPage) return null;
  }
}

async function ensurePacienteAuthUser(admin: SupabaseClient, paciente: PacienteSeed): Promise<string> {
  const existingId = await findUserIdByEmail(admin, paciente.email);
  if (existingId) return existingId;

  const { data, error } = await admin.auth.admin.createUser({
    email: paciente.email,
    password: SEED_PATIENT_PASSWORD,
    email_confirm: true,
    user_metadata: { nome_display: paciente.nomeDisplay, seed_demo: true },
  });
  if (error) throw new Error(`createUser(${paciente.email}): ${error.message}`);
  return data.user.id;
}

function gerarMetricasDiarias(pacienteId: string, idx: number, pesoBaseKg: number) {
  const hoje = new Date();
  hoje.setUTCHours(0, 0, 0, 0);
  const rows = [];
  for (let diasAtras = DIAS_HISTORICO; diasAtras >= 0; diasAtras -= 1) {
    const dia = new Date(hoje);
    dia.setUTCDate(dia.getUTCDate() - diasAtras);
    rows.push({
      usuario_id_anonimo: pacienteId,
      data_referencia: dia.toISOString().slice(0, 10),
      passos: Math.floor(4000 + Math.random() * 7000),
      distancia_metros: round2(2000 + Math.random() * 7000),
      fc_repouso: Math.floor(54 + (idx % 6) * 3 + (Math.random() * 8 - 4)),
      hrv_medio: round2(28 + Math.random() * 45),
      calorias_ativas: round2(220 + Math.random() * 480),
      minutos_sono: Math.floor(300 + Math.random() * 180),
      peso_kg: round2(pesoBaseKg - (diasAtras / DIAS_HISTORICO) * 3.2 + (Math.random() - 0.5) * 0.8),
      percentual_gordura: round2(16 + (idx % 5) * 2.5 + Math.random() * 3),
      pressao_sistolica: Math.floor(108 + Math.random() * 24),
      pressao_diastolica: Math.floor(66 + Math.random() * 18),
      glicose_jejum: round2(80 + (idx % 4) * 6 + Math.random() * 10),
      saturacao_oxigenio: round2(95.5 + Math.random() * 3.4),
      temperatura_corporal: round2(36.1 + Math.random() * 0.8),
      origem: 'seed_demo',
    });
  }
  return rows;
}

async function chunkedUpsert(
  admin: SupabaseClient,
  table: string,
  rows: Record<string, unknown>[],
  onConflict: string,
  chunkSize = 500,
) {
  for (let i = 0; i < rows.length; i += chunkSize) {
    const chunk = rows.slice(i, i + chunkSize);
    const { error } = await admin.from(table).upsert(chunk, { onConflict });
    if (error) throw new Error(`upsert ${table}: ${error.message}`);
  }
}

async function main() {
  const admin = createClient(baseSupabaseUrl(), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const profissionalId = await findUserIdByEmail(admin, PROFISSIONAL_EMAIL);
  if (!profissionalId) {
    throw new Error(
      `Nenhuma conta encontrada para ${PROFISSIONAL_EMAIL} em auth.users. Crie a conta (Solicitar Acesso no painel) e aprove-a antes de rodar este seed.`,
    );
  }
  console.log(`Profissional resolvido: ${PROFISSIONAL_EMAIL} -> ${profissionalId}`);

  for (const paciente of PACIENTES) {
    const pacienteId = await ensurePacienteAuthUser(admin, paciente);
    console.log(`[${paciente.idx}/${PACIENTES.length}] ${paciente.email} -> ${pacienteId}`);

    const { error: perfilError } = await admin.from('perfis_usuarios').upsert(
      {
        id: pacienteId,
        nickname: paciente.nomeDisplay,
        data_nascimento: paciente.dataNascimento,
        sexo_biologico: paciente.sexoBiologico,
        pais: 'BR',
        geo_ranking_id: paciente.geoRankingId,
        eh_profissional: false,
        tipo_profissional: null,
        status_aprovacao: 'aprovado',
        is_admin: false,
      },
      { onConflict: 'id' },
    );
    if (perfilError) throw new Error(`perfis_usuarios: ${perfilError.message}`);

    const dataInicio = new Date();
    dataInicio.setUTCDate(dataInicio.getUTCDate() - ((paciente.idx * 17) % 180));

    const { data: vinculoExistente, error: vinculoSelectError } = await admin
      .from('vinculos_profissional_paciente')
      .select('id')
      .eq('profissional_id', profissionalId)
      .eq('paciente_id', pacienteId)
      .neq('status', 'encerrado')
      .maybeSingle();
    if (vinculoSelectError) throw new Error(`vinculos_profissional_paciente (select): ${vinculoSelectError.message}`);

    if (vinculoExistente) {
      const { error: updateError } = await admin
        .from('vinculos_profissional_paciente')
        .update({ status: 'ativo', atualizado_em: new Date().toISOString() })
        .eq('id', vinculoExistente.id);
      if (updateError) throw new Error(`vinculos_profissional_paciente (update): ${updateError.message}`);
    } else {
      const { error: insertError } = await admin.from('vinculos_profissional_paciente').insert({
        profissional_id: profissionalId,
        paciente_id: pacienteId,
        status: 'ativo',
        tipo_pagador: 'profissional',
        tipo_produto: 'sem_garmin',
        data_inicio: dataInicio.toISOString().slice(0, 10),
      });
      if (insertError) throw new Error(`vinculos_profissional_paciente (insert): ${insertError.message}`);
    }

    const { error: deleteError } = await admin
      .from('planejamento_clinico')
      .delete()
      .eq('profissional_id', profissionalId)
      .eq('paciente_id_anonimo', pacienteId)
      .eq('tipo_plano', TAG_PLANO);
    if (deleteError) throw new Error(`planejamento_clinico (delete): ${deleteError.message}`);

    const criadoEm = new Date();
    criadoEm.setUTCDate(criadoEm.getUTCDate() - ((paciente.idx * 17) % 180));
    const { error: planoError } = await admin.from('planejamento_clinico').insert({
      profissional_id: profissionalId,
      paciente_id_anonimo: pacienteId,
      tipo_plano: TAG_PLANO,
      sincronizado_garmin: false,
      criado_em: criadoEm.toISOString(),
    });
    if (planoError) throw new Error(`planejamento_clinico (insert): ${planoError.message}`);

    await chunkedUpsert(
      admin,
      'metricas_saude_diarias',
      gerarMetricasDiarias(pacienteId, paciente.idx, paciente.pesoBaseKg),
      'usuario_id_anonimo,data_referencia',
    );

    const { error: gamificacaoError } = await admin.from('progresso_gamificacao').upsert(
      {
        usuario_id_anonimo: pacienteId,
        ofensiva_atual: Math.floor(2 + Math.random() * 30),
        pontuacao_ranking: Math.floor(40 + (paciente.idx % 6) * 8 + Math.random() * 12),
        ultima_atividade_data: new Date().toISOString().slice(0, 10),
        status_usuario: 'ativo',
      },
      { onConflict: 'usuario_id_anonimo' },
    );
    if (gamificacaoError) throw new Error(`progresso_gamificacao: ${gamificacaoError.message}`);
  }

  console.log(`Seed cloud OK: ${PACIENTES.length} pacientes fictícios vinculados a ${PROFISSIONAL_EMAIL}, com ${DIAS_HISTORICO} dias de métricas cada.`);
}

main().catch((err) => {
  console.error('Seed cloud falhou:', err instanceof Error ? err.message : err);
  process.exit(1);
});
