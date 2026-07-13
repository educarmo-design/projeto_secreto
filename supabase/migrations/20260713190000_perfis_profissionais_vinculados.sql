-- View espelhada de `perfis_pacientes_vinculados` (20260709180000), na direção
-- oposta: deixa o PACIENTE ler o nickname/tipo do PROFISSIONAL com quem tem
-- vínculo — necessária para a UI de Consentimento (Etapa B2C) mostrar QUEM
-- está convidando, antes de o paciente decidir aceitar ou recusar.
--
-- O gap que esta view fecha: `perfis_usuarios.nome`/`telefone`/`email` saem
-- cifrados AES-256-GCM no cliente antes do insert (CryptoStorageService —
-- ver cadastro_controller.dart), então mesmo com RLS liberada eles seriam
-- ciphertext ilegível para outro usuário. `nickname` é o único campo de
-- identificação em texto plano por design (é o handle público de
-- gamificação), e é exatamente o que a view espelho já expõe do paciente
-- para o profissional — aqui é o mesmo princípio, na direção inversa.
--
-- Sem RLS/GRANT dedicados, `perfis_usuarios` só libera `auth.uid() = id`
-- (20260706191827): o paciente não conseguiria ler nada do profissional,
-- mesmo o nickname.

create view perfis_profissionais_vinculados
with (security_invoker = false, security_barrier = true) as
select
  p.id,
  p.nickname,
  p.tipo_profissional
from perfis_usuarios p
where exists (
  select 1
  from vinculos_profissional_paciente v
  where v.profissional_id = p.id
    and v.paciente_id = auth.uid()
);

-- `security_invoker = false` (dono da view, que ignora RLS, executa a
-- consulta) + `security_barrier = true` (impede uma função barata injetada
-- no WHERE do consumidor de rodar ANTES do `exists` e vazar linha de
-- profissional sem vínculo) — mesma correção aplicada a
-- `perfis_pacientes_vinculados` em 20260713140000, pela mesma razão: com
-- `security_invoker = true` a RLS nativa de `perfis_usuarios` entraria em
-- vigor e bloquearia todo mundo, inclusive o paciente lendo o próprio
-- profissional vinculado.
--
-- Não há filtro por `status` de propósito: o paciente vê o profissional
-- vinculado independente do status (pendente inclusive — precisa saber quem
-- o convidou para decidir; ativo/em_carência — para uma futura tela "quem me
-- acompanha"). Só `id`, `nickname`, `tipo_profissional` — nunca nome, e-mail,
-- telefone ou endereço, mesmo que fossem legíveis.
grant select on perfis_profissionais_vinculados to authenticated;
