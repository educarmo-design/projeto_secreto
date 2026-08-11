import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '@/core/supabase';

interface Alimento {
  id: string;
  nomeTaco: string;
  fonte: string;
  caloriasKcal100g: number;
  proteinasG100g: number;
  carboidratosG100g: number;
  gordurasG100g: number;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

const LIMITE_RESULTADOS = 50;

/**
 * N06 (RELATÓRIO 20260811_0005) — manutenção de `alimentos_referencia`.
 *
 * DECISÃO DELIBERADA: esta tela é SÓ BUSCA/LISTAGEM, sem criar/editar/
 * remover — ao contrário de `AdminAtividadesFisicas`/`AdminAlergias`. Dois
 * motivos, ambos verificados na migration original
 * (`20260716120000_alimentos_referencia_taco.sql`), não presumidos:
 *   1. A tabela tem RLS DELIBERADAMENTE sem policy de escrita para
 *      `authenticated` ("curadoria é migration/service role", comentário
 *      original) — abrir escrita aqui reverteria essa decisão de projeto
 *      sem essa reversão ter sido pedida explicitamente nesta tarefa.
 *   2. `nome_taco`/`aliases` alimentam embeddings semânticos
 *      (`cache_sinonimos_alimentos`, busca via Edge Function `search-food`)
 *      — editar via UPDATE direto no Postgres NÃO recalcula o embedding
 *      correspondente, deixando o índice vetorial desatualizado/mentiroso
 *      até um job de re-embed rodar (fora do escopo desta tela).
 * Se o fundador quiser CRUD completo aqui, essas duas questões precisam de
 * uma decisão explícita antes (nova policy de RLS + pipeline de re-embed
 * acoplado à escrita, não só a tela).
 */
export function AdminAlimentos() {
  const [estado, setEstado] = useState<EstadoTela>('sucesso');
  const [busca, setBusca] = useState('');
  const [alimentos, setAlimentos] = useState<Alimento[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [totalAproximado, setTotalAproximado] = useState<number | null>(null);

  useEffect(() => {
    void buscar('');
  }, []);

  async function buscar(termo: string) {
    setEstado('carregando');

    let query = supabase
      .from('alimentos_referencia')
      .select(
        'id, nome_taco, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g',
        { count: 'exact' },
      )
      .order('nome_taco', { ascending: true })
      .limit(LIMITE_RESULTADOS);

    if (termo.trim()) {
      query = query.ilike('nome_taco', `%${termo.trim()}%`);
    }

    const { data, error, count } = await query;

    if (error) {
      setEstado('erro');
      setMensagemErro(error.message);
      return;
    }

    setAlimentos(
      (data ?? []).map((linha) => ({
        id: linha.id,
        nomeTaco: linha.nome_taco,
        fonte: linha.fonte,
        caloriasKcal100g: linha.calorias_kcal_100g,
        proteinasG100g: linha.proteinas_g_100g,
        carboidratosG100g: linha.carboidratos_g_100g,
        gordurasG100g: linha.gorduras_g_100g,
      })),
    );
    setTotalAproximado(count);
    setEstado('sucesso');
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void buscar(busca);
  }

  return (
    <div>
      <header className="mb-6">
        <h1 className="text-lg font-semibold text-slate-100">Alimentos</h1>
        <p className="text-sm text-clinical-muted">
          Catálogo de referência (TACO/USDA) — {totalAproximado ?? '—'} no total, busca por nome.
        </p>
      </header>

      <form onSubmit={handleSubmit} className="mb-6 flex gap-3">
        <input
          type="search"
          value={busca}
          onChange={(event) => setBusca(event.target.value)}
          placeholder="Buscar por nome (ex.: arroz)"
          className="flex-1 rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary"
        />
        <button
          type="submit"
          className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600"
        >
          Buscar
        </button>
      </form>

      {estado === 'carregando' && <p className="text-clinical-muted">Buscando...</p>}
      {estado === 'erro' && (
        <div role="alert" className="rounded-xl border border-clinical-critical/40 bg-clinical-critical/10 p-4 text-clinical-critical">
          Erro ao buscar: {mensagemErro}
        </div>
      )}
      {estado === 'sucesso' && (
        <div className="overflow-x-auto rounded-2xl border border-clinical-border bg-clinical-surface">
          <table className="w-full text-left text-sm">
            <thead className="text-xs uppercase text-clinical-muted">
              <tr>
                <th className="px-4 py-3">Nome</th>
                <th className="px-4 py-3">Fonte</th>
                <th className="px-4 py-3">kcal/100g</th>
                <th className="px-4 py-3">Proteína g/100g</th>
                <th className="px-4 py-3">Carbo g/100g</th>
                <th className="px-4 py-3">Gordura g/100g</th>
              </tr>
            </thead>
            <tbody>
              {alimentos.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-6 text-center text-clinical-muted">
                    Nenhum alimento encontrado.
                  </td>
                </tr>
              ) : (
                alimentos.map((alimento) => (
                  <tr key={alimento.id} className="border-t border-clinical-border">
                    <td className="px-4 py-3 text-slate-200">{alimento.nomeTaco}</td>
                    <td className="px-4 py-3 uppercase text-slate-300">{alimento.fonte}</td>
                    <td className="px-4 py-3 text-slate-300">{alimento.caloriasKcal100g}</td>
                    <td className="px-4 py-3 text-slate-300">{alimento.proteinasG100g}</td>
                    <td className="px-4 py-3 text-slate-300">{alimento.carboidratosG100g}</td>
                    <td className="px-4 py-3 text-slate-300">{alimento.gordurasG100g}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
          {alimentos.length === LIMITE_RESULTADOS && (
            <p className="border-t border-clinical-border px-4 py-3 text-xs text-clinical-muted">
              Mostrando os primeiros {LIMITE_RESULTADOS} resultados — refine a busca para ver mais.
            </p>
          )}
        </div>
      )}
    </div>
  );
}
