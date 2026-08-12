import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/core/supabase';
import type { MotorMetabolicoResultado } from '@/core/types/database';

interface MotorMetabolicoCardProps {
  pacienteId: string;
  /** Incrementado pelo pai (`PatientDetails`) toda vez que uma nova medição é
   * gravada (`InserirMedicaoModal`) — dispara um novo cálculo automático,
   * sem o profissional precisar clicar em "Recalcular" à toa. */
  gatilhoRecalculo?: number;
}

type Estado = 'carregando' | 'sucesso' | 'erro';

const ROTULO_FORMULA: Record<MotorMetabolicoResultado['formula_usada'], string> = {
  katch_mcardle: 'Katch-McArdle (massa magra medida)',
  mifflin_st_jeor: 'Mifflin-St Jeor (idade + peso + altura + sexo)',
  dados_insuficientes: 'Dados insuficientes',
};

const COR_FORMULA: Record<MotorMetabolicoResultado['formula_usada'], string> = {
  katch_mcardle: 'bg-clinical-success/15 text-clinical-success',
  mifflin_st_jeor: 'bg-clinical-primary/15 text-clinical-primary',
  dados_insuficientes: 'bg-clinical-warning/15 text-clinical-warning',
};

/** Mapeia o código cru devolvido em `avisos` para uma frase legível — ver
 * `calcular_motor_metabolico` (`20260812100000`) para a lista completa. */
const ROTULO_AVISO: Record<string, string> = {
  sem_massa_magra: 'Sem massa magra medida (bioimpedância)',
  sem_peso: 'Sem peso registrado',
  sem_data_nascimento: 'Sem data de nascimento no perfil',
  sem_sexo_biologico: 'Sem sexo biológico informado',
  sem_altura: 'Sem altura registrada',
  sem_peso_para_gasto_atividade: 'Sem peso — gasto de atividade não pôde ser calculado',
  sem_anamnese_ativa: 'Paciente sem anamnese ativa (nenhuma atividade considerada)',
};

const ROTULO_SEXO: Record<string, string> = { M: 'Masculino', F: 'Feminino' };

/**
 * N07 (RELATÓRIO 20260812_0009) — "Raio-X" do Motor Metabólico: chama
 * `calcular_motor_metabolico` (RPC, `20260812100000`) pro paciente aberto e
 * mostra TMB/PAL decomposto/TEF/TDEE em tempo real, exatamente o payload
 * que o app mobile também vai consumir (mesma RPC, mesma matemática — ver
 * migration para as fórmulas completas e o RELATÓRIO 20260812_0008 para a
 * verificação funcional com conferência manual).
 *
 * Puramente uma SIMULAÇÃO/visualização: não grava nada, não é uma
 * prescrição — o profissional decide o que fazer com o número. TEF é
 * mostrado separado do TDEE de propósito (o mesmo "anti double-count" que
 * a RPC já implementa): somar os dois na tela seria reintroduzir o erro
 * que a RPC foi desenhada para evitar.
 */
export function MotorMetabolicoCard({ pacienteId, gatilhoRecalculo }: MotorMetabolicoCardProps) {
  const [estado, setEstado] = useState<Estado>('carregando');
  const [resultado, setResultado] = useState<MotorMetabolicoResultado | null>(null);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);

  const calcular = useCallback(async () => {
    setEstado('carregando');
    setMensagemErro(null);

    const { data, error } = await supabase.rpc('calcular_motor_metabolico', {
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
          <h2 className="text-sm font-semibold text-slate-100">Motor Metabólico (N07)</h2>
          <p className="text-xs text-clinical-muted">
            Simulação em tempo real — TMB, PAL decomposto e TEF isolado. Não grava nada.
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
          <span className={`inline-block rounded-full px-2.5 py-1 text-xs font-medium ${COR_FORMULA[resultado.formula_usada]}`}>
            {ROTULO_FORMULA[resultado.formula_usada]}
          </span>

          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <Estatistica titulo="TMB" valor={resultado.tmb} unidade="kcal/dia" />
            <Estatistica titulo="Gasto Sedentário" valor={resultado.gasto_sedentario} unidade="kcal/dia" />
            <Estatistica titulo="Gasto de Atividade" valor={resultado.gasto_atividade} unidade="kcal/dia" />
            <Estatistica
              titulo="TDEE"
              valor={resultado.tdee}
              unidade="kcal/dia"
              destaque
            />
          </div>

          <div className="rounded-xl border border-clinical-border bg-clinical-bg/60 p-3">
            <p className="text-xs text-clinical-muted">
              <span className="font-medium text-slate-300">TEF (Efeito Térmico do Alimento):</span>{' '}
              {resultado.tef !== null ? `${formatarNumero(resultado.tef)} kcal/dia` : '—'} — informativo, já{' '}
              <span className="font-medium">não somado</span> ao TDEE acima (evita contar o mesmo gasto duas vezes).
            </p>
          </div>

          <div>
            <p className="mb-1.5 text-xs font-medium uppercase tracking-wide text-clinical-muted">Insumos usados</p>
            <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-slate-300 sm:grid-cols-5">
              <span>Idade: {resultado.insumos.idade ?? '—'}</span>
              <span>Sexo: {resultado.insumos.sexo_biologico ? ROTULO_SEXO[resultado.insumos.sexo_biologico] : '—'}</span>
              <span>Altura: {resultado.insumos.altura_cm !== null ? `${resultado.insumos.altura_cm} cm` : '—'}</span>
              <span>Peso: {resultado.insumos.peso_kg !== null ? `${resultado.insumos.peso_kg} kg` : '—'}</span>
              <span>Massa magra: {resultado.insumos.massa_magra_kg !== null ? `${resultado.insumos.massa_magra_kg} kg` : '—'}</span>
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

function formatarNumero(valor: number): string {
  return valor.toLocaleString('pt-BR', { maximumFractionDigits: 0 });
}
