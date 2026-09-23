import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '@/core/supabase';
import type { Database, ObjetivoCodigo } from '@/core/types/database';
import { Toast, type ToastMessage } from '@/components/Toast';

type TipoAtividade = Database['public']['Tables']['tipos_atividades_fisicas']['Row'];
type ProblemaSaude = Database['public']['Tables']['problemas_saude']['Row'];
type Alergia = Database['public']['Tables']['alergias']['Row'];

/** RELATÓRIO 20260922_0002 (Item 1) — mesmo catálogo estático do App
 * Flutter (`_restricoesCulturaisCodigos`/`restricao_cultural_*`, sem
 * tabela-catálogo no banco: `restricoes_culturais_religiosas` é `text[]`
 * livre). */
const ROTULO_RESTRICAO_CULTURAL: Record<string, string> = {
  vegano: 'Vegano',
  vegetariano: 'Vegetariano',
  kosher: 'Kosher',
  halal: 'Halal',
  jejum_intermitente: 'Jejum intermitente',
  outros: 'Outros',
};

interface LinhaRefeicaoHabitual {
  chave: string;
  numeroRefeicao: number;
  horario: string;
  foraDeCasa: boolean;
  descricaoTexto: string;
  kcal: number | null;
  proteinaG: number | null;
  carboidratoG: number | null;
  gorduraG: number | null;
  interpretando: boolean;
  erroIa: string | null;
}

function linhaRefeicaoVazia(numero: number): LinhaRefeicaoHabitual {
  return {
    chave: crypto.randomUUID(),
    numeroRefeicao: numero,
    horario: '',
    foraDeCasa: false,
    descricaoTexto: '',
    kcal: null,
    proteinaG: null,
    carboidratoG: null,
    gorduraG: null,
    interpretando: false,
    erroIa: null,
  };
}

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
  // RELATÓRIO 20260918_0002 — gap achado na tarefa anterior: Idoso e
  // Recomposição Corporal ficaram sem toggle no Painel Web (só Atleta/
  // Diabetes/Renal tinham).
  ativarBlocoIdoso: false,
  idosoPerdaPeso: false,
  idosoReducaoForcaMobilidade: false,
  idosoDificuldadeAlimentacao: false,
  ativarBlocoRecomposicao: false,
  recomposicaoPercentualAtual: '',
  recomposicaoPercentualDesejado: '',
  recomposicaoTreinamentoResistido: false,
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
  // Bloco 6 — filtro de texto do seletor de atividades (RELATÓRIO
  // 20260918_0002, gap achado na tarefa anterior: o app já tinha busca, o
  // Painel Web não).
  const [buscaAtividade, setBuscaAtividade] = useState('');
  // Bloco 4 (Seção 7) — histórico de peso do paciente, só leitura, via a
  // RPC pura `anamnese_historico_peso` (RELATÓRIO 20260918_0001) — gap
  // achado na tarefa anterior: a RPC existia e estava tipada, mas nenhuma
  // tela do Painel a chamava ainda.
  const [historicoPeso, setHistoricoPeso] = useState<Database['public']['Functions']['anamnese_historico_peso']['Returns'] | null>(null);

  // RELATÓRIO 20260922_0002 (Item 1) — Sexo Biológico exibido ANTES do
  // Motivo (pedido explícito), lido do perfil do paciente — mesma view
  // `perfis_pacientes_vinculados` que `PatientDetails.tsx` já usa.
  const [sexoBiologico, setSexoBiologico] = useState<string | null>(null);

  // RELATÓRIO 20260922_0002 (Item 1) — Restrições Culturais/Religiosas,
  // mesma mecânica visual de Alergias (chips + seleção múltipla).
  const [restricoesCulturaisSelecionadas, setRestricoesCulturaisSelecionadas] = useState<Set<string>>(new Set());
  const [restricaoCulturalOutroTexto, setRestricaoCulturalOutroTexto] = useState('');

  // RELATÓRIO 20260922_0002 (Item 2) — Motor de Agregação de Smartwatch.
  const [janelaSmartwatch, setJanelaSmartwatch] = useState<{ data_inicio: string; data_fim: string } | null>(null);
  const [buscandoSmartwatch, setBuscandoSmartwatch] = useState(false);
  const [revisaoSmartwatch, setRevisaoSmartwatch] = useState<Database['public']['Functions']['processar_medias_smartwatch']['Returns'] | null>(null);

  // RELATÓRIO 20260922_0002 (Item 3) — Refeições Diárias Habituais + IA.
  const [refeicoesHabituais, setRefeicoesHabituais] = useState<LinhaRefeicaoHabitual[]>([]);

  useEffect(() => {
    void carregarCatalogos();
    void carregarHistoricoPeso();
    void carregarSexoBiologico();
    void carregarJanelaSmartwatch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pacienteId]);

  async function carregarSexoBiologico() {
    const { data, error } = await supabase.from('perfis_pacientes_vinculados').select('sexo_biologico').eq('id', pacienteId).maybeSingle();
    if (!error) setSexoBiologico(data?.sexo_biologico ?? null);
  }

  async function carregarJanelaSmartwatch() {
    const { data, error } = await supabase.rpc('iniciar_rascunho_anamnese', { p_usuario_id: pacienteId });
    if (!error && data) setJanelaSmartwatch(data.janela);
    // Erro aqui só some com o botão "Buscar dados do relógio" — nunca trava o resto da tela.
  }

  async function buscarDadosRelogio() {
    if (!janelaSmartwatch) return;
    setBuscandoSmartwatch(true);
    const { data, error } = await supabase.rpc('processar_medias_smartwatch', {
      p_usuario_id: pacienteId,
      p_data_inicio: janelaSmartwatch.data_inicio,
      p_data_fim: janelaSmartwatch.data_fim,
    });
    setBuscandoSmartwatch(false);
    if (error) {
      setToast({ variant: 'error', text: `Não foi possível buscar os dados do relógio: ${error.message}` });
      return;
    }
    setRevisaoSmartwatch(data);
  }

  function aplicarRevisaoSmartwatch(aceitos: {
    atividades: LinhaAtividade[];
    horasSono: string | null;
    horasCarga: string | null;
  }) {
    setLinhasAtividade((atual) => [...atual, ...aceitos.atividades]);
    setForm((atual) => ({
      ...atual,
      ...(aceitos.horasSono ? { horasSonoMedias: aceitos.horasSono } : {}),
      ...(aceitos.horasCarga ? { ativarBlocoAtleta: true, atletaHorasSemana: aceitos.horasCarga } : {}),
    }));
    setRevisaoSmartwatch(null);
  }

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

  async function carregarHistoricoPeso() {
    const { data, error } = await supabase.rpc('anamnese_historico_peso', { p_usuario_id: pacienteId });
    if (!error) setHistoricoPeso(data);
    // Erro aqui não impede o resto da tela — é só uma seção informativa.
  }

  const atividadesFiltradas = atividades.filter((a) => a.nome_exibicao.toLowerCase().includes(buscaAtividade.trim().toLowerCase()));

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

  function toggleRestricaoCultural(codigo: string) {
    setRestricoesCulturaisSelecionadas((atual) => {
      const novo = new Set(atual);
      if (novo.has(codigo)) novo.delete(codigo);
      else novo.add(codigo);
      return novo;
    });
  }

  /** RELATÓRIO 20260922_0002 (Item 3) — reutiliza o MESMO Edge Function/
   * contrato que o App já usa pro Método 1 (texto) do Registro de Refeição
   * (RELATÓRIO 20260824_0003, `RegistroRefeicaoIaService.interpretarTexto`)
   * — RESTRIÇÃO explícita: "não invente integrações novas do zero". */
  async function interpretarRefeicaoComIa(chave: string) {
    const linha = refeicoesHabituais.find((l) => l.chave === chave);
    if (!linha || !linha.descricaoTexto.trim()) return;

    setRefeicoesHabituais((atual) => atual.map((l) => (l.chave === chave ? { ...l, interpretando: true, erroIa: null } : l)));

    try {
      const { data: sessao } = await supabase.auth.getSession();
      const resposta = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/extract-metric-photo`, {
        method: 'POST',
        headers: {
          'Content-Type': 'text/plain; charset=utf-8',
          'X-Tipo-Aparelho': 'pratoRefeicaoTexto',
          apikey: import.meta.env.VITE_SUPABASE_ANON_KEY,
          ...(sessao.session ? { Authorization: `Bearer ${sessao.session.access_token}` } : {}),
        },
        body: linha.descricaoTexto.trim(),
      });

      if (!resposta.ok) {
        const corpo = await resposta.json().catch(() => null);
        throw new Error(corpo?.error ?? corpo?.message ?? `HTTP ${resposta.status}`);
      }

      const extracao = (await resposta.json()) as { itens: { calorias: number; proteinas_g: number; carboidratos_g: number; gorduras_g: number }[] };
      const somar = (selecionar: (i: (typeof extracao.itens)[number]) => number) =>
        extracao.itens.length === 0 ? null : Math.round(extracao.itens.reduce((soma, i) => soma + selecionar(i), 0) * 10) / 10;

      setRefeicoesHabituais((atual) =>
        atual.map((l) =>
          l.chave === chave
            ? {
                ...l,
                interpretando: false,
                kcal: somar((i) => i.calorias),
                proteinaG: somar((i) => i.proteinas_g),
                carboidratoG: somar((i) => i.carboidratos_g),
                gorduraG: somar((i) => i.gorduras_g),
              }
            : l,
        ),
      );
    } catch (e) {
      setRefeicoesHabituais((atual) =>
        atual.map((l) => (l.chave === chave ? { ...l, interpretando: false, erroIa: e instanceof Error ? e.message : 'Erro ao interpretar.' } : l)),
      );
    }
  }

  function ajustarQuantidadeRefeicoes(quantidade: number) {
    setRefeicoesHabituais((atual) => {
      const alvo = Math.max(0, Math.min(12, quantidade));
      if (alvo === atual.length) return atual;
      if (alvo < atual.length) return atual.slice(0, alvo);
      return [...atual, ...Array.from({ length: alvo - atual.length }, (_, i) => linhaRefeicaoVazia(atual.length + i + 1))];
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
        restricoes_culturais_religiosas: Array.from(restricoesCulturaisSelecionadas).map((codigo) =>
          codigo === 'outros' ? restricaoCulturalOutroTexto.trim() : ROTULO_RESTRICAO_CULTURAL[codigo],
        ).filter((texto): texto is string => Boolean(texto)),
        refeicoes_diarias_habituais: refeicoesHabituais
          .filter((l) => l.horario.trim() || l.descricaoTexto.trim())
          .map((l) => ({
            numero_refeicao: l.numeroRefeicao,
            ...(l.horario.trim() ? { horario: l.horario.trim() } : {}),
            fora_de_casa: l.foraDeCasa,
            ...(l.descricaoTexto.trim() ? { descricao_texto: l.descricaoTexto.trim() } : {}),
            ...(l.kcal !== null ? { kcal: l.kcal } : {}),
            ...(l.proteinaG !== null ? { proteina_g: l.proteinaG } : {}),
            ...(l.carboidratoG !== null ? { carboidrato_g: l.carboidratoG } : {}),
            ...(l.gorduraG !== null ? { gordura_g: l.gorduraG } : {}),
          })),
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
        bloco_idoso: form.ativarBlocoIdoso
          ? {
              perda_involuntaria_peso: form.idosoPerdaPeso,
              reducao_forca_mobilidade: form.idosoReducaoForcaMobilidade,
              dificuldade_alimentacao: form.idosoDificuldadeAlimentacao,
            }
          : null,
        bloco_recomposicao: form.ativarBlocoRecomposicao
          ? {
              percentual_gordura_atual: form.recomposicaoPercentualAtual,
              percentual_desejado: form.recomposicaoPercentualDesejado,
              treinamento_resistido: form.recomposicaoTreinamentoResistido,
            }
          : null,
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
    setRestricoesCulturaisSelecionadas(new Set());
    setRestricaoCulturalOutroTexto('');
    setRefeicoesHabituais([]);
    void data; // { sucesso: true, anamnese_id }
    void carregarHistoricoPeso();
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

      <HistoricoPesoResumo historico={historicoPeso} />

      <form onSubmit={(event) => void handleSubmit(event)} className="space-y-4">
        {/* RELATÓRIO 20260922_0002 (Item 1) — Sexo Biológico, movido pra
            ANTES do Motivo da Avaliação (pedido explícito), só leitura —
            "deve exibir a informação que já vem do Perfil do Usuário".
            Edição continua em `PatientDetails.tsx` (profissional_atualizar_sexo_biologico), não duplicada aqui. */}
        <div>
          <p className="text-xs font-medium text-slate-300">Sexo biológico</p>
          <p className="mt-1 text-sm text-slate-100">
            {sexoBiologico === 'M' ? 'Masculino' : sexoBiologico === 'F' ? 'Feminino' : 'Não informado no perfil'}
          </p>
        </div>

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
            <CampoNumerico
              id="anamnese-prof-refeicoes"
              label="Refeições/dia"
              value={form.numeroRefeicoes}
              disabled={salvando}
              onChange={(v) => {
                setForm((a) => ({ ...a, numeroRefeicoes: v }));
                ajustarQuantidadeRefeicoes(Number(v) || 0);
              }}
            />
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

        {/* RELATÓRIO 20260922_0002 (Item 1) — Restrições Culturais/
            Religiosas, mesma mecânica visual da Alergias (chips), catálogo
            ESTÁTICO (o banco guarda text[] livre, sem tabela-catálogo). */}
        <div>
          <p className="mb-1.5 text-xs font-medium text-slate-300">Restrições culturais/religiosas</p>
          <div className="flex flex-wrap gap-2">
            {Object.entries(ROTULO_RESTRICAO_CULTURAL).map(([codigo, rotulo]) => (
              <label
                key={codigo}
                className={`cursor-pointer rounded-lg border px-2.5 py-1 text-xs transition ${
                  restricoesCulturaisSelecionadas.has(codigo)
                    ? 'border-clinical-primary bg-clinical-primary/15 text-clinical-primary'
                    : 'border-clinical-border text-clinical-muted hover:text-slate-100'
                }`}
              >
                <input type="checkbox" className="sr-only" disabled={salvando} checked={restricoesCulturaisSelecionadas.has(codigo)} onChange={() => toggleRestricaoCultural(codigo)} />
                {rotulo}
              </label>
            ))}
          </div>
          {restricoesCulturaisSelecionadas.has('outros') && (
            <div className="mt-2">
              <CampoTexto
                id="anamnese-prof-restricao-cultural-outros"
                label="Descreva a restrição cultural/religiosa"
                value={restricaoCulturalOutroTexto}
                disabled={salvando}
                onChange={setRestricaoCulturalOutroTexto}
              />
            </div>
          )}
        </div>

        {/* RELATÓRIO 20260922_0002 (Item 3) — Refeições Diárias Habituais +
            IA. Reaproveita o mesmo Edge Function que o App já usa (ver
            `interpretarRefeicaoComIa`) — o texto livre vira calorias/macros,
            gravados em `refeicoes_diarias_habituais` (jsonb). */}
        <div>
          <p className="mb-1.5 text-xs font-medium text-slate-300">Refeições diárias habituais</p>
          <p className="mb-2 text-[10px] text-clinical-muted">
            Defina "Refeições/dia" acima pra abrir os campos de cada refeição. A IA interpreta o texto livre e calcula calorias/macros.
          </p>
          {refeicoesHabituais.length === 0 ? (
            <p className="text-xs text-clinical-muted">Informe o número de refeições por dia para começar.</p>
          ) : (
            <div className="space-y-2">
              {refeicoesHabituais.map((linha, indice) => (
                <div key={linha.chave} className="rounded-lg border border-clinical-border p-3">
                  <p className="mb-2 text-xs font-medium text-slate-300">Refeição {indice + 1}</p>
                  <div className="flex flex-wrap items-end gap-2">
                    <input
                      type="text"
                      placeholder="HH:mm"
                      disabled={salvando}
                      value={linha.horario}
                      onChange={(e) => setRefeicoesHabituais((a) => a.map((l) => (l.chave === linha.chave ? { ...l, horario: e.target.value } : l)))}
                      className="w-24 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                    />
                    <label className="flex items-center gap-1.5 text-xs text-slate-300">
                      <input
                        type="checkbox"
                        disabled={salvando}
                        checked={linha.foraDeCasa}
                        onChange={(e) => setRefeicoesHabituais((a) => a.map((l) => (l.chave === linha.chave ? { ...l, foraDeCasa: e.target.checked } : l)))}
                      />
                      Fora de casa
                    </label>
                    <input
                      type="text"
                      placeholder="Descreva a refeição (ex.: 2 fatias de pão, 1 ovo, café com leite)"
                      disabled={salvando}
                      value={linha.descricaoTexto}
                      onChange={(e) => setRefeicoesHabituais((a) => a.map((l) => (l.chave === linha.chave ? { ...l, descricaoTexto: e.target.value } : l)))}
                      className="min-w-[220px] flex-1 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                    />
                    <button
                      type="button"
                      disabled={salvando || linha.interpretando || !linha.descricaoTexto.trim()}
                      onClick={() => void interpretarRefeicaoComIa(linha.chave)}
                      className="rounded-lg border border-clinical-primary/40 px-2.5 py-1.5 text-[11px] font-medium text-clinical-primary transition hover:bg-clinical-primary/10 disabled:cursor-not-allowed disabled:opacity-60"
                    >
                      {linha.interpretando ? 'Interpretando...' : '✨ Interpretar com IA'}
                    </button>
                  </div>
                  {linha.erroIa && <p className="mt-1 text-[10px] text-clinical-critical">{linha.erroIa}</p>}
                  {linha.kcal !== null && (
                    <p className="mt-1 text-[10px] font-medium text-clinical-success">
                      {linha.kcal} kcal · P {linha.proteinaG}g · C {linha.carboidratoG}g · G {linha.gorduraG}g
                    </p>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>

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

        {/* RELATÓRIO 20260922_0002 (Item 2) — botão único cobrindo Atividade/
            Sono/Carga de Treino (processar_medias_smartwatch devolve as 3
            numa chamada só; o modal de revisão tem uma seção pra cada). */}
        {janelaSmartwatch && (
          <div className="rounded-lg border border-clinical-primary/40 bg-clinical-primary/10 p-3">
            <p className="text-xs font-medium text-clinical-primary">Buscar dados do relógio</p>
            <p className="mt-1 text-[10px] text-clinical-muted">
              Traz as médias de atividade, sono e carga de treino do smartwatch do paciente — você revisa e escolhe o que aceitar antes de qualquer coisa ser usada.
            </p>
            <button
              type="button"
              disabled={salvando || buscandoSmartwatch}
              onClick={() => void buscarDadosRelogio()}
              className="mt-2 rounded-lg border border-clinical-primary px-3 py-1.5 text-xs font-medium text-clinical-primary transition hover:bg-clinical-primary/10 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {buscandoSmartwatch ? 'Buscando...' : '⌚ Buscar dados do relógio'}
            </button>
          </div>
        )}

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
          {atividades.length > 8 && (
            <input
              type="text"
              placeholder="Buscar modalidade..."
              disabled={salvando}
              value={buscaAtividade}
              onChange={(event) => setBuscaAtividade(event.target.value)}
              className="mb-2 w-full max-w-xs rounded-lg border border-clinical-border bg-clinical-bg px-3 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
            />
          )}
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
                    {atividadesFiltradas.map((a) => (
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
        <BlocoCondicionalIdoso form={form} setForm={setForm} salvando={salvando} />
        <BlocoCondicionalRecomposicao form={form} setForm={setForm} salvando={salvando} />

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

      {revisaoSmartwatch && (
        <RevisaoSmartwatchModal
          resultado={revisaoSmartwatch}
          atividadesCatalogo={atividades}
          onFechar={() => setRevisaoSmartwatch(null)}
          onAplicar={aplicarRevisaoSmartwatch}
        />
      )}
    </div>
  );
}

const DIAS_SEMANA_ROTULO: Record<string, string> = { '0': 'Domingo', '1': 'Segunda', '2': 'Terça', '3': 'Quarta', '4': 'Quinta', '5': 'Sexta', '6': 'Sábado' };

/** RELATÓRIO 20260922_0002 (Item 2) — UX de Revisão: NADA aplicado até o
 * profissional clicar "Aplicar itens aceitos" — cada item pode ser
 * aceito/editado/excluído (checkbox + campo editável) antes disso. Sem %
 * de confiabilidade pra Atividades/Carga de Treino (o backend só calcula
 * isso pras métricas diárias, ver `processar_medias_smartwatch`) — não se
 * inventa um número que o backend não devolveu. */
function RevisaoSmartwatchModal({
  resultado,
  atividadesCatalogo,
  onFechar,
  onAplicar,
}: {
  resultado: Database['public']['Functions']['processar_medias_smartwatch']['Returns'];
  atividadesCatalogo: TipoAtividade[];
  onFechar: () => void;
  onAplicar: (aceitos: { atividades: LinhaAtividade[]; horasSono: string | null; horasCarga: string | null }) => void;
}) {
  const minutosSono = resultado.metricas_diarias.minutos_sono;
  const [aceitarSono, setAceitarSono] = useState(false);
  const [horasSono, setHorasSono] = useState(minutosSono.media !== null ? (minutosSono.media / 60).toFixed(1) : '');

  const [aceitarCarga, setAceitarCarga] = useState(false);
  const [horasCarga, setHorasCarga] = useState(resultado.carga_atleta.media_semanal_horas > 0 ? resultado.carga_atleta.media_semanal_horas.toFixed(1) : '');

  const itensAtividade = Object.entries(resultado.atividades_por_dia_semana).flatMap(([dia, itens]) =>
    itens
      .map((item) => ({ dia, item, tipo: atividadesCatalogo.find((a) => a.nome_codigo === item.modalidade) }))
      .filter((x): x is { dia: string; item: (typeof itens)[number]; tipo: TipoAtividade } => x.tipo !== undefined),
  );

  const [aceites, setAceites] = useState<Record<string, boolean>>(() =>
    Object.fromEntries(itensAtividade.map(({ dia, tipo }) => [`${dia}-${tipo.id}`, true])),
  );
  const [minutosEditados, setMinutosEditados] = useState<Record<string, string>>(() =>
    Object.fromEntries(itensAtividade.map(({ dia, item, tipo }) => [`${dia}-${tipo.id}`, Math.round(item.media_duracao_minutos_por_semana).toString()])),
  );
  const [intensidades, setIntensidades] = useState<Record<string, 'leve' | 'moderada' | 'alta'>>(() =>
    Object.fromEntries(itensAtividade.map(({ dia, tipo }) => [`${dia}-${tipo.id}`, 'moderada' as const])),
  );

  function aplicar() {
    const atividadesAceitas: LinhaAtividade[] = itensAtividade
      .filter(({ dia, tipo }) => aceites[`${dia}-${tipo.id}`])
      .map(({ dia, tipo }) => ({
        chave: crypto.randomUUID(),
        diaSemana: Number(dia),
        atividadeId: String(tipo.id),
        minutos: minutosEditados[`${dia}-${tipo.id}`] ?? '0',
        intensidade: intensidades[`${dia}-${tipo.id}`] ?? 'moderada',
      }));

    onAplicar({
      atividades: atividadesAceitas,
      horasSono: aceitarSono ? horasSono : null,
      horasCarga: aceitarCarga ? horasCarga : null,
    });
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
      <div className="max-h-[85vh] w-full max-w-2xl overflow-y-auto rounded-2xl border border-clinical-border bg-clinical-surface p-5">
        <h3 className="text-sm font-semibold text-slate-100">Revisar dados do relógio</h3>
        <p className="mt-1 text-xs text-clinical-muted">
          Nada aqui é salvo automaticamente. Marque "Aceitar" só no que quiser usar, edite se precisar, e clique em "Aplicar itens aceitos".
        </p>

        {/* Sono */}
        <div className="mt-4">
          <p className="text-xs font-medium text-slate-300">Sono e Recuperação</p>
          {minutosSono.media === null ? (
            <p className="mt-1 text-xs text-clinical-muted">Sem dados suficientes neste período.</p>
          ) : (
            <div className="mt-1 rounded-lg border border-clinical-border p-3">
              <div className="flex items-center justify-between">
                <span className="text-[11px] text-clinical-muted">
                  Confiabilidade:{' '}
                  <span className={confiabilidadeCor(minutosSono.percentual_confiabilidade)}>{minutosSono.percentual_confiabilidade.toFixed(0)}%</span>
                </span>
                <label className="flex items-center gap-1.5 text-xs text-slate-300">
                  Aceitar <input type="checkbox" checked={aceitarSono} onChange={(e) => setAceitarSono(e.target.checked)} />
                </label>
              </div>
              <input
                type="number"
                step="0.1"
                disabled={!aceitarSono}
                value={horasSono}
                onChange={(e) => setHorasSono(e.target.value)}
                className="mt-2 w-28 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1 text-xs text-slate-100 outline-none disabled:opacity-50"
              />{' '}
              <span className="text-xs text-clinical-muted">horas médias de sono</span>
            </div>
          )}
        </div>

        {/* Carga de Treino */}
        <div className="mt-4">
          <p className="text-xs font-medium text-slate-300">Carga de Treino</p>
          <p className="text-[10px] text-clinical-muted">O backend não calcula % de confiabilidade pra isto (só pras métricas diárias).</p>
          {resultado.carga_atleta.media_semanal_horas <= 0 ? (
            <p className="mt-1 text-xs text-clinical-muted">Sem dados suficientes neste período.</p>
          ) : (
            <div className="mt-1 rounded-lg border border-clinical-border p-3">
              <div className="flex items-center justify-between">
                <span className="text-[11px] text-clinical-muted">Média sobre {resultado.carga_atleta.semanas_no_periodo.toFixed(1)} semana(s) do período.</span>
                <label className="flex items-center gap-1.5 text-xs text-slate-300">
                  Aceitar <input type="checkbox" checked={aceitarCarga} onChange={(e) => setAceitarCarga(e.target.checked)} />
                </label>
              </div>
              <input
                type="number"
                step="0.1"
                disabled={!aceitarCarga}
                value={horasCarga}
                onChange={(e) => setHorasCarga(e.target.value)}
                className="mt-2 w-28 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1 text-xs text-slate-100 outline-none disabled:opacity-50"
              />{' '}
              <span className="text-xs text-clinical-muted">horas de treino/semana</span>
            </div>
          )}
        </div>

        {/* Atividades por dia da semana */}
        <div className="mt-4">
          <p className="text-xs font-medium text-slate-300">Atividades por dia da semana</p>
          <p className="text-[10px] text-clinical-muted">O backend não calcula % de confiabilidade pra isto (só pras métricas diárias).</p>
          {itensAtividade.length === 0 ? (
            <p className="mt-1 text-xs text-clinical-muted">Sem dados suficientes neste período.</p>
          ) : (
            <div className="mt-1 space-y-2">
              {itensAtividade.map(({ dia, item, tipo }) => {
                const chave = `${dia}-${tipo.id}`;
                return (
                  <div key={chave} className="rounded-lg border border-clinical-border p-3">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-medium text-slate-200">
                        {DIAS_SEMANA_ROTULO[dia]} · {tipo.nome_exibicao}
                      </span>
                      <label className="flex items-center gap-1.5 text-xs text-slate-300">
                        Aceitar <input type="checkbox" checked={aceites[chave] ?? false} onChange={(e) => setAceites((a) => ({ ...a, [chave]: e.target.checked }))} />
                      </label>
                    </div>
                    <p className="text-[10px] text-clinical-muted">
                      {item.ocorrencias_totais} ocorrência(s) em {item.semanas_do_periodo} semana(s) do período.
                    </p>
                    {aceites[chave] && (
                      <div className="mt-2 flex gap-2">
                        <input
                          type="number"
                          value={minutosEditados[chave] ?? ''}
                          onChange={(e) => setMinutosEditados((a) => ({ ...a, [chave]: e.target.value }))}
                          className="w-20 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1 text-xs text-slate-100 outline-none"
                        />
                        <select
                          value={intensidades[chave] ?? 'moderada'}
                          onChange={(e) => setIntensidades((a) => ({ ...a, [chave]: e.target.value as 'leve' | 'moderada' | 'alta' }))}
                          className="rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1 text-xs text-slate-100 outline-none"
                        >
                          <option value="leve">Leve</option>
                          <option value="moderada">Moderada</option>
                          <option value="alta">Alta</option>
                        </select>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>

        <div className="mt-5 flex justify-end gap-2">
          <button type="button" onClick={onFechar} className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted">
            Preencher manualmente
          </button>
          <button type="button" onClick={aplicar} className="rounded-lg bg-clinical-primary px-3 py-1.5 text-xs font-medium text-white">
            Aplicar itens aceitos
          </button>
        </div>
      </div>
    </div>
  );
}

function confiabilidadeCor(percentual: number): string {
  if (percentual > 70) return 'text-clinical-success';
  if (percentual >= 30) return 'text-clinical-warning';
  return 'text-clinical-critical';
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

function BlocoCondicionalIdoso({
  form,
  setForm,
  salvando,
}: {
  form: typeof FORM_VAZIO;
  setForm: React.Dispatch<React.SetStateAction<typeof FORM_VAZIO>>;
  salvando: boolean;
}) {
  return (
    <details className="rounded-lg border border-clinical-border p-3" open={form.ativarBlocoIdoso}>
      <summary className="cursor-pointer text-xs font-medium text-slate-300">
        <label className="inline-flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
          <input type="checkbox" disabled={salvando} checked={form.ativarBlocoIdoso} onChange={(e) => setForm((a) => ({ ...a, ativarBlocoIdoso: e.target.checked }))} />
          Bloco Idoso
        </label>
      </summary>
      {form.ativarBlocoIdoso && (
        <div className="mt-3 space-y-1">
          <label className="flex items-center gap-2 text-xs text-slate-300">
            <input type="checkbox" disabled={salvando} checked={form.idosoPerdaPeso} onChange={(e) => setForm((a) => ({ ...a, idosoPerdaPeso: e.target.checked }))} />
            Houve perda involuntária de peso?
          </label>
          <label className="flex items-center gap-2 text-xs text-slate-300">
            <input type="checkbox" disabled={salvando} checked={form.idosoReducaoForcaMobilidade} onChange={(e) => setForm((a) => ({ ...a, idosoReducaoForcaMobilidade: e.target.checked }))} />
            Houve redução importante de força ou mobilidade?
          </label>
          <label className="flex items-center gap-2 text-xs text-slate-300">
            <input type="checkbox" disabled={salvando} checked={form.idosoDificuldadeAlimentacao} onChange={(e) => setForm((a) => ({ ...a, idosoDificuldadeAlimentacao: e.target.checked }))} />
            Existe dificuldade para alimentação?
          </label>
        </div>
      )}
    </details>
  );
}

function BlocoCondicionalRecomposicao({
  form,
  setForm,
  salvando,
}: {
  form: typeof FORM_VAZIO;
  setForm: React.Dispatch<React.SetStateAction<typeof FORM_VAZIO>>;
  salvando: boolean;
}) {
  return (
    <details className="rounded-lg border border-clinical-border p-3" open={form.ativarBlocoRecomposicao}>
      <summary className="cursor-pointer text-xs font-medium text-slate-300">
        <label className="inline-flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
          <input type="checkbox" disabled={salvando} checked={form.ativarBlocoRecomposicao} onChange={(e) => setForm((a) => ({ ...a, ativarBlocoRecomposicao: e.target.checked }))} />
          Bloco Recomposição Corporal
        </label>
      </summary>
      {form.ativarBlocoRecomposicao && (
        <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
          <CampoNumerico id="bloco-recomp-atual" label="% gordura atual" value={form.recomposicaoPercentualAtual} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, recomposicaoPercentualAtual: v }))} />
          <CampoNumerico id="bloco-recomp-desejado" label="% gordura desejado" value={form.recomposicaoPercentualDesejado} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, recomposicaoPercentualDesejado: v }))} />
          <label className="flex items-center gap-2 self-end text-xs text-slate-300">
            <input
              type="checkbox"
              disabled={salvando}
              checked={form.recomposicaoTreinamentoResistido}
              onChange={(e) => setForm((a) => ({ ...a, recomposicaoTreinamentoResistido: e.target.checked }))}
            />
            Faz treinamento resistido?
          </label>
        </div>
      )}
    </details>
  );
}

/** Bloco 4 (Seção 7, RELATÓRIO 20260918_0002) — histórico de peso do
 * paciente, só leitura, via a RPC pura `anamnese_historico_peso`. */
function HistoricoPesoResumo({ historico }: { historico: Database['public']['Functions']['anamnese_historico_peso']['Returns'] | null }) {
  if (!historico || historico.peso_atual === null) return null;

  const itens: { label: string; valor: number | null }[] = [
    { label: 'Atual', valor: historico.peso_atual },
    { label: 'Anterior', valor: historico.peso_anterior },
    { label: 'Há 30 dias', valor: historico.peso_30_dias },
    { label: 'Há 3 meses', valor: historico.peso_3_meses },
    { label: 'Há 6 meses', valor: historico.peso_6_meses },
    { label: 'Há 12 meses', valor: historico.peso_12_meses },
    { label: 'Maior já registrado', valor: historico.maior_peso },
    { label: 'Menor já registrado', valor: historico.menor_peso },
  ];

  return (
    <div className="rounded-lg border border-clinical-border p-3">
      <p className="mb-2 text-xs font-medium text-slate-300">Histórico de Peso</p>
      <div className="flex flex-wrap gap-3">
        {itens
          .filter((item) => item.valor !== null)
          .map((item) => (
            <div key={item.label} className="text-xs text-clinical-muted">
              <span className="text-slate-300">{item.label}:</span> {item.valor} kg
            </div>
          ))}
        {historico.variacao_percentual !== null && (
          <div className="text-xs text-clinical-muted">
            <span className="text-slate-300">Variação:</span> {historico.variacao_percentual}%
          </div>
        )}
      </div>
    </div>
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
