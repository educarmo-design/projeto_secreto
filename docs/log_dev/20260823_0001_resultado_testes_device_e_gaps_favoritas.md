# 20260823_0001_resultado_testes_device_e_gaps_favoritas — Resultado dos testes reais em device (fundador) + gaps encontrados em Favoritas

Log de Máquina (Regra 10.3 — append-only). Fundador testou em device
físico de verdade tudo que foi entregue em modo autônomo nos
RELATÓRIOS 20260820_0001/0002 e 20260821_0001/0002 (correção de fuso
horário, treino de força, hidratação N16, card consumo×meta N12, N15
aparelho por foto, favoritas N13).

## Resultado dos testes reais (fundador, device físico)

| Item | Resultado |
|---|---|
| Correção definitiva de fuso horário (histórico de transições, RELATÓRIO 20260820_0002) | ✅ OK |
| Treino de força (dicionário `tipos_atividades_fisicas`, RELATÓRIO 20260820_0002) | ✅ OK |
| Hidratação (N16, RELATÓRIO 20260819_0022) | ✅ OK |
| Glicosímetro/balança gravando em `coleta_diaria` (N15, RELATÓRIO 20260821_0001) | ✅ OK — confirmado gravando no banco |
| Card consumo × meta (N12, RELATÓRIO 20260821_0001) | ⚠️ Criado, aparece na tela, mas o CÁLCULO ainda não foi validado pelo fundador — precisa de teste mais detalhado (comparar número mostrado contra soma manual real). Não é um bug reportado, é uma verificação pendente. |
| Favoritas (N13, RELATÓRIO 20260821_0002) | ⚠️ Parcialmente OK — ver gaps abaixo |

## Gaps encontrados em Favoritas (achado real do fundador testando)

O fundador foi na tela de Favoritas procurando criar/editar uma
favorita e não achou. Investigação confirma: **não é bug, é
funcionalidade que ficou faltando por causa de onde eu decidi colocar
cada ação**, sem deixar isso claro/descobrível:

1. **Criar uma favorita**: só existe o botão ⭐ na AppBar de
   `ConfirmacaoPratoPage` ("Confirmar Refeição") — precisa fotografar/
   confirmar um prato primeiro. A tela de Favoritas (`FavoritasPage`)
   em si **não tem nenhum jeito de criar** uma favorita nova — só usa
   (toca pra registrar) e gerencia (menu de 3 pontos: trocar tipo/
   excluir) o que já existe.
2. **Editar conteúdo de uma favorita já salva**: nunca foi
   implementado — só "trocar tipo" e "excluir" (a spec original, Parte
   V1.H do Documento Mestre, só pedia "excluir/trocar tipo", não
   "editar itens"). Não dá pra abrir uma favorita salva e mudar quais
   alimentos ou quantidades estão nela.

## Próximo passo (decisão do fundador)

Fundador pediu pra trabalhar nos 2 gaps. Fica registrado aqui ANTES de
começar a implementação (pedido explícito do fundador: relatório da
pendência antes de iniciar o trabalho) — a implementação em si vai pro
próximo relatório desta sequência.
