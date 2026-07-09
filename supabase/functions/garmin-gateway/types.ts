// Contrato de entrada JSON — tipagem estrita dos blocos de treino da
// Garmin Training API, mais o payload que este gateway recebe do Painel
// Web. Validação em tempo de execução vive aqui também
// (`validarGarminDispatchRequest`): tipos TypeScript sozinhos não protegem
// nada depois que o JSON já chegou como `unknown` pela rede — sem essa
// validação, um payload malformado só falharia dentro da própria chamada à
// Garmin, desperdiçando uma requisição de rede inteira (o oposto de Custo
// Zero) em vez de ser rejeitado localmente e de graça.

// ============================================================================
// Estrutura de treino da Garmin (o que este gateway ENVIA à Garmin)
// ============================================================================

export type SportType = 'RUNNING' | 'CYCLING';

/** Papel de cada bloco dentro do treino. */
export type IntensityType = 'WARMUP' | 'ACTIVE' | 'COOLDOWN' | 'RECOVERY' | 'REST' | 'INTERVAL';

/** O que o bloco está mirando — só `HEART_RATE` é usado hoje (zonas de FC prescritas), os demais existem para deixar o tipo extensível sem quebrar o contrato. */
export type TargetType = 'NO_TARGET' | 'HEART_RATE' | 'PACE' | 'POWER' | 'CADENCE';

export type DurationType = 'TIME' | 'DISTANCE' | 'OPEN';

export interface WorkoutTarget {
  targetType: TargetType;
  /** bpm (HEART_RATE), m/s (PACE) ou watts (POWER) — omitido quando targetType é NO_TARGET. */
  targetValueLow?: number;
  targetValueHigh?: number;
}

export interface WorkoutStep {
  stepOrder: number;
  intensityType: IntensityType;
  durationType: DurationType;
  /** Segundos — obrigatório quando durationType é 'TIME'. */
  durationValue?: number;
  target: WorkoutTarget;
}

export interface GarminWorkoutRequest {
  workoutName: string;
  sportType: SportType;
  steps: WorkoutStep[];
}

export interface GarminCreateWorkoutResponse {
  workoutId: string;
}

export interface GarminScheduleRequest {
  workoutId: string;
  garminUserId: string;
  /** yyyy-MM-dd */
  scheduleDate: string;
}

// ============================================================================
// Payload de entrada (o que o Painel Web ENVIA a este gateway)
// ============================================================================

/**
 * Espelha `PlanoTreinoEstrutura` de
 * `web_painel/src/core/types/database.ts` — duplicado propositalmente
 * (Deno e o projeto Vite/npm do painel são dois runtimes/toolchains
 * separados, sem import compartilhado direto entre eles). Mudar um lado
 * sem o outro quebra o contrato silenciosamente; mantenha os dois em
 * sincronia manualmente.
 */
export interface PlanoTreinoEstrutura {
  tipoTreino: 'corrida' | 'ciclismo';
  duracaoMinutos: number;
  zonaFcAlvoMin: number;
  zonaFcAlvoMax: number;
  /** yyyy-MM-dd */
  dataAgenda: string;
  observacoes?: string;
}

/** Espelha `GarminTrainingDispatchPayload` de `web_painel/src/features/prescriptions/services/garminApi.ts`. */
export interface GarminDispatchRequest {
  planejamentoClinicoId: string;
  pacienteIdAnonimo: string;
  estrutura: PlanoTreinoEstrutura;
}

export interface GarminDispatchResponse {
  garmin_workout_id: string;
}

export interface GarminDispatchErrorResponse {
  error: string;
}

/**
 * Erro de validação com mensagem segura para devolver ao cliente (nunca
 * expõe detalhes internos — só qual campo do payload está errado e por
 * quê).
 */
export class PayloadInvalidoError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PayloadInvalidoError';
  }
}

/**
 * Valida estritamente o corpo JSON recebido antes de qualquer chamada à
 * Garmin. Lança [PayloadInvalidoError] com uma mensagem específica no
 * primeiro campo inválido encontrado — `index.ts` converte isso num 400
 * sem nunca chegar a gastar uma chamada de rede à Garmin com um payload
 * ruim.
 */
export function validarGarminDispatchRequest(corpo: unknown): GarminDispatchRequest {
  if (typeof corpo !== 'object' || corpo === null) {
    throw new PayloadInvalidoError('O corpo da requisição deve ser um objeto JSON.');
  }
  const obj = corpo as Record<string, unknown>;

  if (typeof obj.planejamentoClinicoId !== 'string' || obj.planejamentoClinicoId.length === 0) {
    throw new PayloadInvalidoError('"planejamentoClinicoId" é obrigatório e deve ser uma string.');
  }
  if (typeof obj.pacienteIdAnonimo !== 'string' || obj.pacienteIdAnonimo.length === 0) {
    throw new PayloadInvalidoError('"pacienteIdAnonimo" é obrigatório e deve ser uma string.');
  }

  return {
    planejamentoClinicoId: obj.planejamentoClinicoId,
    pacienteIdAnonimo: obj.pacienteIdAnonimo,
    estrutura: validarPlanoTreinoEstrutura(obj.estrutura),
  };
}

function validarPlanoTreinoEstrutura(valor: unknown): PlanoTreinoEstrutura {
  if (typeof valor !== 'object' || valor === null) {
    throw new PayloadInvalidoError('"estrutura" é obrigatória e deve ser um objeto.');
  }
  const obj = valor as Record<string, unknown>;

  if (obj.tipoTreino !== 'corrida' && obj.tipoTreino !== 'ciclismo') {
    throw new PayloadInvalidoError('"estrutura.tipoTreino" deve ser "corrida" ou "ciclismo".');
  }
  if (typeof obj.duracaoMinutos !== 'number' || !Number.isFinite(obj.duracaoMinutos) || obj.duracaoMinutos <= 0) {
    throw new PayloadInvalidoError('"estrutura.duracaoMinutos" deve ser um número maior que zero.');
  }
  if (typeof obj.zonaFcAlvoMin !== 'number' || !Number.isFinite(obj.zonaFcAlvoMin) || obj.zonaFcAlvoMin <= 0) {
    throw new PayloadInvalidoError('"estrutura.zonaFcAlvoMin" deve ser um número maior que zero.');
  }
  if (
    typeof obj.zonaFcAlvoMax !== 'number' ||
    !Number.isFinite(obj.zonaFcAlvoMax) ||
    obj.zonaFcAlvoMax <= obj.zonaFcAlvoMin
  ) {
    throw new PayloadInvalidoError('"estrutura.zonaFcAlvoMax" deve ser maior que "zonaFcAlvoMin".');
  }
  if (typeof obj.dataAgenda !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(obj.dataAgenda)) {
    throw new PayloadInvalidoError('"estrutura.dataAgenda" deve estar no formato yyyy-MM-dd.');
  }
  if (obj.observacoes !== undefined && typeof obj.observacoes !== 'string') {
    throw new PayloadInvalidoError('"estrutura.observacoes", se fornecida, deve ser uma string.');
  }

  return {
    tipoTreino: obj.tipoTreino,
    duracaoMinutos: obj.duracaoMinutos,
    zonaFcAlvoMin: obj.zonaFcAlvoMin,
    zonaFcAlvoMax: obj.zonaFcAlvoMax,
    dataAgenda: obj.dataAgenda,
    ...(typeof obj.observacoes === 'string' ? { observacoes: obj.observacoes } : {}),
  };
}
