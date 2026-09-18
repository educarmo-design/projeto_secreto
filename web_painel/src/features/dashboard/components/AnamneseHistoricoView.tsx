import { useEffect, useState } from 'react';
import { supabase } from '@/core/supabase';
import type { Database, ObjetivoCodigo } from '@/core/types/database';

type Anamnese = Database['public']['Tables']['anamneses']['Row'];

interface AnamneseHistoricoViewProps {
  pacienteId: string;
  /** Mesmo padrão de gatilho já usado nos outros cards — recarrega a
   * lista quando uma nova Anamnese Profissional é salva. */
  gatilhoRecarga?: number;
}

const ROTULO_OBJETIVO: Record<ObjetivoCodigo, string> = {
  perder_peso: 'Perder peso',
  manter_peso: 'Manter peso',
  ganhar_peso: 'Ganhar peso',
  reduzir_gordura_corporal: 'Reduzir gordura corporal',
  ganhar_massa_muscular: 'Ganhar massa muscular',
  recomposicao_corporal: 'Recomposição corporal',
  melhorar_desempenho_esportivo: 'Melhorar desempenho esportivo',
  outro: 'Outro',
};

interface DetalheAnamnese {
  condicoes: { nome: string; status: string | null }[];
  alergias: string[];
  atividades: { nome: string; dia: number; minutos: number; intensidade: string }[];
  medicamentos: { nome: string; dose: number | null; unidade: string | null }[];
  suplementos: { nome: string; dose: number | null; unidade: string | null }[];
  exames: { nome: string; resultado: string | null }[];
}

const DIAS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

/**
 * Item 3 (RELATÓRIO 20260918_0001, TAREFA "Garantir que a visualização do
 * histórico do paciente exiba todos esses blocos de dados") — lista TODAS
 * as anamneses do paciente (qualquer `status_vigencia`, nenhuma é
 * sobrescrita — mesmo princípio de `HistoricoAnamnesesPage` no app
 * Flutter), com um seletor pra abrir o detalhe completo de cada versão:
 * todos os Blocos 1-12 preenchidos naquela anamnese específica.
 */
export function AnamneseHistoricoView({ pacienteId, gatilhoRecarga }: AnamneseHistoricoViewProps) {
  const [anamneses, setAnamneses] = useState<Anamnese[]>([]);
  const [selecionadaId, setSelecionadaId] = useState<string | null>(null);
  const [detalhe, setDetalhe] = useState<DetalheAnamnese | null>(null);
  const [carregandoLista, setCarregandoLista] = useState(true);
  const [carregandoDetalhe, setCarregandoDetalhe] = useState(false);

  useEffect(() => {
    void carregarLista();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pacienteId, gatilhoRecarga]);

  useEffect(() => {
    if (selecionadaId) void carregarDetalhe(selecionadaId);
  }, [selecionadaId]);

  async function carregarLista() {
    setCarregandoLista(true);
    const { data, error } = await supabase
      .from('anamneses')
      .select('*')
      .eq('usuario_id', pacienteId)
      .order('data_preenchimento', { ascending: false });

    setCarregandoLista(false);
    if (error) return;
    setAnamneses(data ?? []);
    setSelecionadaId(data?.[0]?.id ?? null);
  }

  async function carregarDetalhe(anamneseId: string) {
    setCarregandoDetalhe(true);
    const [condicoesResult, atividadesResult, medicamentosResult, suplementosResult, examesResult, alergiasResult] = await Promise.all([
      supabase.from('anamneses_problemas_saude').select('status, problemas_saude(nome)').eq('anamnese_id', anamneseId),
      supabase
        .from('anamneses_atividades_dias')
        .select('dia_semana, minutos, intensidade, tipos_atividades_fisicas(nome_exibicao)')
        .eq('anamnese_id', anamneseId),
      supabase.from('anamneses_medicamentos').select('nome, dose, unidade').eq('anamnese_id', anamneseId),
      supabase.from('anamneses_suplementos').select('nome, dose, unidade').eq('anamnese_id', anamneseId),
      supabase.from('anamneses_exames_laboratoriais').select('nome_exame, resultado').eq('anamnese_id', anamneseId),
      supabase.from('anamneses_alergias').select('alergias(nome_exibicao)').eq('anamnese_id', anamneseId),
    ]);

    setCarregandoDetalhe(false);

    setDetalhe({
      condicoes: (condicoesResult.data ?? []).map((linha) => {
        const catalogo = linha.problemas_saude as unknown as { nome: string } | { nome: string }[] | null;
        const nome = Array.isArray(catalogo) ? (catalogo[0]?.nome ?? '—') : (catalogo?.nome ?? '—');
        return { nome, status: linha.status };
      }),
      atividades: (atividadesResult.data ?? []).map((linha) => {
        const tipo = linha.tipos_atividades_fisicas as unknown as { nome_exibicao: string } | { nome_exibicao: string }[] | null;
        const nome = Array.isArray(tipo) ? (tipo[0]?.nome_exibicao ?? '—') : (tipo?.nome_exibicao ?? '—');
        return { nome, dia: linha.dia_semana, minutos: linha.minutos, intensidade: linha.intensidade };
      }),
      medicamentos: medicamentosResult.data ?? [],
      suplementos: suplementosResult.data ?? [],
      exames: (examesResult.data ?? []).map((e) => ({ nome: e.nome_exame, resultado: e.resultado })),
      alergias: (alergiasResult.data ?? []).map((linha) => {
        const catalogo = linha.alergias as unknown as { nome_exibicao: string } | { nome_exibicao: string }[] | null;
        return Array.isArray(catalogo) ? (catalogo[0]?.nome_exibicao ?? '—') : (catalogo?.nome_exibicao ?? '—');
      }),
    });
  }

  const selecionada = anamneses.find((a) => a.id === selecionadaId) ?? null;

  return (
    <div className="rounded-2xl border border-clinical-border bg-clinical-surface p-5">
      <div className="mb-4">
        <h2 className="text-sm font-semibold text-slate-100">Histórico de Anamneses</h2>
        <p className="text-xs text-clinical-muted">Todas as versões preenchidas — nenhuma anamnese é sobrescrita.</p>
      </div>

      {carregandoLista ? (
        <p className="text-sm text-clinical-muted">Carregando...</p>
      ) : anamneses.length === 0 ? (
        <p className="text-sm text-clinical-muted">Nenhuma anamnese preenchida ainda.</p>
      ) : (
        <div className="space-y-4">
          <div className="flex flex-wrap gap-2">
            {anamneses.map((a) => (
              <button
                key={a.id}
                type="button"
                onClick={() => setSelecionadaId(a.id)}
                className={`rounded-lg border px-3 py-1.5 text-xs font-medium transition ${
                  a.id === selecionadaId
                    ? 'border-clinical-primary bg-clinical-primary/15 text-clinical-primary'
                    : 'border-clinical-border text-clinical-muted hover:text-slate-100'
                }`}
              >
                v{a.numero_versao ?? '—'} · {new Date(a.data_preenchimento).toLocaleDateString('pt-BR')}
                {a.status_vigencia === 'ativo' && ' (atual)'}
              </button>
            ))}
          </div>

          {selecionada && (
            <div className="space-y-4 rounded-xl border border-clinical-border bg-clinical-bg/60 p-4">
              <Secao titulo="Contexto e Confirmação">
                <Linha label="Origem" valor={selecionada.profissional_id ? 'Prescrita por profissional' : 'Self-service (App)'} />
                <Linha label="Confirmada" valor={selecionada.dados_confirmados ? 'Sim' : 'Não'} />
                {selecionada.data_proxima_avaliacao && (
                  <Linha label="Próxima avaliação" valor={new Date(selecionada.data_proxima_avaliacao).toLocaleDateString('pt-BR')} />
                )}
              </Secao>

              <Secao titulo="Dados Físicos e Antropometria">
                <Linha label="Peso" valor={selecionada.peso_kg !== null ? `${selecionada.peso_kg} kg` : '—'} />
                <Linha label="Altura" valor={selecionada.altura_cm !== null ? `${selecionada.altura_cm} cm` : '—'} />
                {selecionada.percentual_gordura !== null && <Linha label="% gordura" valor={`${selecionada.percentual_gordura}%`} />}
                {selecionada.massa_magra_kg !== null && <Linha label="Massa magra" valor={`${selecionada.massa_magra_kg} kg`} />}
              </Secao>

              <Secao titulo="Objetivo">
                <Linha label="Principal" valor={ROTULO_OBJETIVO[selecionada.objetivo_codigo]} />
                {selecionada.objetivo_outro && <Linha label="Detalhe" valor={selecionada.objetivo_outro} />}
                {selecionada.objetivos_secundarios.length > 0 && (
                  <Linha label="Secundários" valor={selecionada.objetivos_secundarios.map((c) => ROTULO_OBJETIVO[c] ?? c).join(', ')} />
                )}
              </Secao>

              {(selecionada.rotina_diaria || selecionada.atividade_ocupacional || (carregandoDetalhe === false && (detalhe?.atividades.length ?? 0) > 0)) && (
                <Secao titulo="Rotina e Atividades">
                  {selecionada.rotina_diaria && <Linha label="Rotina diária" valor={selecionada.rotina_diaria} />}
                  {carregandoDetalhe ? (
                    <p className="text-xs text-clinical-muted">Carregando atividades...</p>
                  ) : (
                    detalhe?.atividades.map((a, i) => (
                      <Linha key={i} label={DIAS[a.dia] ?? String(a.dia)} valor={`${a.nome} — ${a.minutos} min — ${a.intensidade}`} />
                    ))
                  )}
                </Secao>
              )}

              {selecionada.horas_sono_medias !== null && (
                <Secao titulo="Sono">
                  <Linha label="Horas médias" valor={`${selecionada.horas_sono_medias}h`} />
                  {selecionada.qualidade_sono_percebida && <Linha label="Qualidade" valor={selecionada.qualidade_sono_percebida} />}
                </Secao>
              )}

              <Secao titulo="Condições Especiais">
                <Linha label="Possui condição" valor={selecionada.possui_condicao_saude === null ? 'Não informado' : selecionada.possui_condicao_saude ? 'Sim' : 'Não'} />
                {carregandoDetalhe ? (
                  <p className="text-xs text-clinical-muted">Carregando...</p>
                ) : (
                  <>
                    {detalhe?.condicoes.map((c, i) => <Linha key={i} label={c.nome} valor={c.status ?? '—'} />)}
                    {detalhe && detalhe.alergias.length > 0 && <Linha label="Alergias" valor={detalhe.alergias.join(', ')} />}
                  </>
                )}
              </Secao>

              {(selecionada.bloco_atleta || selecionada.bloco_diabetes || selecionada.bloco_doenca_renal || selecionada.bloco_recomposicao || selecionada.bloco_idoso) && (
                <Secao titulo="Blocos Condicionais">
                  {selecionada.bloco_atleta && <Linha label="Atleta" valor={JSON.stringify(selecionada.bloco_atleta)} />}
                  {selecionada.bloco_diabetes && <Linha label="Diabetes" valor={JSON.stringify(selecionada.bloco_diabetes)} />}
                  {selecionada.bloco_doenca_renal && <Linha label="Doença Renal" valor={JSON.stringify(selecionada.bloco_doenca_renal)} />}
                  {selecionada.bloco_recomposicao && <Linha label="Recomposição" valor={JSON.stringify(selecionada.bloco_recomposicao)} />}
                  {selecionada.bloco_idoso && <Linha label="Idoso" valor={JSON.stringify(selecionada.bloco_idoso)} />}
                </Secao>
              )}

              {!carregandoDetalhe && ((detalhe?.medicamentos.length ?? 0) > 0 || (detalhe?.suplementos.length ?? 0) > 0 || (detalhe?.exames.length ?? 0) > 0) && (
                <Secao titulo="Medicamentos, Suplementos e Exames">
                  {detalhe?.medicamentos.map((m, i) => (
                    <Linha key={`med-${i}`} label={m.nome} valor={`${m.dose ?? '—'} ${m.unidade ?? ''}`} />
                  ))}
                  {detalhe?.suplementos.map((s, i) => (
                    <Linha key={`sup-${i}`} label={s.nome} valor={`${s.dose ?? '—'} ${s.unidade ?? ''}`} />
                  ))}
                  {detalhe?.exames.map((e, i) => (
                    <Linha key={`exa-${i}`} label={e.nome} valor={e.resultado ?? '—'} />
                  ))}
                </Secao>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function Secao({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-clinical-muted">{titulo}</p>
      <div className="space-y-0.5">{children}</div>
    </div>
  );
}

function Linha({ label, valor }: { label: string; valor: string }) {
  return (
    <p className="text-xs text-slate-300">
      <span className="font-medium text-slate-200">{label}:</span> {valor}
    </p>
  );
}
