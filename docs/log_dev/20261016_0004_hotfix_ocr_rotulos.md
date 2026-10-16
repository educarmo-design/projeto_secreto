# Hotfix — "foto branca" no OCR de rótulos era o card de macros vazio, não a foto

**Tipo:** RCA (3ª rodada) + correção. Fundador testou em produção: ingredientes
vêm corretos, mas o card continua "um quadrado branco" e calorias/macros não
preenchem.

## Investigação — a hipótese de "foto quebrada" foi descartada com evidência

A tarefa chegou com uma hipótese forte: `Image.file()`/`Image.memory()`
quebrados, o `File`/path se perdendo por lifecycle do Android. Antes de
escrever qualquer código, refiz a busca **exaustiva** de qualquer widget de
imagem em todo o projeto:

```
grep -rn "Image\.file\|Image\.memory\|Image\.network\|Image\(|DecorationImage|
FadeInImage|Image\.asset|CachedNetworkImage|RawImage|MemoryImage|FileImage" lib/
```

**Zero resultados**, de novo (3ª vez que confirmo isto nesta saga —
`image_picker` também não é dependência do projeto). **Não existe, nunca
existiu, nenhum widget que renderize a foto tirada** — o fluxo é 100% câmera
ao vivo (Zero Storage, LGPD, documentado explicitamente desde a criação
desta tela). Não há "foto quebrada" pra consertar porque não há foto
renderizada em lugar nenhum.

**Hipótese alternativa, confirmada pela evidência disponível**: o "quadrado
branco" é o `Card(color: Colors.white, ...)` do card de macros
(`_buildResultadoRotulo`) — quando os 4 `TextFormField` (calorias/proteína/
carboidrato/gordura) vêm vazios, o card fica literalmente um bloco branco
sem nenhum texto visível, indistinguível, pra quem olha a tela rapidamente,
de "não carregou nada". Isso é consistente com o segundo sintoma relatado
("macros não preenchem, só ingredientes") — são o MESMO bug, descrito de
duas formas.

**Decisão registrada**: perguntei explicitamente ao fundador se, mesmo
assim, valeria adicionar uma prévia real da foto (guardando os bytes em
memória durante a revisão) — ele escolheu **não fazer isso**, preservando o
design Zero Storage já usado em TODOS os tipos de captura deste app, não só
rótulo. Esta correção foca 100% em fazer a extração/exibição dos macros ser
honesta, não em adicionar uma prévia.

## Por que os macros vêm vazios (causa provável, não 100% confirmável sem acesso ao Gemini)

Não consigo chamar a API do Gemini de verdade nesta investigação (sem
acesso a `GEMINI_API_KEY`/`SUPABASE_SERVICE_ROLE_KEY` — segredos do
projeto, corretamente nunca expostos em texto claro pelo `supabase secrets
list`). Confirmado por leitura de código, porém:

- O backend (`avaliarLeituraRotulo`) **exige pelo menos 1 macro não-nulo**
  pra aceitar a leitura — se os 4 fossem genuinamente null, a resposta
  inteira seria rejeitada (422) e os ingredientes TAMBÉM não apareceriam.
  Como os ingredientes aparecem, pelo menos 1 macro chegou — a percepção de
  "nenhum macro preenche" é consistente com "a maioria/os mais importantes
  (ex. calorias) vêm vazios", não com uma falha total.
- Achado mais provável, por inspeção do prompt anterior
  (`SYSTEM_PROMPT_ROTULO`): rótulos brasileiros de "Informação Nutricional"
  quase sempre imprimem DUAS colunas lado a lado ("por porção" e "100
  g"/"100 ml") — o prompt antigo não dizia qual coluna usar quando só uma
  delas existe, nem nomeava os rótulos reais impressos ("Valor energético",
  "Gorduras totais"). Um modelo incerto sobre qual coluna ler tende a
  responder `null` em vez de arriscar — exatamente o padrão "li os
  ingredientes (sem ambiguidade de coluna) mas não os números (com
  ambiguidade de coluna)".

## Correção

### Backend — `SYSTEM_PROMPT_ROTULO` (`extract-metric-photo/index.ts`)

Adicionada uma "Column-choice rule" explícita: preferir a coluna "por
porção" quando existir; usar a coluna "100 g"/"100 ml" quando for a ÚNICA
impressa (em vez de `null`), registrando isso em `porcao_descricao`; nomeia
os rótulos impressos reais ("Valor energético" = calorias; "Gorduras
totais", não "saturadas"/"trans"); reforça que só deve haver `null` quando
o nutriente está GENUINAMENTE ausente da tabela, nunca por causa de duas
colunas ou letra pequena. **Não relaxa** a regra de nunca calcular/estimar
— continua estritamente transcrição.

### Flutter — `CameraCaptureView`/`RotuloExtracaoModel`

Regra 23 ("falhar visível, nunca arbitrar/esconder") aplicada ao que já
estava, silenciosamente, no código:

- Novo getter `RotuloExtracaoModel.todosMacrosPresentes`.
- Novo banner (mesmo padrão visual do aviso de "possível foto de tela", cor
  `AppColors.info`) quando QUALQUER um dos 4 macros vier ausente — nunca
  mais um card em branco sem explicação.
- Cada campo de macro vazio agora tem `hintText` ("não impresso no
  rótulo") em vez de um espaço mudo — comunica "a IA olhou e não achou
  isto", não "quebrou".

**Ingredientes não foram tocados** (restrição explícita da tarefa) — nem o
parsing, nem a exibição, nem o limite de 10 itens.

## Verificação

- **Backend**: `deno check` limpo; `deno test` 132/132 (sem teste novo — o
  prompt em si não é exportado nem testável por `deno test`; o efeito real
  só se confirma com o Gemini de verdade, fora do alcance desta tarefa).
- **Flutter**: `flutter analyze` 30 issues (linha de base, zero novo);
  `flutter test` **524/524** (era 519/519, +5 novos — teste novo e
  dedicado pra `RotuloExtracaoModel.todosMacrosPresentes`, cobrindo o
  cenário exato relatado: todos os 4 ausentes, qualquer um ausente, todos
  presentes). Sem teste pra `CameraCaptureView` em si — limitação
  pré-existente já documentada (`CameraController` não é mockável).

## Deploy

Mudança na Edge Function — deploy imediato após o merge:

```
supabase functions deploy extract-metric-photo
```

Branch `fix/hotfix-ocr-rotulos`, a partir de `main`.
