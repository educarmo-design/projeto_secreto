import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '@/core/supabase';
import type { Database, ObjetivoCodigo } from '@/core/types/database';
import { Toast, type ToastMessage } from '@/components/Toast';

type TipoAtividade = Database['public']['Tables']['tipos_atividades_fisicas']['Row'];
type ProblemaSaude = Database['public']['Tables']['problemas_saude']['Row'];
type Alergia = Database['public']['Tables']['alergias']['Row'];

interface AnamneseProfissionalViewProps {
  pacienteId: string;
  /** Chamado após salvar com sucesso — o pai (`PatientDetails`) usa isto
   * pra incrementar o gatilho de recálculo do `MotorMetabolicoV1Card`,
   * mesmo padrão já estabelecido para `InserirMedicaoModal`. */
  onSalvo?: () => void;
}

/** Lista EXATA da Seção 4.1 do documento (RELATÓRIO 20260918_0001). */
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

const ROTULO_MOTIVO: Record<string, string> = {
  avaliacao_inicial: 'Avaliação inicial',
  reavaliacao_periodica: 'Reavaliação periódica',
  alteracao_objetivo: 'Alteração de objetivo',
  alteracao_condicao_saude: 'Alteração de condição de saúde',
  alteracao_peso: 'Alteração importante de peso',
  alteracao_rotina: 'Alteração de rotina',
  nova_avaliacao_profissional: 'Nova avaliação profissional',
  retorno_apos_interrupcao: 'Retorno após interrupção',
  outro: 'Outro',
};

const ROTULO_ROTINA_DIARIA: Record<string, string> = {
  predominantemente_sentado: 'Predominantemente sentado',
  pouco_ativo: 'Pouco ativo',
  moderadamente_ativo: 'Moderadamente ativo',
  muito_ativo: 'Muito ativo',
  trabalho_fisicamente_intenso: 'Trabalho fisicamente intenso',
};

const ROTULO_QUALIDADE_SONO: Record<string, string> = {
  muito_ruim: 'Muito ruim',
  ruim: 'Ruim',
  regular: 'Regular',
  boa: 'Boa',
  muito_boa: 'Muito boa',
};

const DIAS_SEMANA: { valor: number; rotulo: string }[] = [
  { valor: 1, rotulo: 'Segunda' },
  { valor: 2, rotulo: 'Terça' },
  { valor: 3, rotulo: 'Quarta' },
  { valor: 4, rotulo: 'Quinta' },
  { valor: 5, rotulo: 'Sexta' },
  { valor: 6, rotulo: 'Sábado' },
  { valor: 0, rotulo: 'Domingo' },
];

interface LinhaAtividade {
  chave: string;
  diaSemana: number;
  atividadeId: string;
  minutos: string;
  intensidade: 'leve' | 'moderada' | 'alta';
}

function linhaAtividadeVazia(): LinhaAtividade {
  return { chave: crypto.randomUUID(), diaSemana: 1, atividadeId: '', minutos: '', intensidade: 'moderada' };
}

/** Bloco 9/10/11 — Medicamentos/Suplementos/Exames compartilham a mesma
 * forma "linha com nome + poucos campos" — um único tipo genérico em vez
 * de 3 quase idênticos. */
interface LinhaItem {
  chave: string;
  nome: string;
  campo2: string;
  campo3: string;
}

function linhaItemVazia(): LinhaItem {
  return { chave: crypto.randomUUID(), nome: '', campo2: '', campo3: '' };
}

const FORM_VAZIO = {
  pesoKg: '',
  alturaCm: '',
  objetivoCodigo: 'manter_peso' as ObjetivoCodigo,
  objetivoOutro: '',
  dataProximaAvaliacao: '',
  motivoAvaliacao: '',
  motivoAvaliacaoOutro: '',
  metaPesoDesejado: '',
  metaPercentualGorduraDesejado: '',
  metaMassaDesejada: '',
  metaPrazo: '',
  metaOutroIndicador: '',
  percentualGordura: '',
  massaGorda: '',
  massaMagra: '',
  massaMuscular: '',
  circCintura: '',
  circAbdominal: '',
  houveAlteracaoPeso: '',
  numeroRefeicoes: '',
  horariosRefeicoes: '',
  regularidadeAlimentar: '',
  refeicoesFora: '',
  consumoUltraprocessados: '',
  preferenciasAlimentares: '',
  alimentosEvitados: '',
  restricoesAlimentares: '',
  intolerancias: '',
  padraoAlimentar: '',
  rotinaDiaria: '',
  atividadeOcupacional: '',
  horasSonoMedias: '',
  horarioDormir: '',
  horarioAcordar: '',
  qualidadeSono: '',
  despertaresNoturnos: '',
  sonoObservacoes: '',
  possuiCondicaoSaude: null as boolean | null,
  ativarBlocoAtleta: false,
  atletaModalidade: '',
  atletaHorasSemana: '',
  atletaObjetivoEsportivo: '',
  ativarBlocoDiabetes: false,
  diabetesTipo: '',
  diabetesHba1c: '',
  ativarBlocoRenal: false,
  renalEstagio: '',
  renalTfg: '',
};

/**
 * RELATÓRIO 20260917_0001 (item 2) + RELATÓRIO 20260918_0001 (compliance
 * total, Blocos 1-16 de docs/motor_metabolico.txt) — Anamnese Profissional
 * (Web B2B): profissional preenche PARA o paciente, via a RPC
 * `profissional_salvar_anamnese` (`security definer`, checa vínculo
 * ATIVO). SEM TRAVA DE TEMPO: `data_proxima_avaliacao` é livre.
 *
 * Blocos condicionais (Diabetes/Renal/Atleta) usam um toggle explícito
 * ("Ativar bloco") em vez de inferência automática — diferente do app
 * Flutter, aqui é o profissional quem decide clinicamente quando cada
 * bloco se aplica. Bloco Idoso/Recomposição ficam mais simples (poucos
 * campos, Idoso nem tem campos dedicados aqui — histórico completo fica
 * no App self-service, que já pergunta perda de peso/mobilidade).
 */
export function AnamneseProfissionalView({ pacienteId, onSalvo }: AnamneseProfissionalViewProps) {
  const [form, setForm] = useState(FORM_VAZIO);
  const [linhasAtividade, setLinhasAtividade] = useState<LinhaAtividade[]>([]);
  const [linhasMedicamento, setLinhasMedicamento] = useState<LinhaItem[]>([]);
  const [linhasSuplemento, setLinhasSuplemento] = useState<LinhaItem[]>([]);
  const [linhasExame, setLinhasExame] = useState<LinhaItem[]>([]);
  const [atividades, setAtividades] = useState<TipoAtividade[]>([]);
  const [problemasSaude, setProblemasSaude] = useState<ProblemaSaude[]>([]);
  const [condicoesSelecionadas, setCondicoesSelecionadas] = useState<Set<string>>(new Set());
  const [alergiasCatalogo, setAlergiasCatalogo] = useState<Alergia[]>([]);
  const [alergiasSelecionadas, setAlergiasSelecionadas] = useState<Set<string>>(new Set());
  const [salvando, setSalvando] = useState(false);
  const [toast, setToast] = useState<ToastMessage | null>(null);

  useEffect(() => {
    void carregarCatalogos();
  }, []);

  async function carregarCatalogos() {
    const [atividadesResult, problemasResult, alergiasResult] = await Promise.all([
      supabase.from('tipos_atividades_fisicas').select('*').order('nome_exibicao'),
      supabase.from('problemas_saude').select('*').order('nome'),
      supabase.from('alergias').select('*').order('nome_exibicao'),
    ]);
    if (!atividadesResult.error) setAtividades(atividadesResult.data ?? []);
    if (!problemasResult.error) setProblemasSaude(problemasResult.data ?? []);
    if (!alergiasResult.error) setAlergiasCatalogo(alergiasResult.data ?? []);
    // Erro aqui não impede o resto da tela — os catálogos alimentam
    // seções opcionais (rotina/condições/alergias).
  }

  function adicionarLinhaAtividade() {
    setLinhasAtividade((atual) => [...atual, linhaAtividadeVazia()]);
  }
  function removerLinhaAtividade(chave: string) {
    setLinhasAtividade((atual) => atual.filter((l) => l.chave !== chave));
  }
  function atualizarLinhaAtividade(chave: string, campo: keyof LinhaAtividade, valor: string | number) {
    setLinhasAtividade((atual) => atual.map((l) => (l.chave === chave ? { ...l, [campo]: valor } : l)));
  }

  function toggleCondicao(id: string) {
    setCondicoesSelecionadas((atual) => {
      const novo = new Set(atual);
      if (novo.has(id)) novo.delete(id);
      else novo.add(id);
      return novo;
    });
  }

  function toggleAlergia(id: string) {
    setAlergiasSelecionadas((atual) => {
      const novo = new Set(atual);
      if (novo.has(id)) novo.delete(id);
      else novo.add(id);
      return novo;
    });
  }

  function listaDeTexto(valor: string): string[] {
    return valor
      .split(',')
      .map((item) => item.trim())
      .filter((item) => item.length > 0);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSalvando(true);

    const linhasAtividadeValidas = linhasAtividade.filter((l) => l.atividadeId && l.minutos.trim());
    if (linhasAtividade.some((l) => (l.atividadeId && !l.minutos.trim()) || (!l.atividadeId && l.minutos.trim()))) {
      setSalvando(false);
      setToast({ variant: 'error', text: 'Cada linha de rotina precisa de atividade E minutos preenchidos (ou remova a linha).' });
      return;
    }

    const linhasParaPayload = (linhas: LinhaItem[]) => linhas.filter((l) => l.nome.trim());

    const { data, error } = await supabase.rpc('profissional_salvar_anamnese', {
      p_paciente_id: pacienteId,
      p_payload: {
        objetivo_codigo: form.objetivoCodigo,
        objetivo_outro: form.objetivoCodigo === 'outro' ? form.objetivoOutro.trim() || null : null,
        peso_kg: form.pesoKg.trim() ? Number(form.pesoKg) : null,
        altura_cm: form.alturaCm.trim() ? Number(form.alturaCm) : null,
        data_proxima_avaliacao: form.dataProximaAvaliacao ? `${form.dataProximaAvaliacao}T00:00:00Z` : null,
        motivo_avaliacao: form.motivoAvaliacao || null,
        motivo_avaliacao_outro: form.motivoAvaliacao === 'outro' ? form.motivoAvaliacaoOutro.trim() || null : null,
        meta_peso_desejado_kg: form.metaPesoDesejado.trim() ? Number(form.metaPesoDesejado) : null,
        meta_percentual_gordura_desejado: form.metaPercentualGorduraDesejado.trim() ? Number(form.metaPercentualGorduraDesejado) : null,
        meta_massa_desejada_kg: form.metaMassaDesejada.trim() ? Number(form.metaMassaDesejada) : null,
        meta_prazo: form.metaPrazo || null,
        meta_outro_indicador: form.metaOutroIndicador.trim() || null,
        percentual_gordura: form.percentualGordura.trim() ? Number(form.percentualGordura) : null,
        massa_gorda_kg: form.massaGorda.trim() ? Number(form.massaGorda) : null,
        massa_magra_kg: form.massaMagra.trim() ? Number(form.massaMagra) : null,
        massa_muscular_kg: form.massaMuscular.trim() ? Number(form.massaMuscular) : null,
        circunferencia_cintura_cm: form.circCintura.trim() ? Number(form.circCintura) : null,
        circunferencia_abdominal_cm: form.circAbdominal.trim() ? Number(form.circAbdominal) : null,
        houve_alteracao_peso_nao_planejada: (form.houveAlteracaoPeso || null) as 'sim' | 'nao' | 'nao_sabe' | null,
        numero_refeicoes_dia: form.numeroRefeicoes.trim() ? Number(form.numeroRefeicoes) : null,
        horarios_refeicoes_habituais: form.horariosRefeicoes.trim() || null,
        regularidade_alimentar: form.regularidadeAlimentar.trim() || null,
        refeicoes_fora_de_casa: form.refeicoesFora.trim() || null,
        consumo_ultraprocessados: form.consumoUltraprocessados.trim() || null,
        preferencias_alimentares: form.preferenciasAlimentares.trim() || null,
        alimentos_evitados: form.alimentosEvitados.trim() || null,
        restricoes_alimentares: listaDeTexto(form.restricoesAlimentares),
        intolerancias_alimentares: listaDeTexto(form.intolerancias),
        padrao_alimentar_habitual: form.padraoAlimentar.trim() || null,
        rotina_diaria: form.rotinaDiaria || null,
        atividade_ocupacional: form.atividadeOcupacional.trim() || null,
        horas_sono_medias: form.horasSonoMedias.trim() ? Number(form.horasSonoMedias) : null,
        horario_dormir_habitual: form.horarioDormir || null,
        horario_acordar_habitual: form.horarioAcordar || null,
        qualidade_sono_percebida: form.qualidadeSono || null,
        despertares_noturnos: form.despertaresNoturnos.trim() ? Number(form.despertaresNoturnos) : null,
        sono_observacoes: form.sonoObservacoes.trim() || null,
        possui_condicao_saude: form.possuiCondicaoSaude,
        bloco_atleta: form.ativarBlocoAtleta
          ? { modalidade: form.atletaModalidade, horas_semana: form.atletaHorasSemana, objetivo_esportivo: form.atletaObjetivoEsportivo }
          : null,
        bloco_diabetes: form.ativarBlocoDiabetes ? { tipo: form.diabetesTipo, hba1c: form.diabetesHba1c } : null,
        bloco_doenca_renal: form.ativarBlocoRenal ? { estagio: form.renalEstagio, tfg_egfr: form.renalTfg } : null,
        atividades: linhasAtividadeValidas.map((l) => ({
          atividade_id: Number(l.atividadeId),
          dia_semana: l.diaSemana,
          minutos: Number(l.minutos),
          intensidade: l.intensidade,
        })),
        condicoes_saude: Array.from(condicoesSelecionadas).map((id) => ({ problema_saude_id: id })),
        alergias: Array.from(alergiasSelecionadas),
        medicamentos: linhasParaPayload(linhasMedicamento).map((l) => ({ nome: l.nome, dose: l.campo2 || null, unidade: l.campo3 || null })),
        suplementos: linhasParaPayload(linhasSuplemento).map((l) => ({ nome: l.nome, dose: l.campo2 || null, objetivo: l.campo3 || null })),
        exames: linhasParaPayload(linhasExame).map((l) => ({ nome_exame: l.nome, resultado: l.campo2 || null, unidade: l.campo3 || null })),
      },
    });

    setSalvando(false);

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível salvar a anamnese: ${error.message}` });
      return;
    }

    setToast({ variant: 'success', text: 'Anamnese salva com sucesso.' });
    setForm(FORM_VAZIO);
    setLinhasAtividade([]);
    setLinhasMedicamento([]);
    setLinhasSuplemento([]);
    setLinhasExame([]);
    setCondicoesSelecionadas(new Set());
    setAlergiasSelecionadas(new Set());
    void data; // { sucesso: true, anamnese_id }
    onSalvo?.();
  }

  return (
    <div className="space-y-4 rounded-2xl border border-clinical-border bg-clinical-surface p-5">
      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      <div>
        <h2 className="text-sm font-semibold text-slate-100">Anamnese Profissional</h2>
        <p className="text-xs text-clinical-muted">
          Sem trava de tempo — defina a próxima avaliação livremente. Sempre cria uma nova versão (histórico preservado).
        </p>
      </div>

      <form onSubmit={(event) => void handleSubmit(event)} className="space-y-4">
        {/* Bloco 1 — Contexto */}
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div className="col-span-2">
            <label className="block text-xs font-medium text-slate-300">Motivo da avaliação</label>
            <select
              disabled={salvando}
              value={form.motivoAvaliacao}
              onChange={(event) => setForm((atual) => ({ ...atual, motivoAvaliacao: event.target.value }))}
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
            >
              <option value="">Selecione...</option>
              {Object.entries(ROTULO_MOTIVO).map(([codigo, rotulo]) => (
                <option key={codigo} value={codigo}>
                  {rotulo}
                </option>
              ))}
            </select>
          </div>
          {form.motivoAvaliacao === 'outro' && (
            <div className="col-span-2">
              <CampoTexto
                id="anamnese-prof-motivo-outro"
                label="Descreva o motivo"
                value={form.motivoAvaliacaoOutro}
                disabled={salvando}
                onChange={(valor) => setForm((atual) => ({ ...atual, motivoAvaliacaoOutro: valor }))}
              />
            </div>
          )}
        </div>

        {/* Bloco 3 — Dados físicos e antropometria */}
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <CampoNumerico id="anamnese-prof-peso" label="Peso (kg)" value={form.pesoKg} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, pesoKg: v }))} />
          <CampoNumerico id="anamnese-prof-altura" label="Altura (cm)" value={form.alturaCm} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, alturaCm: v }))} />
          <div className="col-span-2">
            <label htmlFor="anamnese-prof-proxima-avaliacao" className="block text-xs font-medium text-slate-300">
              Data da Próxima Avaliação
            </label>
            <input
              id="anamnese-prof-proxima-avaliacao"
              type="date"
              disabled={salvando}
              value={form.dataProximaAvaliacao}
              onChange={(event) => setForm((atual) => ({ ...atual, dataProximaAvaliacao: event.target.value }))}
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
            />
            <p className="mt-1 text-[10px] text-clinical-muted">Livre — sem trava de 30 dias (essa regra é só para o preenchimento self-service).</p>
          </div>
        </div>

        <details className="rounded-lg border border-clinical-border p-3">
          <summary className="cursor-pointer text-xs font-medium text-slate-300">Composição corporal (opcional)</summary>
          <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
            <CampoNumerico id="anamnese-prof-pgordura" label="% de gordura" value={form.percentualGordura} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, percentualGordura: v }))} />
            <CampoNumerico id="anamnese-prof-massa-magra" label="Massa magra (kg)" value={form.massaMagra} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, massaMagra: v }))} />
            <CampoNumerico id="anamnese-prof-massa-gorda" label="Massa gorda (kg)" value={form.massaGorda} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, massaGorda: v }))} />
            <CampoNumerico id="anamnese-prof-massa-muscular" label="Massa muscular (kg)" value={form.massaMuscular} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, massaMuscular: v }))} />
            <CampoNumerico id="anamnese-prof-cintura" label="Circunf. cintura (cm)" value={form.circCintura} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, circCintura: v }))} />
            <CampoNumerico id="anamnese-prof-abdominal" label="Circunf. abdominal (cm)" value={form.circAbdominal} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, circAbdominal: v }))} />
          </div>
        </details>

        {/* Bloco 4 — houve alteração de peso não planejada */}
        <div>
          <p className="mb-1.5 text-xs font-medium text-slate-300">Houve perda ou ganho de peso importante não planejado?</p>
          <div className="flex gap-2">
            {(['sim', 'nao', 'nao_sabe'] as const).map((opcao) => (
              <PillRadio
                key={opcao}
                selecionado={form.houveAlteracaoPeso === opcao}
                disabled={salvando}
                onClick={() => setForm((a) => ({ ...a, houveAlteracaoPeso: opcao }))}
              >
                {opcao === 'sim' ? 'Sim' : opcao === 'nao' ? 'Não' : 'Não sabe'}
              </PillRadio>
            ))}
          </div>
        </div>

        {/* Bloco 2 — Objetivo */}
        <div>
          <p className="mb-1.5 text-xs font-medium text-slate-300">Objetivo</p>
          <div className="flex flex-wrap gap-2">
            {(Object.keys(ROTULO_OBJETIVO) as ObjetivoCodigo[]).map((codigo) => (
              <label
                key={codigo}
                className={`cursor-pointer rounded-lg border px-3 py-1.5 text-xs font-medium transition ${
                  form.objetivoCodigo === codigo
                    ? 'border-clinical-primary bg-clinical-primary/15 text-clinical-primary'
                    : 'border-clinical-border text-clinical-muted hover:text-slate-100'
                }`}
              >
                <input
                  type="radio"
                  name="anamnese-prof-objetivo"
                  className="sr-only"
                  checked={form.objetivoCodigo === codigo}
                  disabled={salvando}
                  onChange={() => setForm((atual) => ({ ...atual, objetivoCodigo: codigo }))}
                />
                {ROTULO_OBJETIVO[codigo]}
              </label>
            ))}
          </div>
          {form.objetivoCodigo === 'outro' && (
            <input
              type="text"
              required
              disabled={salvando}
              value={form.objetivoOutro}
              onChange={(event) => setForm((atual) => ({ ...atual, objetivoOutro: event.target.value }))}
              placeholder="Outros objetivos personalizados..."
              className="mt-2 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
            />
          )}
        </div>

        <details className="rounded-lg border border-clinical-border p-3">
          <summary className="cursor-pointer text-xs font-medium text-slate-300">Meta quantitativa (opcional)</summary>
          <p className="mt-1 text-[10px] text-clinical-muted">Informar uma meta não significa que ela seja automaticamente considerada clinicamente adequada.</p>
          <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <CampoNumerico id="anamnese-prof-meta-peso" label="Peso desejado (kg)" value={form.metaPesoDesejado} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, metaPesoDesejado: v }))} />
            <CampoNumerico id="anamnese-prof-meta-gordura" label="% gordura desejado" value={form.metaPercentualGorduraDesejado} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, metaPercentualGorduraDesejado: v }))} />
            <CampoNumerico id="anamnese-prof-meta-massa" label="Massa desejada (kg)" value={form.metaMassaDesejada} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, metaMassaDesejada: v }))} />
            <div>
              <label className="block text-xs font-medium text-slate-300">Prazo</label>
              <input
                type="date"
                disabled={salvando}
                value={form.metaPrazo}
                onChange={(event) => setForm((atual) => ({ ...atual, metaPrazo: event.target.value }))}
                className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
              />
            </div>
          </div>
        </details>

        {/* Bloco 5 — Alimentação (sem duplicar o diário alimentar já existente) */}
        <details className="rounded-lg border border-clinical-border p-3">
          <summary className="cursor-pointer text-xs font-medium text-slate-300">Alimentação (opcional)</summary>
          <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
            <CampoNumerico id="anamnese-prof-refeicoes" label="Refeições/dia" value={form.numeroRefeicoes} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, numeroRefeicoes: v }))} />
            <CampoTexto id="anamnese-prof-horarios" label="Horários habituais" value={form.horariosRefeicoes} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, horariosRefeicoes: v }))} />
            <CampoTexto id="anamnese-prof-regularidade" label="Regularidade" value={form.regularidadeAlimentar} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, regularidadeAlimentar: v }))} />
            <CampoTexto id="anamnese-prof-fora" label="Refeições fora de casa" value={form.refeicoesFora} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, refeicoesFora: v }))} />
            <CampoTexto id="anamnese-prof-ultraprocessados" label="Consumo de ultraprocessados" value={form.consumoUltraprocessados} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, consumoUltraprocessados: v }))} />
            <CampoTexto id="anamnese-prof-preferencias" label="Preferências alimentares" value={form.preferenciasAlimentares} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, preferenciasAlimentares: v }))} />
            <CampoTexto id="anamnese-prof-evitados" label="Alimentos evitados" value={form.alimentosEvitados} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, alimentosEvitados: v }))} />
            <CampoTexto id="anamnese-prof-restricoes" label="Restrições (separe por vírgula)" value={form.restricoesAlimentares} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, restricoesAlimentares: v }))} />
            <CampoTexto id="anamnese-prof-intolerancias" label="Intolerâncias (separe por vírgula)" value={form.intolerancias} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, intolerancias: v }))} />
            <CampoTexto id="anamnese-prof-padrao" label="Padrão alimentar habitual" value={form.padraoAlimentar} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, padraoAlimentar: v }))} />
          </div>
        </details>

        {/* Bloco 5 — Alergias (padrão clínico, catálogo curado no banco) */}
        <div>
          <p className="mb-1.5 text-xs font-medium text-slate-300">Alergias</p>
          {alergiasCatalogo.length === 0 ? (
            <p className="text-xs text-clinical-muted">Nenhuma alergia cadastrada no sistema ainda.</p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {alergiasCatalogo.map((item) => (
                <label
                  key={item.id}
                  className={`cursor-pointer rounded-lg border px-2.5 py-1 text-xs transition ${
                    alergiasSelecionadas.has(item.id)
                      ? 'border-clinical-primary bg-clinical-primary/15 text-clinical-primary'
                      : 'border-clinical-border text-clinical-muted hover:text-slate-100'
                  }`}
                >
                  <input type="checkbox" className="sr-only" disabled={salvando} checked={alergiasSelecionadas.has(item.id)} onChange={() => toggleAlergia(item.id)} />
                  {item.nome_exibicao}
                </label>
              ))}
            </div>
          )}
        </div>

        {/* Seção 5 + Bloco 6 — Rotina diária e atividade ocupacional */}
        <div>
          <p className="mb-1.5 text-xs font-medium text-slate-300">Como é a rotina na maior parte do dia?</p>
          <div className="flex flex-wrap gap-2">
            {Object.entries(ROTULO_ROTINA_DIARIA).map(([codigo, rotulo]) => (
              <PillRadio key={codigo} selecionado={form.rotinaDiaria === codigo} disabled={salvando} onClick={() => setForm((a) => ({ ...a, rotinaDiaria: codigo }))}>
                {rotulo}
              </PillRadio>
            ))}
          </div>
          <div className="mt-2">
            <CampoTexto id="anamnese-prof-ocupacional" label="Atividade ocupacional (opcional)" value={form.atividadeOcupacional} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, atividadeOcupacional: v }))} />
          </div>
        </div>

        {/* Bloco 6 — Rotina de atividades por dia da semana, com Intensidade */}
        <div>
          <div className="mb-1.5 flex items-center justify-between">
            <p className="text-xs font-medium text-slate-300">Rotina de atividades por dia da semana (opcional)</p>
            <button
              type="button"
              onClick={adicionarLinhaAtividade}
              disabled={salvando}
              className="rounded-lg border border-clinical-border px-2.5 py-1 text-[11px] font-medium text-clinical-muted transition hover:border-clinical-primary hover:text-clinical-primary"
            >
              + Adicionar linha
            </button>
          </div>
          <p className="mb-2 text-[10px] text-clinical-muted">
            Dias sem nenhuma linha usam o PAL padrão (sedentário) no Motor Metabólico — não é tratado como "sem atividade nenhuma".
          </p>
          {linhasAtividade.length === 0 ? (
            <p className="text-xs text-clinical-muted">Nenhuma linha adicionada.</p>
          ) : (
            <div className="space-y-2">
              {linhasAtividade.map((linha) => (
                <div key={linha.chave} className="flex flex-wrap items-end gap-2">
                  <select
                    disabled={salvando}
                    value={linha.diaSemana}
                    onChange={(event) => atualizarLinhaAtividade(linha.chave, 'diaSemana', Number(event.target.value))}
                    className="rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                  >
                    {DIAS_SEMANA.map((d) => (
                      <option key={d.valor} value={d.valor}>
                        {d.rotulo}
                      </option>
                    ))}
                  </select>
                  <select
                    disabled={salvando}
                    value={linha.atividadeId}
                    onChange={(event) => atualizarLinhaAtividade(linha.chave, 'atividadeId', event.target.value)}
                    className="min-w-[160px] flex-1 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                  >
                    <option value="">Selecione a atividade...</option>
                    {atividades.map((a) => (
                      <option key={a.id} value={a.id}>
                        {a.nome_exibicao}
                      </option>
                    ))}
                  </select>
                  <input
                    type="number"
                    min="0"
                    step="1"
                    placeholder="min"
                    disabled={salvando}
                    value={linha.minutos}
                    onChange={(event) => atualizarLinhaAtividade(linha.chave, 'minutos', event.target.value)}
                    className="w-20 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                  />
                  <select
                    disabled={salvando}
                    value={linha.intensidade}
                    onChange={(event) => atualizarLinhaAtividade(linha.chave, 'intensidade', event.target.value)}
                    className="rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                    title="Intensidade"
                  >
                    <option value="leve">Leve</option>
                    <option value="moderada">Moderada</option>
                    <option value="alta">Alta</option>
                  </select>
                  <button
                    type="button"
                    onClick={() => removerLinhaAtividade(linha.chave)}
                    disabled={salvando}
                    className="rounded-lg border border-clinical-border px-2 py-1.5 text-xs text-clinical-muted transition hover:border-clinical-critical hover:text-clinical-critical"
                  >
                    Remover
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Bloco 7 — Sono */}
        <details className="rounded-lg border border-clinical-border p-3">
          <summary className="cursor-pointer text-xs font-medium text-slate-300">Sono e Recuperação (opcional)</summary>
          <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
            <CampoNumerico id="anamnese-prof-sono-horas" label="Horas médias de sono" value={form.horasSonoMedias} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, horasSonoMedias: v }))} />
            <div>
              <label className="block text-xs font-medium text-slate-300">Horário de dormir</label>
              <input type="time" disabled={salvando} value={form.horarioDormir} onChange={(e) => setForm((a) => ({ ...a, horarioDormir: e.target.value }))} className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60" />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300">Horário de acordar</label>
              <input type="time" disabled={salvando} value={form.horarioAcordar} onChange={(e) => setForm((a) => ({ ...a, horarioAcordar: e.target.value }))} className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60" />
            </div>
            <div>
              <label className="block text-xs font-medium text-slate-300">Qualidade percebida</label>
              <select disabled={salvando} value={form.qualidadeSono} onChange={(e) => setForm((a) => ({ ...a, qualidadeSono: e.target.value }))} className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60">
                <option value="">Selecione...</option>
                {Object.entries(ROTULO_QUALIDADE_SONO).map(([codigo, rotulo]) => (
                  <option key={codigo} value={codigo}>
                    {rotulo}
                  </option>
                ))}
              </select>
            </div>
            <CampoNumerico id="anamnese-prof-despertares" label="Despertares noturnos" value={form.despertaresNoturnos} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, despertaresNoturnos: v }))} />
            <CampoTexto id="anamnese-prof-sono-obs" label="Outras observações" value={form.sonoObservacoes} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, sonoObservacoes: v }))} />
          </div>
        </details>

        {/* Bloco 8 — Condições de saúde */}
        <div>
          <p className="mb-1.5 text-xs font-medium text-slate-300">Possui alguma condição de saúde relevante?</p>
          <div className="flex gap-2">
            <PillRadio selecionado={form.possuiCondicaoSaude === false} disabled={salvando} onClick={() => setForm((a) => ({ ...a, possuiCondicaoSaude: false }))}>
              Não tenho
            </PillRadio>
            <PillRadio selecionado={form.possuiCondicaoSaude === true} disabled={salvando} onClick={() => setForm((a) => ({ ...a, possuiCondicaoSaude: true }))}>
              Sim, tem
            </PillRadio>
          </div>
          {form.possuiCondicaoSaude === true && (
            <div className="mt-2 max-h-40 overflow-y-auto rounded-lg border border-clinical-border p-2">
              {problemasSaude.length === 0 ? (
                <p className="text-xs text-clinical-muted">Nenhuma condição cadastrada no sistema ainda.</p>
              ) : (
                problemasSaude.map((item) => (
                  <label key={item.id} className="flex items-center gap-2 py-1 text-xs text-slate-300">
                    <input type="checkbox" disabled={salvando} checked={condicoesSelecionadas.has(item.id)} onChange={() => toggleCondicao(item.id)} />
                    {item.nome}
                  </label>
                ))
              )}
            </div>
          )}
        </div>

        {/* Bloco 12 — Blocos condicionais (o profissional decide clinicamente quando ativar) */}
        <BlocoCondicionalAtleta form={form} setForm={setForm} salvando={salvando} />
        <BlocoCondicionalDiabetes form={form} setForm={setForm} salvando={salvando} />
        <BlocoCondicionalRenal form={form} setForm={setForm} salvando={salvando} />

        {/* Blocos 9/10/11 — Medicamentos, Suplementos, Exames */}
        <LinhaRepetivel titulo="Medicamentos (opcional)" campo2Label="Dose" campo3Label="Unidade" linhas={linhasMedicamento} setLinhas={setLinhasMedicamento} disabled={salvando} />
        <LinhaRepetivel titulo="Suplementos (opcional)" campo2Label="Dose" campo3Label="Objetivo" linhas={linhasSuplemento} setLinhas={setLinhasSuplemento} disabled={salvando} />
        <LinhaRepetivel titulo="Exames Laboratoriais (opcional)" nomeLabel="Nome do exame" campo2Label="Resultado" campo3Label="Unidade" linhas={linhasExame} setLinhas={setLinhasExame} disabled={salvando} />

        <div className="flex justify-end">
          <button
            type="submit"
            disabled={salvando}
            className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {salvando ? 'Salvando...' : 'Salvar Anamnese'}
          </button>
        </div>
      </form>
    </div>
  );
}

function BlocoCondicionalAtleta({
  form,
  setForm,
  salvando,
}: {
  form: typeof FORM_VAZIO;
  setForm: React.Dispatch<React.SetStateAction<typeof FORM_VAZIO>>;
  salvando: boolean;
}) {
  return (
    <details className="rounded-lg border border-clinical-border p-3" open={form.ativarBlocoAtleta}>
      <summary className="cursor-pointer text-xs font-medium text-slate-300">
        <label className="inline-flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
          <input type="checkbox" disabled={salvando} checked={form.ativarBlocoAtleta} onChange={(e) => setForm((a) => ({ ...a, ativarBlocoAtleta: e.target.checked }))} />
          Bloco Atleta
        </label>
      </summary>
      {form.ativarBlocoAtleta && (
        <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
          <CampoTexto id="bloco-atleta-modalidade" label="Modalidade principal" value={form.atletaModalidade} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, atletaModalidade: v }))} />
          <CampoNumerico id="bloco-atleta-horas" label="Horas de treino/semana" value={form.atletaHorasSemana} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, atletaHorasSemana: v }))} />
          <CampoTexto id="bloco-atleta-objetivo" label="Objetivo esportivo" value={form.atletaObjetivoEsportivo} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, atletaObjetivoEsportivo: v }))} />
        </div>
      )}
    </details>
  );
}

function BlocoCondicionalDiabetes({
  form,
  setForm,
  salvando,
}: {
  form: typeof FORM_VAZIO;
  setForm: React.Dispatch<React.SetStateAction<typeof FORM_VAZIO>>;
  salvando: boolean;
}) {
  return (
    <details className="rounded-lg border border-clinical-border p-3" open={form.ativarBlocoDiabetes}>
      <summary className="cursor-pointer text-xs font-medium text-slate-300">
        <label className="inline-flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
          <input type="checkbox" disabled={salvando} checked={form.ativarBlocoDiabetes} onChange={(e) => setForm((a) => ({ ...a, ativarBlocoDiabetes: e.target.checked }))} />
          Bloco Diabetes
        </label>
      </summary>
      {form.ativarBlocoDiabetes && (
        <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
          <CampoTexto id="bloco-diabetes-tipo" label="Tipo de diabetes" value={form.diabetesTipo} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, diabetesTipo: v }))} />
          <CampoTexto id="bloco-diabetes-hba1c" label="HbA1c (se disponível)" value={form.diabetesHba1c} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, diabetesHba1c: v }))} />
        </div>
      )}
    </details>
  );
}

function BlocoCondicionalRenal({
  form,
  setForm,
  salvando,
}: {
  form: typeof FORM_VAZIO;
  setForm: React.Dispatch<React.SetStateAction<typeof FORM_VAZIO>>;
  salvando: boolean;
}) {
  return (
    <details className="rounded-lg border border-clinical-border p-3" open={form.ativarBlocoRenal}>
      <summary className="cursor-pointer text-xs font-medium text-slate-300">
        <label className="inline-flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
          <input type="checkbox" disabled={salvando} checked={form.ativarBlocoRenal} onChange={(e) => setForm((a) => ({ ...a, ativarBlocoRenal: e.target.checked }))} />
          Bloco Doença Renal
        </label>
      </summary>
      {form.ativarBlocoRenal && (
        <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
          <CampoTexto id="bloco-renal-estagio" label="Estágio (se conhecido)" value={form.renalEstagio} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, renalEstagio: v }))} />
          <CampoTexto id="bloco-renal-tfg" label="TFG/eGFR (se disponível)" value={form.renalTfg} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, renalTfg: v }))} />
        </div>
      )}
    </details>
  );
}

function LinhaRepetivel({
  titulo,
  nomeLabel = 'Nome',
  campo2Label,
  campo3Label,
  linhas,
  setLinhas,
  disabled,
}: {
  titulo: string;
  nomeLabel?: string;
  campo2Label: string;
  campo3Label: string;
  linhas: LinhaItem[];
  setLinhas: React.Dispatch<React.SetStateAction<LinhaItem[]>>;
  disabled: boolean;
}) {
  function atualizar(chave: string, campo: keyof LinhaItem, valor: string) {
    setLinhas((atual) => atual.map((l) => (l.chave === chave ? { ...l, [campo]: valor } : l)));
  }

  return (
    <div>
      <div className="mb-1.5 flex items-center justify-between">
        <p className="text-xs font-medium text-slate-300">{titulo}</p>
        <button
          type="button"
          onClick={() => setLinhas((atual) => [...atual, linhaItemVazia()])}
          disabled={disabled}
          className="rounded-lg border border-clinical-border px-2.5 py-1 text-[11px] font-medium text-clinical-muted transition hover:border-clinical-primary hover:text-clinical-primary"
        >
          + Adicionar
        </button>
      </div>
      {linhas.length === 0 ? (
        <p className="text-xs text-clinical-muted">Nenhum item adicionado.</p>
      ) : (
        <div className="space-y-2">
          {linhas.map((linha) => (
            <div key={linha.chave} className="flex flex-wrap items-end gap-2">
              <input
                type="text"
                placeholder={nomeLabel}
                disabled={disabled}
                value={linha.nome}
                onChange={(event) => atualizar(linha.chave, 'nome', event.target.value)}
                className="min-w-[140px] flex-1 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
              />
              <input
                type="text"
                placeholder={campo2Label}
                disabled={disabled}
                value={linha.campo2}
                onChange={(event) => atualizar(linha.chave, 'campo2', event.target.value)}
                className="w-28 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
              />
              <input
                type="text"
                placeholder={campo3Label}
                disabled={disabled}
                value={linha.campo3}
                onChange={(event) => atualizar(linha.chave, 'campo3', event.target.value)}
                className="w-28 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
              />
              <button
                type="button"
                onClick={() => setLinhas((atual) => atual.filter((l) => l.chave !== linha.chave))}
                disabled={disabled}
                className="rounded-lg border border-clinical-border px-2 py-1.5 text-xs text-clinical-muted transition hover:border-clinical-critical hover:text-clinical-critical"
              >
                Remover
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function PillRadio({
  children,
  selecionado,
  disabled,
  onClick,
}: {
  children: React.ReactNode;
  selecionado: boolean;
  disabled: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className={`rounded-lg border px-3 py-1.5 text-xs font-medium transition disabled:opacity-60 ${
        selecionado ? 'border-clinical-primary bg-clinical-primary/15 text-clinical-primary' : 'border-clinical-border text-clinical-muted hover:text-slate-100'
      }`}
    >
      {children}
    </button>
  );
}

function CampoTexto({
  id,
  label,
  value,
  onChange,
  disabled,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (valor: string) => void;
  disabled: boolean;
}) {
  return (
    <div>
      <label htmlFor={id} className="block text-xs font-medium text-slate-300">
        {label}
      </label>
      <input
        id={id}
        type="text"
        disabled={disabled}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
      />
    </div>
  );
}

function CampoNumerico({
  id,
  label,
  value,
  onChange,
  disabled,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (valor: string) => void;
  disabled: boolean;
}) {
  return (
    <div>
      <label htmlFor={id} className="block text-xs font-medium text-slate-300">
        {label}
      </label>
      <input
        id={id}
        type="number"
        min="0"
        step="0.1"
        disabled={disabled}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
      />
    </div>
  );
}
