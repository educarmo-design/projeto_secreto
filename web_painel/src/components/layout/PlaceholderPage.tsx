interface PlaceholderPageProps {
  titulo: string;
  descricao: string;
}

/** Placeholder para rotas do esqueleto de navegação ainda sem tela própria. */
export function PlaceholderPage({ titulo, descricao }: PlaceholderPageProps) {
  return (
    <div>
      <header className="mb-4">
        <h1 className="text-lg font-semibold text-slate-100">{titulo}</h1>
      </header>
      <div className="rounded-2xl border border-clinical-border bg-clinical-surface p-8 text-center">
        <p className="text-sm text-clinical-muted">{descricao}</p>
      </div>
    </div>
  );
}
