const REQUEST_TIMEOUT_MS = 20_000;

export interface InvitePatientResult {
  success: boolean;
  /**
   * `true` quando já existia um vínculo vivo (pendente/ativo/em_carência)
   * entre este profissional e este paciente — `manage-professional-link` é
   * idempotente e devolve o vínculo existente (HTTP 200) em vez de duplicar
   * (HTTP 201 é só na primeira vez). O modal usa isto para distinguir "convite
   * enviado" de "convite já estava em andamento" na mensagem de sucesso.
   */
  alreadyInvited?: boolean;
  errorMessage?: string;
}

/**
 * Dispara `criar_vinculo` em `manage-professional-link` a partir do e-mail do
 * paciente — mesmo padrão Server-to-Server de `dispatchTrainingBlockToGarmin`
 * (garminApi.ts): `fetch` puro com `AbortController`/timeout, nunca
 * `supabase.functions.invoke` (não usado em nenhum lugar deste painel).
 *
 * Por que e-mail, e não UUID: a Edge Function historicamente exigia
 * `paciente_id` (UUID), mas o profissional só conhece o e-mail do paciente na
 * vida real — e `perfis_usuarios.email` está cifrado AES-256-GCM no cliente,
 * então não daria para buscar o UUID com uma query Postgrest direta contra
 * essa coluna. `manage-professional-link` foi estendida para aceitar
 * `paciente_email` e resolver o UUID internamente, com a service role, contra
 * `auth.users` (texto plano, gerido pelo GoTrue) — ver
 * `resolverPacienteIdPorEmail` em
 * supabase/functions/manage-professional-link/index.ts e a migration
 * `20260713210000_resolver_usuario_id_por_email.sql`. Este client nunca vê
 * nem precisa do UUID: envia só o e-mail e a intenção.
 */
export async function invitePatientByEmail(
  pacienteEmail: string,
  authToken: string,
  endpoint: string,
): Promise<InvitePatientResult> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${authToken}`,
      },
      body: JSON.stringify({ acao: 'criar_vinculo', paciente_email: pacienteEmail }),
      signal: controller.signal,
    });

    if (!response.ok) {
      return {
        success: false,
        errorMessage: (await mensagemDeErro(response)) ?? `Não foi possível enviar o convite (HTTP ${response.status}).`,
      };
    }

    return { success: true, alreadyInvited: response.status === 200 };
  } catch (error) {
    const timedOut = error instanceof DOMException && error.name === 'AbortError';
    return {
      success: false,
      errorMessage: timedOut
        ? 'Tempo esgotado ao enviar o convite.'
        : 'Erro de conexão ao enviar o convite.',
    };
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * `manage-professional-link` devolve `{ error: string }` com mensagens já
 * prontas para o profissional (ex. "Paciente não encontrado.",
 * "Apenas um profissional pode criar vínculos.") — repassadas como vieram, em
 * vez de um texto genérico, porque o critério de aceite pede exatamente esse
 * nível de especificidade.
 */
async function mensagemDeErro(response: Response): Promise<string | null> {
  try {
    const data = (await response.json()) as { error?: string };
    return data.error ?? null;
  } catch {
    return null;
  }
}
