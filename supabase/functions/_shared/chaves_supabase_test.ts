// Testes de _shared/chaves_supabase.ts (N44). Rodam sem rede e sem segredos
// reais: todos os valores abaixo são texto inventado só para o teste.
//
//   deno test --allow-env supabase/functions/_shared/chaves_supabase_test.ts

import { assertEquals } from 'jsr:@std/assert@^1.0.0';
import { lerChavePublicavel, lerChaveSecreta } from './chaves_supabase.ts';

const VARIAVEIS = [
  'SUPABASE_SECRET_KEYS',
  'SUPABASE_PUBLISHABLE_KEYS',
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_ANON_KEY',
];

/** Roda `fn` com o ambiente exatamente igual a `env` e restaura o original no fim. */
function comAmbiente(env: Record<string, string>, fn: () => void): void {
  const original = VARIAVEIS.map((nome) => [nome, Deno.env.get(nome)] as const);
  try {
    for (const nome of VARIAVEIS) Deno.env.delete(nome);
    for (const [nome, valor] of Object.entries(env)) Deno.env.set(nome, valor);
    fn();
  } finally {
    for (const [nome, valor] of original) {
      if (valor === undefined) Deno.env.delete(nome);
      else Deno.env.set(nome, valor);
    }
  }
}

Deno.test('chave secreta: prefere o dicionário novo à variável legada', () => {
  comAmbiente(
    {
      SUPABASE_SECRET_KEYS: '{"default":"sb_secret_teste"}',
      SUPABASE_SERVICE_ROLE_KEY: 'legada-teste',
    },
    () => assertEquals(lerChaveSecreta(), 'sb_secret_teste'),
  );
});

Deno.test('chave secreta: sem a chave nova, cai na legada (Parte 1 do aceite)', () => {
  comAmbiente(
    { SUPABASE_SERVICE_ROLE_KEY: 'legada-teste' },
    () => assertEquals(lerChaveSecreta(), 'legada-teste'),
  );
});

Deno.test('chave secreta: sem "default", usa a primeira do dicionário', () => {
  comAmbiente(
    { SUPABASE_SECRET_KEYS: '{"backend":"sb_secret_a","outra":"sb_secret_b"}' },
    () => assertEquals(lerChaveSecreta(), 'sb_secret_a'),
  );
});

Deno.test('chave secreta: dicionário malformado ou vazio cai na legada em vez de lançar', () => {
  for (const ruim of ['nao-e-json', '{}', 'null', '{"default":""}', '{"default":42}']) {
    comAmbiente(
      { SUPABASE_SECRET_KEYS: ruim, SUPABASE_SERVICE_ROLE_KEY: 'legada-teste' },
      () => assertEquals(lerChaveSecreta(), 'legada-teste', `entrada: ${ruim}`),
    );
  }
});

Deno.test('chave secreta: nada configurado devolve undefined', () => {
  comAmbiente({}, () => assertEquals(lerChaveSecreta(), undefined));
});

Deno.test('chave publicável: mesma ordem — nova, depois legada, depois undefined', () => {
  comAmbiente(
    {
      SUPABASE_PUBLISHABLE_KEYS: '{"default":"sb_publishable_teste"}',
      SUPABASE_ANON_KEY: 'legada-teste',
    },
    () => assertEquals(lerChavePublicavel(), 'sb_publishable_teste'),
  );
  comAmbiente(
    { SUPABASE_ANON_KEY: 'legada-teste' },
    () => assertEquals(lerChavePublicavel(), 'legada-teste'),
  );
  comAmbiente({}, () => assertEquals(lerChavePublicavel(), undefined));
});
