import type { PlanoTreinoEstrutura } from '@/core/types/database';

export interface GarminTrainingDispatchPayload {
  planejamentoClinicoId: string;
  pacienteIdAnonimo: string;
  estrutura: PlanoTreinoEstrutura;
}

export interface GarminDispatchResult {
  success: boolean;
  garminWorkoutId?: string;
  errorMessage?: string;
}

const REQUEST_TIMEOUT_MS = 20_000;

/**
 * Despacho Server-to-Server do bloco de treino prescrito para a Garmin
 * Training API — Custo R$ 0 (PRD): a Garmin Training API (Health API
 * partner program) não cobra por integração homologada, e não há nenhum
 * provedor pago no meio deste caminho.
 *
 * Zero Trust: as credenciais OAuth2 de parceiro Garmin (client secret,
 * tokens de longa duração por atleta) NUNCA podem viver neste bundle
 * JavaScript que roda no navegador do profissional — qualquer segredo
 * aqui seria visível a qualquer um com o DevTools aberto. Por isso esta
 * função só conhece [VITE_GARMIN_DISPATCH_ENDPOINT], uma Supabase Edge
 * Function própria que guarda essas credenciais do lado do servidor e
 * conversa com a Garmin em nome do app — o mesmo padrão de gateway já
 * usado no app mobile para o Gemini (`GeminiGatewayService`), agora
 * espelhado aqui para a Garmin. A implementação da Edge Function em si
 * (o handshake OAuth2 com a Garmin) está fora do escopo deste front-end.
 *
 * A resposta chega ao pulso do usuário através do fluxo padrão da Garmin
 * (push da Training API para o Garmin Connect do atleta, sincronizado ao
 * relógio na próxima conexão) — não é este método que "empurra" para o
 * hardware diretamente.
 */
export async function dispatchTrainingBlockToGarmin(
  payload: GarminTrainingDispatchPayload,
  authToken: string,
  endpoint: string,
): Promise<GarminDispatchResult> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${authToken}`,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    if (!response.ok) {
      return {
        success: false,
        errorMessage: `Garmin recusou o despacho (HTTP ${response.status}).`,
      };
    }

    const data = (await response.json()) as { garmin_workout_id?: string };
    return { success: true, garminWorkoutId: data.garmin_workout_id };
  } catch (error) {
    const timedOut = error instanceof DOMException && error.name === 'AbortError';
    return {
      success: false,
      errorMessage: timedOut
        ? 'Tempo esgotado ao despachar o treino para a Garmin.'
        : 'Erro de conexão ao despachar o treino para a Garmin.',
    };
  } finally {
    clearTimeout(timeoutId);
  }
}
