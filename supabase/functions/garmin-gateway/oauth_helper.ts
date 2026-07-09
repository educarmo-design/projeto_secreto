// Assinador OAuth 1.0a para a Garmin Training API.
//
// A Garmin Health/Training API (partner program) ainda usa OAuth 1.0a, não
// OAuth 2.0 — cada requisição precisa de um cabeçalho `Authorization: OAuth
// ...` assinado com HMAC-SHA1, combinando a Consumer Key/Secret do app
// (uma por integração, salva em `GARMIN_CONSUMER_KEY`/`GARMIN_CONSUMER_SECRET`
// nas variáveis de ambiente do Supabase — nunca no código) com o Access
// Token/Secret daquele ALUNO específico (obtido no fluxo de consentimento
// OAuth1 three-legged, armazenado em `garmin_conexoes`).
//
// Toda a lógica de assinatura vive isolada aqui, longe de index.ts, para
// que a parte criptográfica possa ser lida/revisada — e testada
// (index_test.ts) — como uma unidade só.
//
// `buildSignatureBaseString`, `sign` e `percentEncode` são expostos
// publicamente (não só `buildAuthorizationHeader`) de propósito: são as
// três etapas mecânicas do RFC 5849 que dá pra verificar cada uma
// isoladamente — a primeira por inspeção literal da string produzida, a
// segunda por comparação contra um cálculo HMAC-SHA1 independente (mesma
// Web Crypto API, chamada separadamente no teste), a terceira por casos de
// caractere especial pontuais (`! * ' ( )`, o gotcha clássico de
// `encodeURIComponent`).

/** Credenciais necessárias para assinar uma requisição — a combinação "app" (consumer) + "aluno" (access token). */
export interface GarminCredentials {
  consumerKey: string;
  consumerSecret: string;
  /** Token OAuth1 do ALUNO — nunca um token de app/serviço. */
  accessToken: string;
  /** Segredo pareado ao `accessToken` acima. */
  accessTokenSecret: string;
}

interface AssinarRequisicaoParams {
  method: 'GET' | 'POST';
  url: string;
  credentials: GarminCredentials;
  /**
   * Parâmetros de query string, se houver. OAuth 1.0a assina apenas
   * parâmetros de URL/form — nunca o corpo JSON de um POST, por
   * especificação (RFC 5849 §3.4.1.3) — então um corpo JSON não entra
   * aqui, mesmo que a requisição tenha um body.
   */
  extraParams?: Record<string, string>;
  /** Override para testes determinísticos — se omitido, gera um nonce aleatório novo a cada chamada (uso real em produção). */
  nonce?: string;
  /** Override para testes determinísticos — se omitido, usa o timestamp Unix atual (uso real em produção). */
  timestamp?: string;
}

/**
 * Utilitário de assinatura OAuth 1.0a.
 */
export class OAuth1Signer {
  /**
   * Monta o cabeçalho `Authorization: OAuth ...` completo, pronto para uso
   * em `fetch(url, { headers: { Authorization: ... } })`.
   */
  static async buildAuthorizationHeader(params: AssinarRequisicaoParams): Promise<string> {
    const { method, url, credentials, extraParams = {}, nonce, timestamp } = params;

    const oauthParams: Record<string, string> = {
      oauth_consumer_key: credentials.consumerKey,
      oauth_nonce: nonce ?? gerarNonce(),
      oauth_signature_method: 'HMAC-SHA1',
      oauth_timestamp: timestamp ?? gerarTimestamp(),
      oauth_token: credentials.accessToken,
      oauth_version: '1.0',
    };

    const baseString = OAuth1Signer.buildSignatureBaseString(method, url, {
      ...extraParams,
      ...oauthParams,
    });
    const assinatura = await OAuth1Signer.sign(
      baseString,
      credentials.consumerSecret,
      credentials.accessTokenSecret,
    );

    const paramsComAssinatura = { ...oauthParams, oauth_signature: assinatura };

    const cabecalho = Object.entries(paramsComAssinatura)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([chave, valor]) => `${percentEncode(chave)}="${percentEncode(valor)}"`)
      .join(', ');

    return `OAuth ${cabecalho}`;
  }

  /**
   * RFC 5849 §3.4.1 — `METHOD & base-URL-encoded & parâmetros-normalizados-encoded`.
   * Pura função de string (sem I/O, sem criptografia) — por isso testável
   * por inspeção literal do resultado, sem precisar de nenhum vetor de
   * teste externo.
   */
  static buildSignatureBaseString(method: string, url: string, params: Record<string, string>): string {
    const parametrosNormalizados = Object.entries(params)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([chave, valor]) => `${percentEncode(chave)}=${percentEncode(valor)}`)
      .join('&');

    return [method.toUpperCase(), percentEncode(url), percentEncode(parametrosNormalizados)].join('&');
  }

  /**
   * RFC 5849 §3.4.2 — `HMAC-SHA1(consumerSecret&tokenSecret, baseString)`,
   * em base64. Único ponto do módulo que toca criptografia de verdade;
   * mantido separado de `buildSignatureBaseString` para que um teste possa
   * comparar esta saída contra um cálculo HMAC-SHA1 independente (mesma
   * Web Crypto API do runtime, chamada separadamente) sem precisar
   * reimplementar a construção da base string também.
   */
  static async sign(baseString: string, consumerSecret: string, tokenSecret: string): Promise<string> {
    // Signing key = consumer secret + '&' + token secret, ambos
    // percent-encoded — RFC 5849 §3.4.2. Nunca logar isto.
    const signingKey = `${percentEncode(consumerSecret)}&${percentEncode(tokenSecret)}`;

    const chaveCripto = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(signingKey),
      { name: 'HMAC', hash: 'SHA-1' },
      false,
      ['sign'],
    );

    const assinaturaBuffer = await crypto.subtle.sign(
      'HMAC',
      chaveCripto,
      new TextEncoder().encode(baseString),
    );

    return arrayBufferParaBase64(assinaturaBuffer);
  }
}

/**
 * `oauth_nonce`: string aleatória única por requisição — a Garmin usa isto
 * (combinado ao timestamp) para recusar requisições repetidas (replay
 * attack). 32 caracteres hexadecimais é generoso o bastante para
 * colisão ser praticamente impossível.
 */
function gerarNonce(tamanho = 32): string {
  const bytes = new Uint8Array(Math.ceil(tamanho / 2));
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0'))
    .join('')
    .slice(0, tamanho);
}

/** `oauth_timestamp`: segundos desde a época Unix — a Garmin rejeita requisições com timestamp fora de uma janela de tolerância. */
function gerarTimestamp(): string {
  return Math.floor(Date.now() / 1000).toString();
}

/**
 * RFC 3986 percent-encoding — mais estrito que `encodeURIComponent`
 * nativo, que deixa `! * ' ( )` sem escapar. OAuth 1.0a exige que esses
 * caracteres também sejam codificados; sem isto a assinatura calculada
 * aqui nunca bateria com a que a Garmin calcula do lado dela. Exportado
 * para que os casos de caractere especial possam ser testados
 * isoladamente, sem envolver base string nem HMAC.
 */
export function percentEncode(valor: string): string {
  return encodeURIComponent(valor).replace(
    /[!*'()]/g,
    (char) => `%${char.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

function arrayBufferParaBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binario = '';
  for (const byte of bytes) {
    binario += String.fromCharCode(byte);
  }
  return btoa(binario);
}
