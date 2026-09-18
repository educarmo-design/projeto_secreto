import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/core/supabase';
import type { MotorMetabolicoV1Resultado } from '@/core/types/database';

interface MotorMetabolicoV1CardProps {
  pacienteId: string;
  /** Incrementado pelo pai (`PatientDetails`) toda vez que a Anamnese
   * Profissional é salva — dispara um novo cálculo automático (mesmo
   * padrão de `gatilhoRecalculo` em `MotorMetabolicoCard`). */
  gatilhoRecalculo?: number;
}

type Estado = 'carregando' | 'sucesso' | 'erro';

/** 0 = domingo .. 6 = sábado — mesma convenção de `anamneses_atividades_dias.dia_semana` (`extract(dow from date)`). */
const ROTULO_DIA: Record<string, string> = {
  '0': 'Dom',
  '1': 'Seg',
  '2': 'Ter',
  '3': 'Qua',
  '4': 'Qui',
  '5': 'Sex',
  '6': 'Sáb',
};

const ROTULO_ESTRATEGIA: Record<string, string> = {
  decomposicao: 'Atividade registrada',
  pal: 'PAL padrão (sedentário)',
  dados_insuficientes: 'Dados insuficientes',
};

const ROTULO_AVISO: Record<string, string> = {
  sem_anamnese_com_dados_antropometricos: 'Nenhuma anamnese com peso e altura preenchidos',
  sem_data_nascimento: 'Sem data de nascimento no perfil',
  sem_sexo_biologico: 'Sem sexo biológico informado',
  sem_peso: 'Sem peso na última anamnese',
  sem_altura: 'Sem altura na última anamnese',
  tmb_nao_calculada_dados_insuficientes: 'TMB não calculada — faltam dados',
};

const ROTULO_SEXO: Record<string, string> = { M: 'Masculino', F: 'Feminino' };

const ROTULO_SCORE_QUALIDADE: Record<string, string> = { alta: 'Alta', media: 'Média', baixa: 'Baixa' };
const COR_SCORE_QUALIDADE: Record<string, string> = {
  alta: 'bg-clinical-success/15 text-clinical-success',
  media: 'bg-clinical-warning/15 text-clinical-warning',
  baixa: 'bg-clinical-critical/15 text-clinical-critical',
};
const ROTULO_MOTIVO_QUALIDADE: Record<string, string> = {
  decomposicao_com_composicao_corporal_confirmada: 'Decomposição (NEAT+EAT) com composição corporal confirmada',
  estrategia_fallback_pal: 'Usando PAL como fallback (sem decomposição por atividade)',
  sem_composicao_corporal_confirmada: 'Sem composição corporal confirmada (% gordura/massa magra)',
  dados_insuficientes_para_tmb: 'Dados insuficientes para calcular a TMB',
};

/**
 * RELATÓRIO 20260917_0001 (item 3, ME-007) — "Raio-X" do Motor Metabólico
 * V1 (`calcular_motor_metabolico_v1`, `20260916120000`): TMB + TDEE
 * detalhado por dia da semana (decomposição por atividade registrada na
 * Anamnese Profissional, ou PAL padrão nos dias sem atividade — Seção "9.
 * Não tratar ausência de atividade como atividade zero"). Igual à
 * `MotorMetabolicoCard` (V0): SÓ LEITURA, não grava nada — a "fotografia"
 * só é persistida quando uma Meta é salva em cima dela (Gap Crítico, item
 * 1, dentro de `validar_e_salvar_meta`).
 */
export function MotorMetabolicoV1Card({ pacienteId, gatilhoRecalculo }: MotorMetabolicoV1CardProps) {
  const [estado, setEstado] = useState<Estado>('carregando');
  const [resultado, setResultado] = useState<MotorMetabolicoV1Resultado | null>(null);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);

  const calcular = useCallback(async () => {
    setEstado('carregando');
    setMensagemErro(null);

    const { data, error } = await supabase.rpc('calcular_motor_metabolico_v1', {
      p_usuario_id: pacienteId,
    });

    if (error) {
      setEstado('erro');
      setMensagemErro(error.message);
      return;
    }

    setResultado(data);
    setEstado('sucesso');
  }, [pacienteId]);

  useEffect(() => {
    void calcular();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pacienteId, gatilhoRecalculo]);

  return (
    <div className="rounded-2xl border border-clinical-border bg-clinical-surface p-5">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-sm font-semibold text-slate-100">Motor Metabólico V1 — Resultados Calculados</h2>
          <p className="text-xs text-clinical-muted">
            Valores informativos (TMB-001 Mifflin-St Jeor) — não são uma meta. Defina a meta abaixo, em Prescrição.
          </p>
        </div>
        <button
          type="button"
          onClick={() => void calcular()}
          disabled={estado === 'carregando'}
          className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:border-clinical-primary hover:text-clinical-primary disabled:cursor-not-allowed disabled:opacity-60"
        >
          {estado === 'carregando' ? 'Calculando...' : 'Recalcular'}
        </button>
      </div>

      {estado === 'erro' && (
        <div role="alert" className="rounded-xl border border-clinical-critical/40 bg-clinical-critical/10 p-4 text-sm text-clinical-critical">
          Erro ao calcular: {mensagemErro}
        </div>
      )}

      {estado === 'carregando' && !resultado && <p className="text-sm text-clinical-muted">Calculando...</p>}

      {resultado && (
        <div className="space-y-4">
          <div className="flex items-center gap-2">
            <span className="text-xs font-medium text-clinical-muted">Qualidade dos dados:</span>
            <span className={`inline-block rounded-full px-2 py-0.5 text-[11px] font-medium ${COR_SCORE_QUALIDADE[resultado.qualidade.score]}`}>
              {ROTULO_SCORE_QUALIDADE[resultado.qualidade.score]}
            </span>
            <span className="text-[11px] text-clinical-muted">
              {resultado.qualidade.motivos.map((m) => ROTULO_MOTIVO_QUALIDADE[m] ?? m).join(' · ')}
            </span>
          </div>

          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            <Estatistica titulo="TMB" valor={resultado.tmb} unidade="kcal/dia" />
            <Estatistica titulo="TEF estimado" valor={resultado.tef_estimado} unidade="kcal/dia (informativo)" />
            <Estatistica titulo="TDEE médio (7 dias)" valor={resultado.tdee_medio} unidade="kcal/dia" destaque />
          </div>

          {resultado.energia_recomendacao && (
            <div className="rounded-xl border border-clinical-primary/40 bg-clinical-primary/10 p-3">
              <p className="text-xs font-medium text-clinical-primary">
                Recomendação do sistema ({resultado.energia_recomendacao.estrategia === 'manutencao' ? 'manutenção' : 'déficit conservador'})
              </p>
              <p className="mt-1 text-lg font-semibold text-slate-100">
                {formatarNumero(resultado.energia_recomendacao.recomendacao_media_diaria)} <span className="text-xs font-normal text-clinical-muted">kcal/dia (média)</span>
              </p>
              {resultado.energia_recomendacao.deficit_percentual !== null && (
                <p className="text-[10px] text-clinical-muted">
                  Déficit de {(resultado.energia_recomendacao.deficit_percentual * 100).toFixed(0)}% sobre o TDEE médio ({resultado.energia_recomendacao.deficit_versao}).
                </p>
              )}
              <p className="mt-1 text-[10px] text-clinical-muted">
                Informativo — nunca é gravado automaticamente como meta. A meta continua sendo definida/confirmada separadamente.
              </p>
            </div>
          )}

          {resultado.macros_recomendados && (
            <div>
              <p className="mb-1.5 text-xs font-medium uppercase tracking-wide text-clinical-muted">
                Macronutrientes recomendados (sobre {formatarNumero(resultado.macros_recomendados.energia_alvo)} kcal/dia)
              </p>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <BlocoMacro
                  titulo={`MACRO-002 (${resultado.macros_recomendados.macro_002.parametros.proteina_g_por_kg}g/kg proteína + ${resultado.macros_recomendados.macro_002.parametros.gordura_g_por_kg}g/kg gordura)`}
                  destaque
                  proteinaG={resultado.macros_recomendados.macro_002.proteina_g}
                  carboidratoG={resultado.macros_recomendados.macro_002.carboidrato_g}
                  gorduraG={resultado.macros_recomendados.macro_002.gordura_g}
                  validacaoOk={resultado.macros_recomendados.macro_002.validacao_soma_ok}
                />
                <BlocoMacro
                  titulo={`MACRO-001 (${(resultado.macros_recomendados.macro_001.parametros.percentual_proteina * 100).toFixed(0)}% P / ${(resultado.macros_recomendados.macro_001.parametros.percentual_carboidrato * 100).toFixed(0)}% C / ${(resultado.macros_recomendados.macro_001.parametros.percentual_gordura * 100).toFixed(0)}% G)`}
                  proteinaG={resultado.macros_recomendados.macro_001.proteina_g}
                  carboidratoG={resultado.macros_recomendados.macro_001.carboidrato_g}
                  gorduraG={resultado.macros_recomendados.macro_001.gordura_g}
                  validacaoOk={resultado.macros_recomendados.macro_001.validacao_soma_ok}
                />
              </div>
            </div>
          )}

          <div>
            <p className="mb-1.5 text-xs font-medium uppercase tracking-wide text-clinical-muted">TDEE por dia da semana</p>
            <div className="grid grid-cols-4 gap-2 sm:grid-cols-7">
              {Object.entries(resultado.tdee_por_dia)
                .sort(([a], [b]) => Number(a) - Number(b))
                .map(([dia, valor]) => (
                  <div key={dia} className="rounded-xl border border-clinical-border bg-clinical-bg/60 p-2 text-center">
                    <p className="text-[10px] font-medium uppercase text-clinical-muted">{ROTULO_DIA[dia] ?? dia}</p>
                    <p className="mt-1 text-sm font-semibold text-slate-100">
                      {valor.tdee !== null ? formatarNumero(valor.tdee) : '—'}
                    </p>
                    <p className="text-[9px] text-clinical-muted">{ROTULO_ESTRATEGIA[valor.estrategia] ?? valor.estrategia}</p>
                  </div>
                ))}
            </div>
          </div>

          <div>
            <p className="mb-1.5 text-xs font-medium uppercase tracking-wide text-clinical-muted">Insumos usados</p>
            <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-slate-300 sm:grid-cols-5">
              <span>Idade: {resultado.insumos.idade ?? '—'}</span>
              <span>Sexo: {resultado.insumos.sexo_biologico ? ROTULO_SEXO[resultado.insumos.sexo_biologico] : '—'}</span>
              <span>Altura: {resultado.insumos.altura_cm !== null ? `${resultado.insumos.altura_cm} cm` : '—'}</span>
              <span>Peso: {resultado.insumos.peso_kg !== null ? `${resultado.insumos.peso_kg} kg` : '—'}</span>
              <span>
                Medido em: {resultado.insumos.peso_data_medicao ? new Date(resultado.insumos.peso_data_medicao).toLocaleDateString('pt-BR') : '—'}
              </span>
            </div>
          </div>

          {resultado.avisos.length > 0 && (
            <div className="rounded-xl border border-clinical-warning/40 bg-clinical-warning/10 p-3">
              <p className="mb-1 text-xs font-medium text-clinical-warning">Dados faltando</p>
              <ul className="list-inside list-disc text-xs text-clinical-warning">
                {resultado.avisos.map((aviso) => (
                  <li key={aviso}>{ROTULO_AVISO[aviso] ?? aviso}</li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function Estatistica({
  titulo,
  valor,
  unidade,
  destaque = false,
}: {
  titulo: string;
  valor: number | null;
  unidade: string;
  destaque?: boolean;
}) {
  return (
    <div
      className={`rounded-xl border p-3 ${
        destaque ? 'border-clinical-primary/40 bg-clinical-primary/10' : 'border-clinical-border bg-clinical-bg/60'
      }`}
    >
      <p className="text-xs text-clinical-muted">{titulo}</p>
      <p className={`mt-1 text-lg font-semibold ${destaque ? 'text-clinical-primary' : 'text-slate-100'}`}>
        {valor !== null ? formatarNumero(valor) : '—'}
      </p>
      {valor !== null && <p className="text-[10px] text-clinical-muted">{unidade}</p>}
    </div>
  );
}

function BlocoMacro({
  titulo,
  proteinaG,
  carboidratoG,
  gorduraG,
  validacaoOk,
  destaque = false,
}: {
  titulo: string;
  proteinaG: number;
  carboidratoG: number;
  gorduraG: number;
  validacaoOk: boolean;
  destaque?: boolean;
}) {
  return (
    <div className={`rounded-xl border p-3 ${destaque ? 'border-clinical-primary/40 bg-clinical-primary/10' : 'border-clinical-border bg-clinical-bg/60'}`}>
      <p className="text-[11px] font-medium text-clinical-muted">{titulo}</p>
      <div className="mt-1 flex gap-4 text-sm text-slate-100">
        <span>P {formatarNumero(proteinaG)}g</span>
        <span>C {formatarNumero(carboidratoG)}g</span>
        <span>G {formatarNumero(gorduraG)}g</span>
      </div>
      {!validacaoOk && (
        <p className="mt-1 text-[10px] text-clinical-critical">Inconsistência na soma de kcal — resultado não deveria ser apresentado como final.</p>
      )}
    </div>
  );
}

function formatarNumero(valor: number): string {
  return valor.toLocaleString('pt-BR', { maximumFractionDigits: 0 });
}
