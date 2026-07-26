import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase, type ProfissionalAutenticado } from '@/core/supabase';
import { Toast, type ToastMessage } from '@/components/Toast';
import { InvitePatientModal } from './InvitePatientModal';

interface PatientListProps {
  profissional: ProfissionalAutenticado;
}

interface PacienteResumo {
  id: string;
  nickname: string | null;
  faixaEtaria: string;
  regiao: string;
  /**
   * Placeholder até o HealthScore (`HealthScoreEngine`, app mobile/Dart)
   * ser espelhado no lado do servidor e persistido em algum lugar que o
   * painel web possa ler diretamente — hoje usamos `pontuacao_ranking`
   * (`progresso_gamificacao`) como a aproximação numérica mais próxima já
   * disponível via RLS. Rotulado explicitamente como aproximado na UI.
   */
  pontuacaoAproximada: number | null;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

/**
 * Prontuário Anonimizado LGPD.
 *
 * Regra de Blindagem: quando `profissional.ehSeguradora`, a tabela NUNCA
 * renderiza `nickname` (o único identificador "nominal-adjacent" que esta
 * lista teria acesso a exibir) nem um link de navegação para
 * `PatientDetails`/`GarminPrescriptionForm` — auditoria de sinistros só
 * enxerga UUID anônimo, Idade Macro, Região e a pontuação agregada do
 * grupo, nunca a ficha clínica bruta de um indivíduo.
 *
 * Nota de escopo (documentada, não escondida): esta lista só mostra
 * pacientes com quem O PROFISSIONAL LOGADO tem um vínculo ATIVO em
 * `vinculos_profissional_paciente` (F.2) — correto para
 * Médico/Nutricionista (a relação de cuidado É o vínculo), mas insuficiente
 * para o caso de uso real de uma Auditoria de Seguradora (que precisaria
 * enxergar todo um pool de apólices, não pacientes vinculados a ela mesma).
 * Sem uma tabela de vínculo seguradora↔apólice↔paciente (que não existe
 * neste schema ainda), a alternativa seria uma policy de RLS ampla demais —
 * e por Zero Trust é preferível esta lista ficar vazia para contas de
 * seguradora até essa modelagem existir, a abrir acesso amplo por padrão.
 * (Continua vazia de graça: uma seguradora nunca tem linha própria em
 * `vinculos_profissional_paciente`, então a `WHERE EXISTS` da view abaixo
 * já devolve zero linhas pra ela, sem nenhum caso especial no código.)
 *
 * Correção (achado da integração de Vínculos, ver RELATÓRIO): esta tela
 * lia a lista de IDs de `planejamento_clinico` — a fonte de autorização
 * ANTIGA, substituída por `vinculos_profissional_paciente` desde a
 * unificação do Zero Trust (20260713140000). Um paciente que aceitasse um
 * convite só aparecia aqui se o profissional TAMBÉM registrasse uma
 * prescrição — o vínculo sozinho não bastava, mesmo já sendo a autorização
 * real. Corrigido: `perfis_pacientes_vinculados` (abaixo) já é, ela mesma,
 * a fonte de verdade — a view só devolve linha para quem tem vínculo ATIVO
 * com `auth.uid()` (ver `create or replace view` em 20260713140000), então
 * não existe mais nenhum passo prévio de buscar IDs em outro lugar.
 */
export function PatientList({ profissional }: PatientListProps) {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [pacientes, setPacientes] = useState<PacienteResumo[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [modalConviteAberto, setModalConviteAberto] = useState(false);
  const [toast, setToast] = useState<ToastMessage | null>(null);

  useEffect(() => {
    let cancelado = false;

    async function carregar() {
      setEstado('carregando');
      setMensagemErro(null);

      // `perfis_pacientes_vinculados` (não `perfis_usuarios` diretamente) —
      // a view criada na migration deste ONDA 3, que só expõe as 4 colunas
      // não-sensíveis. Nenhum filtro por `profissional.id` é necessário
      // aqui: a própria view só devolve linha para quem tem vínculo ATIVO
      // com `auth.uid()` (a sessão atual) — a autorização já está embutida
      // na `WHERE EXISTS` da view, não é responsabilidade deste componente
      // reconstruí-la buscando IDs em outra tabela antes.
      const { data: perfis, error: erroPerfis } = await supabase
        .from('perfis_pacientes_vinculados')
        .select('id, nickname, data_nascimento, geo_ranking_id');

      if (cancelado) return;
      if (erroPerfis) {
        setEstado('erro');
        setMensagemErro(erroPerfis.message);
        return;
      }

      if (!perfis || perfis.length === 0) {
        setPacientes([]);
        setEstado('sucesso');
        return;
      }

      const idsUnicos = perfis.map((p) => p.id);
      const { data: progresso, error: erroProgresso } = await supabase
        .from('progresso_gamificacao')
        .select('usuario_id_anonimo, pontuacao_ranking')
        .in('usuario_id_anonimo', idsUnicos);

      if (cancelado) return;
      if (erroProgresso) {
        setEstado('erro');
        setMensagemErro(erroProgresso.message);
        return;
      }

      const pontuacaoPorId = new Map<string, number>(
        (progresso ?? []).map((p): [string, number] => [
          p.usuario_id_anonimo,
          p.pontuacao_ranking,
        ]),
      );

      const resumos: PacienteResumo[] = perfis.map((perfil) => ({
        id: perfil.id,
        nickname: perfil.nickname,
        faixaEtaria: calcularFaixaEtaria(perfil.data_nascimento),
        regiao: perfil.geo_ranking_id ?? 'desconhecida',
        pontuacaoAproximada: pontuacaoPorId.get(perfil.id) ?? null,
      }));

      setPacientes(resumos);
      setEstado('sucesso');
    }

    void carregar();
    return () => {
      cancelado = true;
    };
  }, [profissional.id]);

  const ehSeguradora = profissional.ehSeguradora;

  if (estado === 'carregando') {
    return <p className="text-clinical-muted">Carregando pacientes...</p>;
  }

  if (estado === 'erro') {
    return (
      <div
        role="alert"
        className="rounded-xl border border-clinical-critical/40 bg-clinical-critical/10 p-4 text-clinical-critical"
      >
        Erro ao carregar pacientes: {mensagemErro}
      </div>
    );
  }

  return (
    <div>
      <header className="mb-4 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-lg font-semibold text-slate-100">
            {ehSeguradora ? 'Auditoria de Sinistros — Grupo Anonimizado' : 'Meus Pacientes'}
          </h1>
          <p className="text-sm text-clinical-muted">
            {ehSeguradora
              ? 'Visão agregada e anonimizada — sem dados nominais.'
              : `${pacientes.length} paciente(s) com vínculo ativo.`}
          </p>
        </div>
        {/* Blindagem LGPD (mesma regra do restante desta tela): Auditoria de
            Seguradora nunca cria vínculo nominal com um paciente individual —
            só enxerga o pool agregado e anonimizado. */}
        {!ehSeguradora && (
          <button
            type="button"
            onClick={() => setModalConviteAberto(true)}
            className="shrink-0 rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600"
          >
            Convidar Paciente
          </button>
        )}
      </header>

      {modalConviteAberto && (
        <InvitePatientModal
          onClose={() => setModalConviteAberto(false)}
          onSuccess={(pacienteEmail, alreadyInvited) => {
            setModalConviteAberto(false);
            setToast({
              variant: 'success',
              text: alreadyInvited
                ? `Este paciente (${pacienteEmail}) já tinha um convite em andamento.`
                : 'Convite enviado. A aguardar autorização do paciente.',
            });
          }}
        />
      )}

      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      {pacientes.length === 0 ? (
        <p className="text-sm text-clinical-muted">Nenhum paciente vinculado ainda.</p>
      ) : (
        <div className="overflow-x-auto rounded-2xl border border-clinical-border bg-clinical-surface">
          <table className="w-full text-left text-sm">
            <thead className="text-xs uppercase text-clinical-muted">
              <tr>
                {!ehSeguradora && <th className="px-4 py-3">Apelido</th>}
                <th className="px-4 py-3">UUID Anônimo</th>
                <th className="px-4 py-3">Idade Macro</th>
                <th className="px-4 py-3">Região</th>
                <th className="px-4 py-3">HealthScore (aprox.)</th>
                {!ehSeguradora && <th className="px-4 py-3" />}
              </tr>
            </thead>
            <tbody>
              {pacientes.map((paciente) => (
                <tr key={paciente.id} className="border-t border-clinical-border">
                  {!ehSeguradora && (
                    <td className="px-4 py-3 text-slate-200">{paciente.nickname ?? '—'}</td>
                  )}
                  <td className="px-4 py-3 font-mono text-xs text-slate-300">{paciente.id}</td>
                  <td className="px-4 py-3 text-slate-300">{paciente.faixaEtaria}</td>
                  <td className="px-4 py-3 text-slate-300">{paciente.regiao}</td>
                  <td className="px-4 py-3 text-slate-300">
                    {paciente.pontuacaoAproximada ?? '—'}
                  </td>
                  {!ehSeguradora && (
                    <td className="px-4 py-3 text-right">
                      <Link
                        to={`/pacientes/${paciente.id}`}
                        className="text-clinical-primary hover:underline"
                      >
                        Ver detalhes
                      </Link>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

/**
 * Mesma regra de bucketização usada em `B2BAnalyticsPayload` (app mobile,
 * Dart) — deliberadamente idêntica nas duas plataformas para que a mesma
 * data de nascimento sempre caia na mesma faixa, não importa qual sistema
 * calculou.
 */
function calcularFaixaEtaria(dataNascimentoIso: string | null): string {
  if (!dataNascimentoIso) return 'desconhecida';

  const nascimento = new Date(dataNascimentoIso);
  const hoje = new Date();
  let idade = hoje.getFullYear() - nascimento.getFullYear();
  const aindaNaoFezAniversarioEsteAno =
    hoje.getMonth() < nascimento.getMonth() ||
    (hoje.getMonth() === nascimento.getMonth() && hoje.getDate() < nascimento.getDate());
  if (aindaNaoFezAniversarioEsteAno) idade -= 1;

  if (idade < 18) return '<18';
  if (idade < 25) return '18-24';
  if (idade < 35) return '25-34';
  if (idade < 45) return '35-44';
  if (idade < 55) return '45-54';
  if (idade < 65) return '55-64';
  return '65+';
}
