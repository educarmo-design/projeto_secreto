/// RELATÓRIO 20260922_0002 (Item 5 — Widget de Notificação e Bloqueio de
/// Validade) — lógica PURA (sem Flutter) de cálculo do estado de validade
/// da anamnese, a partir de `anamneses.data_validade` (RELATÓRIO
/// 20260922_0001). Compartilhada entre [AnamneseValidadeBanner] (Dashboard)
/// e o bloqueio de `MetaBemEstarPage` — um único lugar decide os limiares.
enum AnamneseValidadeNivel {
  /// Mais de 7 dias pra vencer, ou sem anamnese vigente ainda — nenhum alerta.
  ok,

  /// De 7 dias antes até o dia do vencimento (inclusive) — alerta amarelo,
  /// dispensável.
  lembrete,

  /// Vencida há 1 a 39 dias — alerta laranja, dispensável. A mensagem
  /// sempre mostra o número exato de dias de atraso (não só nos "marcos"
  /// de 10/20/30 citados como exemplo na tarefa — um usuário que abre o
  /// app no dia 15 de atraso também precisa ver o aviso, não só em datas
  /// específicas).
  atrasada,

  /// Vencida há 40 dias ou mais — bloqueio severo: alerta vermelho, NÃO
  /// dispensável, e [MetaBemEstarPage] bloqueia o acesso às metas.
  bloqueada,
}

class AnamneseValidadeStatus {
  final AnamneseValidadeNivel nivel;

  /// Dias restantes até o vencimento (`nivel == ok/lembrete`) ou dias de
  /// atraso (`nivel == atrasada/bloqueada`) — sempre um número >= 0.
  final int dias;

  const AnamneseValidadeStatus({required this.nivel, required this.dias});

  static const diasLembrete = 7;
  static const diasBloqueio = 40;

  /// [dataValidade] nulo (sem anamnese vigente, ou anamnese sem validade
  /// calculada) → sempre [AnamneseValidadeNivel.ok] (nada a bloquear pra
  /// quem nunca preencheu uma anamnese; essa é uma responsabilidade de
  /// outra trava, não desta). [agora] injetável só para teste.
  factory AnamneseValidadeStatus.calcular(DateTime? dataValidade, {DateTime? agora}) {
    if (dataValidade == null) {
      return const AnamneseValidadeStatus(nivel: AnamneseValidadeNivel.ok, dias: 0);
    }

    final hoje = agora ?? DateTime.now();
    final diasParaVencer = dataValidade.difference(hoje).inDays;

    if (diasParaVencer > diasLembrete) {
      return AnamneseValidadeStatus(nivel: AnamneseValidadeNivel.ok, dias: diasParaVencer);
    }
    if (diasParaVencer >= 0) {
      return AnamneseValidadeStatus(nivel: AnamneseValidadeNivel.lembrete, dias: diasParaVencer);
    }

    final diasAtraso = -diasParaVencer;
    if (diasAtraso >= diasBloqueio) {
      return AnamneseValidadeStatus(nivel: AnamneseValidadeNivel.bloqueada, dias: diasAtraso);
    }
    return AnamneseValidadeStatus(nivel: AnamneseValidadeNivel.atrasada, dias: diasAtraso);
  }

  bool get exigeAlerta => nivel != AnamneseValidadeNivel.ok;
  bool get podeDispensar => nivel == AnamneseValidadeNivel.lembrete || nivel == AnamneseValidadeNivel.atrasada;
}
