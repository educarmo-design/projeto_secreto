/**
 * RELATÓRIO 20260918_0001 — tabela de rastreabilidade de compliance entre
 * docs/motor_metabolico.txt e as 3 camadas do sistema (Backend/DB, App
 * Flutter, Painel Web). Conteúdo estático (não consulta o banco) —
 * reflete o estado do CÓDIGO na branch `feat/full-compliance-anamnese`,
 * mantido manualmente a cada tarefa que altera a Anamnese. A mesma tabela
 * também aparece no relatório da tarefa
 * (`docs/log_dev/20260918_0001_full_compliance_anamnese.md`).
 */
type Status = 'implementado' | 'parcial' | 'pendente' | 'n/a';

interface LinhaCompliance {
  bloco: string;
  referencia: string;
  descricao: string;
  backend: Status;
  app: Status;
  web: Status;
  /** Só preenchido quando alguma camada não está 100% "implementado". */
  planoOuNota?: string;
}

const LINHAS: LinhaCompliance[] = [
  { bloco: 'Bloco 1', referencia: 'Seção 4', descricao: 'Contexto da avaliação / Motivo', backend: 'implementado', app: 'implementado', web: 'implementado' },
  { bloco: 'Bloco 2', referencia: 'Seção 4.1/4.2/5', descricao: 'Objetivos (lista exata + secundários + meta quantitativa)', backend: 'implementado', app: 'implementado', web: 'implementado' },
  { bloco: 'Bloco 3', referencia: 'Seção 6', descricao: 'Antropometria (composição corporal completa)', backend: 'implementado', app: 'implementado', web: 'implementado' },
  {
    bloco: 'Bloco 4',
    referencia: 'Seção 7',
    descricao: 'Histórico de peso',
    backend: 'implementado',
    app: 'implementado',
    web: 'parcial',
    planoOuNota: 'RPC anamnese_historico_peso existe e está tipada no Painel, mas nenhuma tela do Web a chama ainda (só mostra o peso da versão selecionada no histórico, não os marcos de 30/90/180/365 dias). Plano: card dedicado em PatientDetails.tsx.',
  },
  { bloco: 'Bloco 5', referencia: 'Seção 8', descricao: 'Alimentação (padrão alimentar, sem duplicar o diário já existente)', backend: 'implementado', app: 'implementado', web: 'implementado' },
  {
    bloco: 'Bloco 6',
    referencia: 'Seção 9',
    descricao: 'Atividades e rotina semanal (intensidade obrigatória, alfabético, busca)',
    backend: 'implementado',
    app: 'implementado',
    web: 'parcial',
    planoOuNota: 'Intensidade obrigatória e ordem alfabética presentes; falta a barra de busca (o <select> simples foi considerado suficiente pro tamanho atual do catálogo). Plano: adicionar busca se o catálogo crescer muito.',
  },
  { bloco: 'Bloco 7', referencia: 'Seção 10', descricao: 'Sono e recuperação', backend: 'implementado', app: 'implementado', web: 'implementado' },
  { bloco: 'Bloco 8', referencia: 'Seção 11', descricao: 'Condições de saúde (Sim/Não explícito + lista exata)', backend: 'implementado', app: 'implementado', web: 'implementado' },
  { bloco: 'Alergias', referencia: '—', descricao: 'Catálogo com o padrão clínico pedido (Amendoim, Crustáceos, Glúten...)', backend: 'implementado', app: 'implementado', web: 'implementado' },
  { bloco: 'Bloco 9', referencia: 'Seção 12', descricao: 'Medicamentos', backend: 'implementado', app: 'implementado', web: 'implementado' },
  { bloco: 'Bloco 10', referencia: 'Seção 13', descricao: 'Suplementos', backend: 'implementado', app: 'implementado', web: 'implementado' },
  { bloco: 'Bloco 11', referencia: 'Seção 14', descricao: 'Exames laboratoriais', backend: 'implementado', app: 'implementado', web: 'implementado' },
  {
    bloco: 'Bloco 12',
    referencia: 'Seção 15-19',
    descricao: 'Blocos condicionais — Idoso, Atleta, Recomposição, Diabetes, Doença Renal',
    backend: 'implementado',
    app: 'implementado',
    web: 'parcial',
    planoOuNota: 'App ativa os 5 blocos automaticamente (idade/condição/objetivo). Painel Web só tem toggle manual para Atleta/Diabetes/Doença Renal — Idoso e Recomposição ainda sem UI dedicada lá (o backend já suporta os 5 via JSONB). Plano: adicionar os 2 toggles restantes ao formulário profissional.',
  },
  {
    bloco: 'Bloco 13',
    referencia: 'Seção 21',
    descricao: 'Resultados do Motor Metabólico (energia: TMB/TDEE por dia)',
    backend: 'parcial',
    app: 'implementado',
    web: 'implementado',
    planoOuNota: 'Snapshot de energia (TMB/TDEE) 100% implementado desde tarefas anteriores. Macronutrientes calculados (proteína/carbo/gordura por dia) NÃO implementados — o documento não especifica nenhuma fórmula de cálculo automático de macros, e o projeto nunca arbitra número clínico sem fórmula explícita do fundador. Plano: aguardar definição da fórmula.',
  },
  { bloco: 'Bloco 14', referencia: 'Seção 22', descricao: 'Metas (resultado do sistema × meta profissional, nunca sobrescreve)', backend: 'implementado', app: 'implementado', web: 'implementado' },
  {
    bloco: 'Bloco 15',
    referencia: 'Seção 25',
    descricao: 'Qualidade e exceções (score, dados faltantes/inconsistentes)',
    backend: 'parcial',
    app: 'pendente',
    web: 'pendente',
    planoOuNota: 'Coluna anamneses.qualidade_dados (jsonb) criada e pronta, mas nenhum algoritmo de scoring foi implementado — o documento não fornece a fórmula. Plano: definir o algoritmo com o fundador antes de expor isso em qualquer tela.',
  },
  { bloco: 'Bloco 16', referencia: 'Seção 26', descricao: 'Auditoria e versionamento (número de versão, dados confirmados)', backend: 'implementado', app: 'implementado', web: 'implementado' },
  {
    bloco: 'Seção 11',
    referencia: '—',
    descricao: 'Tela "Confirme seus dados" antes de enviar ao motor',
    backend: 'implementado',
    app: 'implementado',
    web: 'parcial',
    planoOuNota: 'App tem uma tela dedicada de revisão final (ConfirmarAnamnesePage) antes de gravar. Painel Web grava com confirmação implícita no próprio submit do formulário (dados_confirmados=true), sem uma 2ª tela de revisão — decisão de escopo desta tarefa, dado que o profissional já revisa visualmente o formulário antes de enviar.',
  },
  {
    bloco: 'UX Global',
    referencia: '—',
    descricao: 'Confirmação explícita ("Confirmar"/"OK") ao recolher listas/bottom sheets',
    backend: 'n/a',
    app: 'implementado',
    web: 'n/a',
    planoOuNota: 'Pedido específico de UX mobile (bottom sheets). O Painel Web usa formulário denso tradicional com seções <details> colapsáveis, não bottom sheets — não se aplica da mesma forma.',
  },
  { bloco: 'Regra de arquitetura', referencia: 'Seção 18/28', descricao: 'Perguntas mínimas → Confirmado → Anamnese versionada → Motor → Resultado → Meta', backend: 'implementado', app: 'implementado', web: 'implementado' },
];

const ROTULO_STATUS: Record<Status, string> = {
  implementado: 'Implementado',
  parcial: 'Parcial',
  pendente: 'Pendente',
  'n/a': 'N/A',
};

const COR_STATUS: Record<Status, string> = {
  implementado: 'bg-clinical-success/15 text-clinical-success',
  parcial: 'bg-clinical-warning/15 text-clinical-warning',
  pendente: 'bg-clinical-critical/15 text-clinical-critical',
  'n/a': 'bg-clinical-border/40 text-clinical-muted',
};

function Badge({ status }: { status: Status }) {
  return <span className={`inline-block rounded-full px-2 py-0.5 text-[11px] font-medium ${COR_STATUS[status]}`}>{ROTULO_STATUS[status]}</span>;
}

export function AdminComplianceAnamnese() {
  const total = LINHAS.length;
  const totalImplementadoTudo = LINHAS.filter((l) => l.backend === 'implementado' && l.app === 'implementado' && (l.web === 'implementado' || l.web === 'n/a')).length;

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-lg font-semibold text-slate-100">Compliance — Anamnese × docs/motor_metabolico.txt</h1>
        <p className="mt-1 text-sm text-clinical-muted">
          Rastreabilidade item a item entre a especificação (Blocos 1-16) e o que está implementado em cada camada.{' '}
          {totalImplementadoTudo}/{total} itens 100% completos nas 3 camadas — os demais têm nota/plano explícito.
        </p>
      </div>

      <div className="overflow-x-auto rounded-2xl border border-clinical-border bg-clinical-surface">
        <table className="w-full text-left text-sm">
          <thead className="text-xs uppercase text-clinical-muted">
            <tr>
              <th className="px-4 py-2">Bloco</th>
              <th className="px-4 py-2">Ref.</th>
              <th className="px-4 py-2">Descrição</th>
              <th className="px-4 py-2">Backend</th>
              <th className="px-4 py-2">App</th>
              <th className="px-4 py-2">Web</th>
            </tr>
          </thead>
          <tbody>
            {LINHAS.map((linha) => (
              <tr key={`${linha.bloco}-${linha.descricao}`} className="border-t border-clinical-border align-top">
                <td className="px-4 py-2 font-medium text-slate-200">{linha.bloco}</td>
                <td className="px-4 py-2 font-mono text-xs text-clinical-muted">{linha.referencia}</td>
                <td className="px-4 py-2 text-slate-300">
                  {linha.descricao}
                  {linha.planoOuNota && <p className="mt-1 text-[11px] text-clinical-muted">{linha.planoOuNota}</p>}
                </td>
                <td className="px-4 py-2">
                  <Badge status={linha.backend} />
                </td>
                <td className="px-4 py-2">
                  <Badge status={linha.app} />
                </td>
                <td className="px-4 py-2">
                  <Badge status={linha.web} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
