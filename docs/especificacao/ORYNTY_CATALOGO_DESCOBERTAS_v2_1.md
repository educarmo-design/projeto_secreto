# ORYNTY — CATÁLOGO DE DESCOBERTAS v2.1
## 277 templates em 36 famílias de cálculo · documento subordinado ao DOCUMENTO MESTRE v9.2.1

**Data:** 16 de Novembro de 2026
**Sincronizado com:** DOCUMENTO MESTRE **v9.2.1** (emenda de 16/Nov: decisões 97 e 98, segurança de RPC e fronteira do híbrido). **A emenda não toca template nenhum** — este catálogo segue em v2.1, com os mesmos 277 templates.
**O que mudou do v2.0:** o horário da refeição foi **confirmado** (24 templates saem do risco); o **tipo** da refeição entra como pendência (7); a contagem de **famílias de cálculo** passa a ser a unidade de trabalho (§5.2); e a ordem de construção acompanha a fila nova do Mestre. **Nenhum template foi alterado, removido ou acrescentado.**
**Substitui:** `ORYNTY_CATALOGO_TEMPLATES_UAU_CONTINUOUS_RF_ET_005.md` v1.2 (2.178 entradas) e `ORYNTY_TEMPLATES_CURADOS_v2_0.md` (82 templates)

> ## CLÁUSULA DE SUBORDINAÇÃO
> Este documento é **subordinado ao DOCUMENTO MESTRE**. Ele **não cria** regra, nível, permissão, gate ou finalidade. Onde conflitar com o Mestre, **o Mestre prevalece**.
> As regras que governam este catálogo vivem na **Parte 0 (regras 28, 30, 31)**, na **Parte 5 (finalidades declaradas)** e na **Parte D (motor de descobertas)** do Mestre v9.2.1. Aqui há apenas templates.
> **Motivo da cláusula:** em setembro de 2026 o `docs/motor_metabolico.txt` virou segunda fonte de verdade, contradisse o Mestre (seções 9/23 contra ME-005) e produziu a deriva da decisão 42. Esta cláusula existe para que não se repita.

---

## 1. O QUE ESTE DOCUMENTO É

277 templates de descoberta, escritos e lidos um por um. Cada um tem a frase que o usuário lê, **a frase renderizada com dado plausível** — é por ela que se julga o português —, a ressalva que vai fora do corpo, o dado exigido, o gate e o perfil de usuário.

### 1.1 De onde vem

| Origem | Entradas | Sobreviveram |
|---|---:|---:|
| Catálogo v1.2 (`RF_ET_005`) | 2.178 | **31** com reescrita |
| Curadoria editorial de 25/Out | 82 | 82 |
| Camada de índices publicados | — | +91 |
| Família de intervalos entre eventos | — | +10 |
| Coocorrência e qualidade do dado | — | +13 |
| Inventário de pares do v1.2 | — | +17 |
| Ajustes de consolidação | — | +33 |
| **Total** | | **277** |

> **Nota de contagem.** A estimativa dada em conversa foi 252. A escrita linha a linha chegou a **277** — a família de intervalos e a de índices publicados renderam mais que o previsto. O número deste documento é o verdadeiro; a estimativa era estimativa.

### 1.2 Por que o v1.2 contribuiu só 31 de 2.178

Extração mecânica do arquivo: 2.166 entradas com corpo de texto, normalizadas por variável e por nome de métrica, colapsam em **254 esqueletos de frase**, dos quais **20 cobrem 1.786 entradas (82,5%)**. Apenas **195 entradas tinham frase realmente única**.

O resto era permutação. Duas doenças explicam a maior parte das mortes, e ambas viraram regra no Mestre (regras 30 e 31):

**Variável semântica indefinida.** `{descricao_padrao}`, `{estado_mudanca}`, `{descricao_variacao_peso}`, `{efeito}`, `{metodo}` — variáveis que carregavam o **verbo ou o juízo** da frase sem vocabulário fechado. `HV-C3-001` a `HV-C3-038` eram 38 títulos diferentes sobre **um corpo idêntico** cujo sentido inteiro morava num `{descricao_padrao}` nunca especificado. Mataram ~60 entradas únicas.

**Cobertura vendida como descoberta.** *"Encontramos N registros válidos entre M oportunidades de medição avaliáveis"* é qualidade do dado, não achado. Frase cujo sujeito é o **registro** e não o **comportamento** é SUPORTE por construção. Mataram ~370 entradas.

---

## 2. A LEI EDITORIAL

> **A surpresa vive na dispersão, não na tendência central.**

O usuário já tem intuição da própria média — sabe mais ou menos quanto anda, quanto dorme, quanto pesa. **Ninguém tem intuição da própria variância, concentração ou bimodalidade.**

"Sua média de passos é 6.800" é tédio. "Metade dos seus passos veio de 6 dias" é descoberta. "Você dormiu 7h12" é dado. "Seu despertar varia o dobro do seu adormecer" é revelação.

Por isso **todo N3 deste catálogo é de amplitude, concentração, faixa habitual, bimodalidade, sequência, estrato, intervalo ou índice publicado. Nenhum é média ou total** — médias e totais foram rebaixados a N1, onde pertencem.

---

## 3. AS 14 REGRAS DE REDAÇÃO

Valem para qualquer template futuro. São a especificação editorial do produto.

**R1 — O sujeito é "você", nunca "seus registros".**
❌ "Nos últimos 30 dias, seus registros de passos apresentaram variação." ✅ "Você anda quase o dobro durante a semana."

**R2 — A frase nunca começa com preposição de período.** "No período de…", "Nos últimos 30 dias…" → a janela vai para `ctx`.

**R3 — A conta comparativa já vem feita.** Não "9.200 e 5.100", mas "**quase o dobro**: 9.200 contra 5.100".

**R4 — Ressalva, cobertura e método saem do corpo** e vão para `ctx`, em letra menor.

**R5 — Zero jargão estatístico na interface.** Proibidos no corpo: *desvio padrão, mediana, percentil, coeficiente, amostra, significativo, n=, registros válidos, dias monitorados, intervalo de confiança, valor-p*. Substituições: "mediana" → **"na maioria dos dias"** / **"metade dos dias"**; "desvio padrão" → **"variou X minutos"**.

**R6 — Concordância escrita à mão em cada template.** A forma genérica `{metrica} totalizou {valor} {unidade}` é **proibida**: produz "passos totalizou 234.567 passos".

**R7 — Números em formato humano.** Acima de 60 min: **"1h18"**. Abaixo: **"47 minutos"**. Milhar com ponto, decimal com vírgula. Arredondar. Multiplicação em palavras: "o dobro", "4 vezes mais" — nunca "4x".

**R8 — O título é a descoberta, não a etiqueta.** ❌ "Variação dos horários de sono" ✅ "Você acorda menos no mesmo horário do que dorme"

**R9 — Um par de números por frase.** Três números numa oração derrubam a leitura; quebre em duas frases.

**R10 — Sem julgamento, sem conselho, sem elogio.** Proibidos: *parabéns, ótimo, continue assim, você deveria, procure, tente, ideal, recomendado, saudável, preocupante, ruim*. Não é só editorial: é a linha das decisões 43/44 e das duas finalidades declaradas (Mestre, Parte 5).

**R11 — Uma ressalva no máximo, e só quando real.** Pilha de hedge destrói a confiança tanto quanto a afirmação exagerada.

**R12 — Tics e anglicismos banidos.** *consistentemente* (usar "quase sempre"), *vale notar, é importante destacar, isso significa que, observa-se, no período analisado, jornada, otimizar, potencialmente, significativo, não apenas… mas também*. Na tela, para o usuário, a palavra é **descoberta** — nunca "insight".

**R13 — Ausência nunca é descoberta.** Silêncio é estado de tela (SUPORTE), nunca cartão.

**R14 — Registro ≠ realidade.** Frase cujo conteúdo deriva da completude da anotação é SUPORTE, não descoberta. (Promovida a regra 31 do Mestre.)

### 3.1 Linguagem de alerta — proibida no app solo

Pela finalidade de **bem-estar** declarada para o app (Mestre, Parte 5.0), nenhum template do perfil solo usa linguagem de alerta ou detecção. **"Atenção", "alerta", "fora do normal", "procure um médico" são proibidos.** Marco é permitido: *"você passou de 7.000 passos"*. Aviso não é: *"atenção, sua FC subiu"*.

---

## 4. COMO LER CADA ENTRADA

```
**`ID`** ⭐ · perfil · *Título — a descoberta*
- corpo com {variaveis}
- → "exemplo renderizado"           ← é por aqui que se julga o português
- ctx: ressalva · dados: o que exige · gate: condição de publicação
```

**Perfil:** `ambos` disponível aos dois tipos · `prof` somente com acompanhamento profissional (carrega referência clínica, meta ou leitura prognóstica) · `backlog` aguardando parceiro nutricionista.
**⭐** = prioridade de construção.
**`COND:`** = depende de dado ainda não confirmado.
**Gates:** `G1` registro válido · `G2` períodos comparáveis · `G3` grupos observados comparáveis · `G4` pareamento temporal explícito · `G5` múltiplas janelas comparáveis. Definições no Mestre, Parte D.

**Todos os limiares citados nos gates vivem em tabela de configuração** (`limiares_praticos`, Mestre Parte D.3), nunca em código — regra 16.

---

## 5. QUADRO GERAL

| Nível | Nome | Qtd | Dispara no 1º mês | Perfil |
|---|---|---:|---:|---|
| **N1** | Informativo | 18 | 18 | 18 ambos |
| **N2** | Comparativo | 36 | ~12 | 31 ambos · 5 prof |
| **N3** | Comportamental | 117 | ~95 | 106 ambos · 8 prof · 3 backlog |
| **N4** | Comparativo multidimensional | 38 | ~8 | 37 ambos · 1 prof |
| **N5** | Longitudinal descritivo | 49 | 0 | 48 ambos · 1 prof |
| **SUPORTE** | Estado e qualidade | 19 | 19 | 19 ambos |
| | **TOTAL** | **277** | **~152** | **259 ambos · 15 prof · 3 backlog** |

**Leia a coluna do meio — ela é a que importa para o beta.**

Os **49 N5 não disparam nenhum no primeiro mês**: exigem duas janelas comparáveis, e com janela de 30 dias o primeiro N5 só existe por volta do terceiro mês de uso. Os **N4 exigem grupo mínimo**, que em 30 dias fecha para poucos. E a maior parte dos **N2 compara com o período anterior**, que no primeiro mês não existe — só os dois do fosso e os de meta disparam de saída.

Um usuário de beta vê material de **~152 templates no primeiro mês**, e **~168 se o timestamp de sono existir**. Os 277 por volta do terceiro mês. **É cronograma, não catálogo** — e é melhor dizer isso agora do que descobrir em dezembro.

### 5.1 O que depende de dado ainda não confirmado — **atualizado em 16/Nov**

| Dependência | Templates | Situação |
|---|---:|---|
| ~~Horário da refeição~~ | ~~24~~ → **0** | **RESOLVIDO em 16/Nov.** O fundador confirmou: é gravado, **no início da refeição**. A família de intervalos inteira volta a ser viável |
| **Timestamp de início e fim do sono** | **22** | N43 — o dado **chega** com início e fim do Health Connect; a dúvida é se é **persistido** ou descartado após virar minutos |
| **Tipo da refeição** (café/almoço/jantar) | **7** | N43 — existe nas favoritas; **não confirmado** nos outros três métodos de registro |
| Coluna NOVA + grupo FAO | 13 | N39 — curadoria de duas colunas sobre a TACO, junto do N30 |
| Fibra e sódio | 4 | N30 |
| Circunferência de cintura | 4 | N38 — o campo existe desde 18/Set; falta a divisão |
| Passos intradiários | 2 | verificar se o Health Connect é gravado granular ou só no total do dia |
| **Travados pelo R25** (FC pareada) | 6 | decisão regulatória; **fora da primeira biblioteca por escolha** |
| **Backlog de parceiro** (fronteira NOVA 3/4) | 3 | validação por nutricionista |
| **Total pendente de verificação** | **29** | uma só consulta ao schema (N43) decide os dois primeiros |

Os 22 do sono incluem o `N3-SON-401`, que é o melhor template do catálogo.

**Nota de precisão sobre o horário da refeição:** "início da refeição" é quando o usuário **abre o registro**, que é perto mas não igual a quando ele começa a comer. Irrelevante para a maioria dos templates; para o `N3-INT-901` (jejum noturno) e o `N3-INT-902` (intervalo até deitar) é a fonte de ruído da família, e é o limiar prático que a contém. Os contextos desses templates já dizem *"mede o horário do registro"* — foram escritos defensivamente e não precisam de mudança.

### 5.2 A unidade de trabalho é a família, não o template

**Template é linha de tabela. Código é a família de cálculo.** *"Metade dos seus passos veio de 6 dias"* e *"um terço das suas calorias veio de 5 dias"* são a mesma conta de concentração em métricas diferentes: uma função, duas linhas.

| | |
|---|---:|
| Templates | **277** |
| **Famílias de cálculo** | **36** |
| Famílias que os 15 do UAU exigem | **9** |
| Templates que essas 9 famílias destravam | **87 (31%)** |

As 9 do UAU: concentração, estrato semanal, dia específico, dispersão, faixa habitual, distribuição interna, intervalos, repertório alimentar, fosso.

**Semear um template depois que a família existe é entrada de dado com amostragem (regra 26), não desenvolvimento.** Ver Mestre, Parte D.10.

---

# 6. NÍVEL 1 — INFORMATIVO (18)

> **Função:** contextualizar uma descoberta maior ou servir de fallback honesto. **Nunca é cartão principal.**
> **Truque editorial do N1:** total puro é a tela inicial repetida. O N1 só se justifica com uma **conversão que o usuário sente** — passos em quilômetros, andares em metros, treinos em "por semana".

**`N1-PAS-001`** · ambos · *Seus passos do mês*
- `Você deu {passos_total} passos neste mês — cerca de {km} quilômetros.`
- → *"Você deu 234.600 passos neste mês — cerca de 176 quilômetros."*
- ctx: `Com base em {n} dos {total} dias.` · dados: passos + altura (passada) · gate: G1, cobertura ≥60%

**`N1-DIS-001`** · ambos · *A distância que você cobriu*
- `Você percorreu {km} quilômetros no mês.`
- → *"Você percorreu 182 quilômetros no mês."*
- ctx: `Soma dos dias com dado de distância.` · dados: distância · gate: G1, cobertura ≥60%

**`N1-AND-001`** · ambos · *Os andares que você subiu*
- `Você subiu {andares} andares no mês — o equivalente a {metros} metros de altura.`
- → *"Você subiu 312 andares no mês — o equivalente a 940 metros de altura."*
- ctx: `Conversão a 3 metros por andar.` · dados: andares · gate: G1, cobertura ≥60%

**`N1-SON-001`** · ambos · *Quanto você dormiu*
- `Você dormiu {sono_medio} por noite, em média.`
- → *"Você dormiu 7h10 por noite, em média."*
- ctx: `Média de {n} noites com dado.` · dados: sono total · gate: G1, ≥14 noites

**`N1-SON-002`** · ambos · *A arquitetura média da sua noite*
- `Sua noite se dividiu em {leve} de sono leve, {profundo} de profundo e {rem} de REM.`
- → *"Sua noite se dividiu em 3h50 de sono leve, 1h18 de profundo e 1h32 de REM."*
- ctx: `Estágios estimados pelo dispositivo.` · dados: sono por estágio · gate: G1, ≥14 noites, mesma fonte

**`N1-TRE-001`** · ambos · *Quantas vezes você treinou*
- `Você registrou {n} treinos no mês — {media} por semana.`
- → *"Você registrou 14 treinos no mês — pouco mais de três por semana."*
- ctx: `—` · dados: sessões · gate: G1, ≥3 sessões

**`N1-TRE-002`** · ambos · *Seu tempo total de treino*
- `Você somou {horas} horas de treino no mês.`
- → *"Você somou 11h20 de treino no mês."*
- ctx: `Soma das sessões registradas.` · dados: sessões com duração · gate: G1, ≥3 sessões

**`N1-ENE-001`** · ambos · *Seu gasto medido*
- `Seu gasto medido pelo relógio ficou em {kcal} kcal por dia, em média.`
- → *"Seu gasto medido pelo relógio ficou em 2.640 kcal por dia, em média."*
- ctx: `Medido pelo dispositivo, não estimado.` · dados: calorias totais · gate: G1, ≥20 dias

**`N1-ENE-002`** · ambos · *Suas calorias ativas*
- `Do seu gasto diário, {kcal} kcal vieram de movimento.`
- → *"Do seu gasto diário, 620 kcal vieram de movimento."*
- ctx: `Média dos dias com dado. Valor estimado pelo dispositivo.` · dados: calorias ativas · gate: G1, ≥20 dias

**`N1-FCR-001`** · ambos · *Sua frequência de repouso*
- `Sua frequência cardíaca de repouso ficou em {bpm} bpm neste mês.`
- → *"Sua frequência cardíaca de repouso ficou em 58 bpm neste mês."*
- ctx: `Média das medições do período.` · dados: FC repouso · gate: G1, ≥15 medições, **sem leitura clínica**

**`N1-PES-001`** · ambos · *Sua última pesagem*
- `Sua pesagem mais recente foi {peso} kg, no dia {dia}.`
- → *"Sua pesagem mais recente foi 82,4 kg, no dia 20."*
- ctx: `—` · dados: peso · gate: G1

**`N1-COR-001`** · ambos · *Sua composição atual*
- `Na sua última medição você tinha {magra} kg de massa magra e {gordura}% de gordura.`
- → *"Na sua última medição você tinha 59,0 kg de massa magra e 22,8% de gordura."*
- ctx: `Medição de {data}, por bioimpedância.` · dados: massa magra, %gordura · gate: G1, medição <45 dias

**`N1-WHT-001`** ⭐ · ambos · *Sua relação cintura-estatura* `COND: circunferência de cintura`
- `Sua cintura é {cintura} cm e sua altura {altura} cm — uma relação de {whtr}.`
- → *"Sua cintura é 92 cm e sua altura 178 cm — uma relação de 0,52."*
- ctx: `Medição de {data}. Faixa de referência: {faixa}.` · dados: cintura + altura · gate: G1 · **faixa omitida se IMC ≥35** (fidelidade ao NICE NG7)

**`N1-CAL-001`** · ambos · *Suas calorias registradas*
- `Você registrou {kcal} kcal por dia, em média.`
- → *"Você registrou 2.180 kcal por dia, em média."*
- ctx: `Soma do que você anotou; refeições não registradas não entram.` · dados: refeições · gate: G1, ≥15 dias

**`N1-PRO-001`** · ambos · *Sua proteína registrada*
- `Você registrou {g} g de proteína por dia, em média — {gkg} g por quilo de peso.`
- → *"Você registrou 118 g de proteína por dia, em média — 1,4 g por quilo de peso."*
- ctx: `Com base no que você registrou.` · dados: refeições com macros + peso · gate: G1, ≥15 dias

**`N1-MAC-001`** · ambos · *A divisão dos seus macros*
- `Do que você registrou, {pct_c}% veio de carboidrato, {pct_p}% de proteína e {pct_g}% de gordura.`
- → *"Do que você registrou, 48% veio de carboidrato, 22% de proteína e 30% de gordura."*
- ctx: `Percentual sobre as calorias registradas.` · dados: refeições com macros · gate: G1, ≥15 dias

**`N1-AGU-001`** · ambos · *Sua água registrada*
- `Você registrou {litros} litros de água por dia, em média.`
- → *"Você registrou 2,1 litros de água por dia, em média."*
- ctx: `Soma do que você anotou no app.` · dados: água · gate: G1, ≥15 dias

**`N1-COB-001`** · ambos · *A cobertura dos seus dados*
- `Seus dados cobriram {n} dos {total} dias do mês.`
- → *"Seus dados cobriram 26 dos 30 dias do mês."*
- ctx: `Dias sem dado não entram como zero.` · dados: cobertura · gate: — · **contexto, nunca cartão**

---

# 7. NÍVEL 2 — COMPARATIVO (36)

> **Função:** mudança entre períodos e distância de meta vigente.
> **Regra própria do N2:** a direção vem em **palavra** antes do número. "Você andou mais" antes de "7.400 contra 6.100".
> **Metas são sempre as históricas** — a que valia na data de cada registro, nunca a atual.

## 7.1 Os dois do fosso

**`N2-FOS-001`** ⭐⭐ · ambos · *Seu gasto declarado e o gasto medido*
- `Na anamnese, seu gasto diário foi estimado em {declarado} kcal. O relógio mediu {medido} kcal — uma diferença de {dif} kcal por dia.`
- → *"Na anamnese, seu gasto diário foi estimado em 2.330 kcal. O relógio mediu 2.640 kcal — uma diferença de 310 kcal por dia."*
- ctx: `O valor da anamnese é estimativa a partir do nível de atividade que você declarou. O do relógio é medição.` · dados: TDEE do Motor V1 + calorias totais · gate: G2, ≥20 dias, estimativa marcada (regra 29)
- **nota:** subtração entre dois valores observados. **Não é inferência — não cai na regra 28.** Ver Mestre Parte D.5.

**`N2-FOS-002`** ⭐⭐ · ambos · *Seu saldo do mês e seu peso*
- `Você registrou {saldo} kcal {acima_abaixo} do que gastou neste mês. No mesmo período, seu peso {direcao} {delta} kg.`
- → *"Você registrou 4.200 kcal menos do que gastou neste mês. No mesmo período, seu peso caiu 0,6 kg."*
- ctx: `Dois fatos do mesmo período, lado a lado. O consumo considera apenas o que você registrou.` · dados: refeições + calorias totais + peso (≥2 pesagens) · gate: G2, ≥20 dias com ambos
- **nota:** **proibido** escrever "resultou em", "levou a", "por causa de", ou qualquer projeção. A redação é o que mantém isto fora da regra 28.

## 7.2 Período contra período

**`N2-PAS-001`** · ambos · *Você andou mais (ou menos) que no mês passado*
- `Você andou {mais_menos} este mês: {atual} passos por dia, contra {anterior} no anterior.`
- → *"Você andou mais este mês: 7.400 passos por dia, contra 6.100 no anterior."*
- ctx: `Cobertura parecida nos dois meses ({a} e {b} dias).` · dados: passos · gate: G2, diferença ≥10%

**`N2-DIS-001`** · ambos · *Sua distância mudou*
- `Você percorreu {mais_menos} distância este mês: {atual} km, contra {anterior}.`
- → *"Você percorreu mais distância este mês: 182 km, contra 149."*
- ctx: `Cobertura comparável.` · dados: distância · gate: G2, diferença ≥10%

**`N2-AND-001`** · ambos · *Você subiu mais andares*
- `Você subiu {comparativo} de andares este mês: {atual}, contra {anterior}.`
- → *"Você subiu quase o dobro de andares este mês: 312, contra 170."*
- ctx: `Cobertura comparável.` · dados: andares · gate: G2, diferença ≥25%

**`N2-SON-001`** · ambos · *Você dormiu menos (ou mais) que no mês passado*
- `Você dormiu {delta} {mais_menos} por noite que no mês anterior: {atual} contra {anterior}.`
- → *"Você dormiu 22 minutos menos por noite que no mês anterior: 6h48 contra 7h10."*
- ctx: `Com base em {a} e {b} noites.` · dados: sono total · gate: G2, diferença ≥15 min, ≥14 noites cada

**`N2-SON-002`** · ambos · *Seu sono profundo mudou*
- `Seu sono profundo foi de {anterior} para {atual} por noite.`
- → *"Seu sono profundo foi de 1h05 para 1h18 por noite."*
- ctx: `Estágios estimados pelo dispositivo, mesma fonte nos dois períodos.` · dados: sono profundo · gate: G2, ≥14 noites cada, mesma fonte

**`N2-SON-003`** · ambos · *Sua eficiência de sono mudou*
- `Sua eficiência de sono foi de {anterior}% para {atual}%.`
- → *"Sua eficiência de sono foi de 88% para 91%."*
- ctx: `Eficiência é o tempo dormido sobre o tempo total na cama.` · dados: sono total + acordado · gate: G2, ≥14 noites cada

**`N2-FCR-001`** · ambos · *Sua frequência de repouso mudou*
- `Sua frequência de repouso {subiu_caiu} de {anterior} para {atual} bpm entre os dois últimos meses.`
- → *"Sua frequência de repouso caiu de 61 para 58 bpm entre os dois últimos meses."*
- ctx: `Mesma fonte de medição nos dois períodos.` · dados: FC repouso · gate: G2, diferença ≥3 bpm, **sem leitura clínica**

**`N2-PES-001`** · ambos · *Como seu peso se moveu no mês*
- `Seu peso foi de {inicial} kg na primeira pesagem do mês para {final} kg na última.`
- → *"Seu peso foi de 84,2 kg na primeira pesagem do mês para 82,4 kg na última."*
- ctx: `{n} pesagens no período. Peso oscila entre dias; duas medições não são tendência.` · dados: peso · gate: G2, ≥4 pesagens, **nenhuma projeção**

**`N2-COR-001`** · ambos · *Sua massa magra mudou*
- `Sua massa magra foi de {antes} kg para {depois} kg entre as duas últimas medições.`
- → *"Sua massa magra foi de 58,1 kg para 59,0 kg entre as duas últimas medições."*
- ctx: `Medições de {a} e {b}, pela mesma balança.` · dados: massa magra · gate: G2, mesma fonte, intervalo ≥21 dias

**`N2-COR-002`** ⭐ · ambos · *Seu peso caiu e sua massa magra não*
- `Seu peso caiu {delta} kg entre as duas medições, e sua massa magra {direcao_magra}.`
- → *"Seu peso caiu 1,8 kg entre as duas medições, e sua massa magra se manteve."*
- ctx: `Bioimpedância tem margem de erro; duas medições não fecham uma conclusão.` · dados: peso + massa magra · gate: G2, mesma balança, intervalo ≥21 dias

**`N2-COR-003`** · ambos · *Seu percentual de gordura mudou*
- `Seu percentual de gordura foi de {antes}% para {depois}%.`
- → *"Seu percentual de gordura foi de 24,1% para 22,8%."*
- ctx: `Mesma balança nas duas medições; estimativa por bioimpedância.` · dados: %gordura · gate: G2, mesma fonte, intervalo ≥21 dias

**`N2-FFM-001`** · ambos · *Seu índice de massa magra mudou*
- `Seu índice de massa magra foi de {antes} para {depois}.`
- → *"Seu índice de massa magra foi de 18,4 para 18,6."*
- ctx: `Massa magra dividida pela altura ao quadrado. Mesma balança nas duas medições.` · dados: massa magra + altura · gate: G2, mesma fonte, intervalo ≥30 dias

**`N2-WHT-001`** · ambos · *Sua relação cintura-estatura mudou* `COND: cintura`
- `Sua relação cintura-estatura foi de {antes} para {depois}.`
- → *"Sua relação cintura-estatura foi de 0,55 para 0,52."*
- ctx: `Medições de {a} e {b}.` · dados: cintura + altura · gate: G2, duas medições, intervalo ≥30 dias

**`N2-TRE-001`** · ambos · *Você treinou mais vezes*
- `Você treinou {mais_menos} vezes este mês: {atual} sessões, contra {anterior}.`
- → *"Você treinou mais vezes este mês: 14 sessões, contra 9."*
- ctx: `—` · dados: sessões · gate: G2, diferença ≥2 sessões

**`N2-TRE-002`** · ambos · *Suas sessões mudaram de duração*
- `Seus treinos ficaram {mais_menos} longos: {atual} minutos em média, contra {anterior}.`
- → *"Seus treinos ficaram mais longos: 52 minutos em média, contra 41."*
- ctx: `Mesma modalidade predominante nos dois períodos.` · dados: sessões com duração e modalidade · gate: G2, diferença ≥15%

**`N2-TRE-003`** · ambos · *Seu volume semanal mudou*
- `Seu volume de treino foi de {anterior} para {atual} horas por semana.`
- → *"Seu volume de treino foi de 2h10 para 2h50 por semana."*
- ctx: `Semanas completas nos dois períodos.` · dados: sessões com duração · gate: G2, ≥3 semanas cada, diferença ≥20%

**`N2-TRI-001`** · ambos · *Sua carga de treino mudou*
- `Sua carga semanal de treino foi de {anterior} para {atual}.`
- → *"Sua carga semanal de treino foi de 310 para 420."*
- ctx: `Carga calculada a partir da duração e da frequência cardíaca de cada sessão (TRIMP de Banister).` · dados: sessões com FC média + FC repouso + FC máxima · gate: G2, ≥3 semanas cada, mesma fonte de FC

**`N2-CAL-001`** · ambos · *Suas calorias registradas mudaram*
- `Você registrou {mais_menos} este mês: {atual} kcal por dia, contra {anterior}.`
- → *"Você registrou menos este mês: 2.180 kcal por dia, contra 2.390."*
- ctx: `Pode refletir mudança no consumo, no hábito de registrar, ou nas duas coisas.` · dados: refeições · gate: G2, ≥15 dias cada, diferença ≥10%

**`N2-PRO-001`** · ambos · *Sua proteína registrada mudou*
- `Você registrou {mais_menos} proteína: {atual} g por dia, contra {anterior}.`
- → *"Você registrou mais proteína: 118 g por dia, contra 96."*
- ctx: `Com base nos dias com registro nos dois períodos.` · dados: refeições com macros · gate: G2, ≥15 dias cada, diferença ≥10%

**`N2-ACU-001`** · ambos · *Seus açúcares registrados mudaram*
- `Os açúcares que você registra foram de {anterior}% para {atual}% das suas calorias.`
- → *"Os açúcares que você registra foram de 21% para 18% das suas calorias."*
- ctx: `Açúcares totais da tabela de alimentos, que não separa açúcar livre de açúcar naturalmente presente.` · dados: refeições com açúcares · gate: G2, ≥15 dias cada

**`N2-AGU-001`** · ambos · *Sua água registrada mudou*
- `Você registrou {mais_menos} água este mês: {atual} litros por dia, contra {anterior}.`
- → *"Você registrou menos água este mês: 1,8 litro por dia, contra 2,3."*
- ctx: `Soma do que foi anotado. Pode refletir mudança no hábito de registrar.` · dados: água · gate: G2, diferença ≥20%

**`N2-REF-001`** · ambos · *Você registrou mais refeições por dia*
- `Você registrou {atual} refeições por dia, contra {anterior} no mês anterior.`
- → *"Você registrou 3,8 refeições por dia, contra 3,1 no mês anterior."*
- ctx: `Média dos dias com algum registro.` · dados: refeições · gate: G2, ≥15 dias cada

**`N2-NAT-001`** ⭐ · ambos · *Sua proporção de alimentos in natura mudou*
- `A parcela das suas calorias vinda de alimentos in natura ou minimamente processados foi de {anterior}% para {atual}%.`
- → *"A parcela das suas calorias vinda de alimentos in natura ou minimamente processados foi de 54% para 61%."*
- ctx: `Classificação NOVA, com base em {cobertura}% das calorias que pudemos classificar.` · dados: refeições + coluna NOVA · gate: G2, ≥15 dias cada, cobertura ≥70% **declarada**

**`N2-DIV-001`** · ambos · *Sua variedade alimentar mudou*
- `Você registrou {atual} grupos alimentares diferentes por dia, contra {anterior} no mês anterior.`
- → *"Você registrou 5,2 grupos alimentares diferentes por dia, contra 4,1 no mês anterior."*
- ctx: `Dez grupos da classificação da FAO. Com base em {cobertura}% dos alimentos classificados.` · dados: refeições + grupo FAO · gate: G2, ≥15 dias cada, cobertura ≥70%

## 7.3 Contra a meta vigente

**`N2-MET-001`** · ambos · *Onde seu consumo ficou em relação à meta*
- `Seu consumo registrado ficou {delta} kcal por dia {acima_abaixo} da meta vigente no período.`
- → *"Seu consumo registrado ficou 180 kcal por dia acima da meta vigente no período."*
- ctx: `Comparado com a meta que valia em cada data. Considera apenas refeições registradas.` · dados: refeições + `objetivos_alimentares` com vigência · gate: G2, ≥15 dias, **meta histórica**

**`N2-MET-002`** · ambos · *Sua proteína em relação à meta*
- `Você registrou {g} g de proteína por dia, {delta} g {acima_abaixo} da meta do período.`
- → *"Você registrou 118 g de proteína por dia, 22 g abaixo da meta do período."*
- ctx: `Meta vigente na data de cada registro.` · dados: refeições + metas · gate: G2, ≥15 dias, meta definida

**`N2-MET-003`** · ambos · *Seu carboidrato em relação à meta*
- `Você registrou {g} g de carboidrato por dia, {delta} g {acima_abaixo} da meta do período.`
- → *"Você registrou 260 g de carboidrato por dia, 40 g abaixo da meta do período."*
- ctx: `Meta vigente na data de cada registro.` · dados: refeições + metas · gate: G2, ≥15 dias

**`N2-MET-004`** · ambos · *Sua gordura em relação à meta*
- `Você registrou {g} g de gordura por dia, {delta} g {acima_abaixo} da meta do período.`
- → *"Você registrou 78 g de gordura por dia, 6 g acima da meta do período."*
- ctx: `Meta vigente na data de cada registro.` · dados: refeições + metas · gate: G2, ≥15 dias

**`N2-MET-005`** · ambos · *Em quantos dias você ficou dentro da meta*
- `Você ficou dentro da meta de calorias em {n} dos {total} dias com registro.`
- → *"Você ficou dentro da meta de calorias em 17 dos 26 dias com registro."*
- ctx: `Faixa de tolerância de {tol}% em torno da meta vigente de cada dia.` · dados: refeições + metas · gate: G2, ≥15 dias, tolerância em config

**`N2-MET-006`** · prof · *Sua fibra em relação à meta* `COND: N30`
- `Você registrou {g} g de fibra por dia, {delta} g {acima_abaixo} da meta do período.`
- → *"Você registrou 19 g de fibra por dia, 6 g abaixo da meta do período."*
- ctx: `Meta definida pelo profissional.` · dados: refeições + fibra + metas · gate: G2, ≥15 dias
- **nota:** no app solo, fibra é exibida **sem meta** (decisão 50).

**`N2-MET-007`** · prof · *Seu sódio em relação à meta* `COND: N30`
- `Você registrou {mg} mg de sódio por dia, {delta} mg {acima_abaixo} da meta do período.`
- → *"Você registrou 2.900 mg de sódio por dia, 600 mg acima da meta do período."*
- ctx: `Meta definida pelo profissional.` · dados: refeições + sódio + metas · gate: G2, ≥15 dias

**`N2-PRO-002`** · prof · *Sua proteína por quilo em relação à faixa de referência*
- `Você registrou {gkg} g de proteína por quilo de peso. A faixa de referência definida para você é de {min} a {max}.`
- → *"Você registrou 1,4 g de proteína por quilo de peso. A faixa de referência definida para você é de 1,6 a 2,0."*
- ctx: `Faixa definida pelo profissional responsável.` · dados: refeições + peso + faixa do profissional · gate: G2, ≥15 dias
- **nota:** comparar com faixa recomendada é prescrição dietética. **Somente Painel Web.**

**`N2-PER-001`** · prof · *Sua velocidade de perda de peso*
- `Seu peso caiu {pct}% por semana no último mês. A faixa de referência definida para você é de {min}% a {max}%.`
- → *"Seu peso caiu 1,4% por semana no último mês. A faixa de referência definida para você é de 0,5% a 1,0%."*
- ctx: `Com base em {n} pesagens. Faixa definida pelo profissional.` · dados: peso seriado + faixa · gate: G2, ≥6 pesagens em 4 semanas
- **nota:** a versão descritiva sem faixa é o `N3-PER-001`. A comparação com referência é **somente Painel Web**.

**`N2-VAR-001`** · prof · *A variabilidade do seu peso*
- `Seu peso oscilou {cv}% em torno da média nas últimas {n} pesagens.`
- → *"Seu peso oscilou 1,8% em torno da média nas últimas 12 pesagens."*
- ctx: `Leitura clínica da variabilidade de peso cabe ao profissional.` · dados: peso seriado · gate: G2, ≥10 pesagens
- **nota:** a oscilação descritiva está no `N3-PES-401` e vai ao app solo. A leitura prognóstica é **somente Painel Web**.

---

# 8. NÍVEL 3 — COMPORTAMENTAL (117) — **O NÚCLEO DO PRODUTO**

> É aqui que nasce *"eu não sabia disso sobre mim"*. Todos são de concentração, estrato, dispersão, faixa habitual, bimodalidade, sequência, distribuição, intervalo ou índice publicado.

## 8.1 Família A — Concentração (9)
*O mecanismo de surpresa mais forte: o usuário se descobre diferente do que a média dizia.*

**`N3-PAS-101`** ⭐⭐ · ambos · *Metade dos seus passos vem de poucos dias*
- `Metade dos seus passos do mês veio de {n_dias} dias. Nos outros {n_resto}, você andou {passos_resto} por dia.`
- → *"Metade dos seus passos do mês veio de 6 dias. Nos outros 20, você andou 5.400 por dia."*
- ctx: `Com base em {n} dias com dado.` · dados: passos · gate: G3, ≥20 dias, `n_dias` ≤30% do período
- **leitura do usuário:** *"então eu não sou ativo — eu tenho explosões de atividade."* Muda o autoconceito, que é o efeito mais valioso possível.

**`N3-PAS-102`** ⭐ · ambos · *Seus dias mais ativos concentram quanto*
- `Seus {n} dias mais ativos somaram {pct}% de todos os seus passos do mês.`
- → *"Seus 6 dias mais ativos somaram 54% de todos os seus passos do mês."*
- ctx: `Com base em {n} dias com dado.` · dados: passos · gate: G3, ≥20 dias, `n` fixo em config

**`N3-TRE-101`** · ambos · *Seu tempo de treino se concentra em poucas sessões*
- `{fracao} do seu tempo de treino veio de {n} sessões, de um total de {total}.`
- → *"Dois terços do seu tempo de treino veio de 4 sessões, de um total de 14."*
- ctx: `—` · dados: sessões com duração · gate: G3, ≥8 sessões, ≥60% em ≤35% das sessões

**`N3-ENE-101`** · ambos · *Suas calorias se concentram em poucos dias*
- `{fracao} das calorias que você registrou no mês veio de {n} dias.`
- → *"Um terço das calorias que você registrou no mês veio de 5 dias."*
- ctx: `Considera apenas dias com registro.` · dados: refeições · gate: G3, ≥18 dias com registro

**`N3-PRO-101`** ⭐⭐ · ambos · *Sua proteína se concentra numa refeição*
- `Mais da metade da sua proteína vem do {refeicao}: {g_ref} g dos {g_dia} g do dia.`
- → *"Mais da metade da sua proteína vem do jantar: 58 g dos 112 g do dia."*
- ctx: `Média dos dias com as refeições principais registradas.` · dados: refeições com macros e tipo · gate: G3, ≥15 dias, refeição dominante ≥45%
- **base:** a distribuição de proteína entre refeições é desfecho estudado em ensaio controlado (Mamerow et al., *J Nutr* 2014). Aqui o template **apenas descreve** a distribuição observada.

**`N3-PRO-102`** ⭐ · ambos · *Em quantos dias sua proteína veio de uma só refeição*
- `Em {n} dos {total} dias, mais de metade da sua proteína veio de uma única refeição.`
- → *"Em 18 dos 26 dias, mais de metade da sua proteína veio de uma única refeição."*
- ctx: `Dias com ao menos duas refeições registradas.` · dados: refeições com macros · gate: G3, ≥15 dias

**`N3-ACU-101`** · ambos · *Seus açúcares se concentram em poucas refeições*
- `{pct}% dos açúcares que você registra vêm de {n} refeições do dia.`
- → *"70% dos açúcares que você registra vêm de duas refeições do dia."*
- ctx: `Açúcares totais da tabela de alimentos.` · dados: refeições com açúcares e tipo · gate: G3, ≥15 dias

**`N3-REP-101`** ⭐⭐ · ambos · *Cinco alimentos respondem por metade do que você come*
- `{n_poucos} alimentos responderam por metade das suas calorias no mês. Você registrou {n_total} diferentes.`
- → *"Cinco alimentos responderam por metade das suas calorias no mês. Você registrou 34 diferentes."*
- ctx: `Conta alimentos distintos do catálogo, não refeições.` · dados: refeições com ID de alimento · gate: G3, ≥15 dias, ≥10 alimentos distintos
- **leitura do usuário:** ninguém tem ideia de quão estreita é a própria dieta. Nenhum concorrente brasileiro mostra isso.

**`N3-REP-102`** ⭐ · ambos · *Seu repertório alimentar do mês*
- `Você registrou {n} alimentos diferentes no mês, e {n_novos} deles não apareciam no mês anterior.`
- → *"Você registrou 34 alimentos diferentes no mês, e 5 deles não apareciam no mês anterior."*
- ctx: `Comparação com o mês anterior; alimentos criados por você contam.` · dados: refeições com ID + histórico · gate: G3, dois meses com ≥15 dias

## 8.2 Família B — Dia útil × fim de semana (10)

**`N3-PAS-201`** ⭐⭐ · ambos · *Você anda muito mais durante a semana*
- `Você anda {comparativo} durante a semana: {uteis} passos nos dias úteis contra {fds} no sábado e domingo.`
- → *"Você anda quase o dobro durante a semana: 9.200 passos nos dias úteis contra 5.100 no sábado e domingo."*
- ctx: `{a} dias úteis e {b} de fim de semana com dado.` · dados: passos + calendário + `week_start_day` · gate: G3, ≥8 úteis e ≥4 fds, diferença ≥20%

**`N3-DIS-201`** · ambos · *Sua distância muda entre semana e fim de semana*
- `Você cobre {comparativo} distância nos dias úteis: {uteis} km contra {fds} no fim de semana.`
- → *"Você cobre o dobro da distância nos dias úteis: 6,8 km contra 3,4 no fim de semana."*
- ctx: `{a} dias úteis e {b} de fim de semana com dado.` · dados: distância + calendário · gate: G3, ≥8 úteis e ≥4 fds, diferença ≥20%

**`N3-SON-201`** ⭐ · ambos · *Você dorme mais nos fins de semana*
- `Você dorme {delta} mais nos fins de semana: {fds} contra {uteis} nos dias úteis.`
- → *"Você dorme 1h05 mais nos fins de semana: 7h50 contra 6h45 nos dias úteis."*
- ctx: `{a} noites de fim de semana e {b} de dia útil.` · dados: sono total + calendário · gate: G3, ≥4 noites fds, diferença ≥30 min

**`N3-SON-202`** ⭐⭐ · ambos · *Você acorda muito mais tarde no fim de semana* `COND: hora de acordar`
- `No sábado e no domingo você acorda {delta} mais tarde — como se mudasse de fuso horário no fim de semana.`
- → *"No sábado e no domingo você acorda 1h18 mais tarde — como se mudasse de fuso horário no fim de semana."*
- ctx: `Com base em {n} fins de semana.` · dados: horário de acordar · gate: G3, ≥4 fins de semana, diferença ≥45 min
- **nota:** a comparação com fuso horário é o que transforma um número numa sensação reconhecível. O fenômeno tem nome na literatura de cronobiologia (jet lag social, Wittmann/Roenneberg 2006) — o nome **não** aparece na tela.

**`N3-SON-203`** ⭐ · ambos · *Você vai dormir mais tarde no fim de semana* `COND: hora de dormir`
- `No fim de semana você vai para a cama {delta} mais tarde: {fds} contra {uteis} nos dias úteis.`
- → *"No fim de semana você vai para a cama 1h25 mais tarde: 00h40 contra 23h15 nos dias úteis."*
- ctx: `Com base em {n} fins de semana.` · dados: horário de dormir · gate: G3, ≥4 fins de semana, diferença ≥45 min

**`N3-ENE-201`** · ambos · *Você registra mais calorias no fim de semana*
- `Você registra {delta} kcal mais por dia no fim de semana que nos dias úteis.`
- → *"Você registra 420 kcal mais por dia no fim de semana que nos dias úteis."*
- ctx: `Considera apenas dias com registro nos dois grupos.` · dados: refeições + calendário · gate: G3, ≥4 fds e ≥8 úteis com registro, diferença ≥15%

**`N3-ACU-201`** · ambos · *Seus açúcares sobem no fim de semana*
- `No fim de semana, os açúcares respondem por {fds}% das suas calorias, contra {uteis}% nos dias úteis.`
- → *"No fim de semana, os açúcares respondem por 26% das suas calorias, contra 17% nos dias úteis."*
- ctx: `Açúcares totais da tabela de alimentos.` · dados: refeições com açúcares + calendário · gate: G3, ≥4 fds e ≥8 úteis, diferença ≥5 pontos

**`N3-TRE-201`** · ambos · *Seus treinos quase não acontecem no fim de semana*
- `Seus treinos se concentram nos dias úteis: {n} das {total} sessões foram de segunda a sexta.`
- → *"Seus treinos se concentram nos dias úteis: 12 das 14 sessões foram de segunda a sexta."*
- ctx: `—` · dados: sessões + calendário · gate: G3, ≥8 sessões, concentração ≥70%

**`N3-AGU-201`** · ambos · *Sua água registrada muda no fim de semana*
- `No fim de semana você registra {delta} ml {mais_menos} de água por dia.`
- → *"No fim de semana você registra 500 ml menos de água por dia."*
- ctx: `Soma do que foi anotado; pode refletir o hábito de registrar.` · dados: água + calendário · gate: G3, ≥4 fds e ≥8 úteis, diferença ≥15%

**`N3-NAT-201`** · ambos · *Sua alimentação muda de perfil no fim de semana*
- `A parcela de alimentos in natura cai de {uteis}% nos dias úteis para {fds}% no fim de semana.`
- → *"A parcela de alimentos in natura cai de 62% nos dias úteis para 44% no fim de semana."*
- ctx: `Classificação NOVA, com base em {cob}% das calorias classificadas.` · dados: refeições + NOVA + calendário · gate: G3, ≥4 fds e ≥8 úteis, cobertura ≥70%

## 8.3 Família C — Dia da semana específico (8)

**`N3-PAS-301`** ⭐ · ambos · *Seu dia mais ativo da semana*
- `{dia} é seu dia mais ativo: {passos} passos, contra {outros} nos outros dias.`
- → *"Quarta-feira é seu dia mais ativo: 10.400 passos, contra 6.800 nos outros dias."*
- ctx: `Com base em {n} quartas-feiras.` · dados: passos + calendário · gate: G3, ≥4 ocorrências, diferença ≥25%, **o segundo colocado claramente atrás** (sem ranking por ruído)

**`N3-PAS-302`** · ambos · *Seu dia mais parado da semana*
- `{dia} é seu dia mais parado: {passos} passos, pouco mais de {fracao} do seu melhor dia.`
- → *"Domingo é seu dia mais parado: 4.100 passos, pouco mais de um terço do seu melhor dia."*
- ctx: `Com base em {n} domingos.` · dados: passos + calendário · gate: G3, ≥4 ocorrências, separação clara do penúltimo

**`N3-SON-301`** ⭐ · ambos · *A noite da semana em que você dorme pior*
- `Suas noites de {dia} são as mais curtas: {sono}, contra {outros} nas outras.`
- → *"Suas noites de domingo são as mais curtas: 6h12, contra 7h05 nas outras."*
- ctx: `Com base em {n} noites de domingo.` · dados: sono total + calendário · gate: G3, ≥4 ocorrências, diferença ≥30 min, separação clara

**`N3-SON-302`** · ambos · *A noite da semana em que você dorme melhor*
- `Suas noites de {dia} são as mais longas: {sono}, contra {outros} nas outras.`
- → *"Suas noites de sexta são as mais longas: 8h05, contra 6h50 nas outras."*
- ctx: `Com base em {n} noites de sexta.` · dados: sono total + calendário · gate: G3, ≥4 ocorrências, diferença ≥30 min

**`N3-TRE-301`** · ambos · *Você treina quase sempre no mesmo dia*
- `Você treina quase sempre no mesmo dia: {n} das {total} sessões foram na {dia}.`
- → *"Você treina quase sempre no mesmo dia: 8 das 14 sessões foram na terça."*
- ctx: `—` · dados: sessões + calendário · gate: G3, ≥8 sessões, ≥45% num único dia

**`N3-ENE-301`** · ambos · *O dia da semana em que você come mais*
- `{dia} é o dia em que você registra mais calorias: {kcal}, contra {outros} nos outros dias.`
- → *"Sábado é o dia em que você registra mais calorias: 2.740, contra 2.090 nos outros dias."*
- ctx: `Com base em {n} sábados com registro.` · dados: refeições + calendário · gate: G3, ≥4 ocorrências, diferença ≥15%

**`N3-ALI-301`** · ambos · *O dia em que você come mais tarde*
- `Na {dia} sua primeira refeição vem {delta} mais tarde que nos outros dias.`
- → *"No domingo sua primeira refeição vem 2h10 mais tarde que nos outros dias."*
- ctx: `Mede o horário do registro.` · dados: refeições com hora + calendário · gate: G3, ≥4 ocorrências, diferença ≥45 min

**`N3-AGU-301`** · ambos · *O dia em que você bebe menos água*
- `{dia} é o dia em que você registra menos água: {ml}, contra {outros} nos outros dias.`
- → *"Domingo é o dia em que você registra menos água: 1.400 ml, contra 2.200 nos outros dias."*
- ctx: `Soma do que foi anotado.` · dados: água + calendário · gate: G3, ≥4 ocorrências, diferença ≥20%

## 8.4 Família D — Dispersão e regularidade (12)
*A família mais original do catálogo. Ninguém tem intuição da própria variância.*

**`N3-SON-401`** ⭐⭐⭐ · ambos · *Você dorme mais no mesmo horário do que acorda* `COND: hora de dormir/acordar`
- `Você dorme mais no mesmo horário do que acorda. Suas idas para a cama variaram {var_dormir} minutos; seus despertares, {var_acordar}.`
- → *"Você dorme mais no mesmo horário do que acorda. Suas idas para a cama variaram 22 minutos; seus despertares, 47."*
- ctx: `Com base em {n} noites.` · dados: horário de dormir e de acordar · gate: G3, ≥18 noites, diferença entre as variações ≥15 min
- **leitura do usuário:** *"isso eu realmente não sabia, e é o contrário do que eu imaginava — achava que acordava sempre na mesma hora por causa do despertador."* Contraintuitivo, pessoal, e impossível de calcular sozinho. **É o argumento de venda do produto.**

**`N3-SON-402`** ⭐ · ambos · *Suas noites são muito diferentes entre si*
- `Suas noites variam bastante: a mais curta do mês teve {min} e a mais longa, {max}.`
- → *"Suas noites variam bastante: a mais curta do mês teve 5h20 e a mais longa, 8h40."*
- ctx: `Com base em {n} noites com dado.` · dados: sono total · gate: G3, ≥18 noites, amplitude ≥2h30

**`N3-PAS-401`** ⭐ · ambos · *Seus dias são muito diferentes entre si*
- `Seu dia mais ativo teve {multiplo} vezes mais passos que o mais parado: {max} contra {min}.`
- → *"Seu dia mais ativo teve 4 vezes mais passos que o mais parado: 14.800 contra 3.600."*
- ctx: `Com base em {n} dias com dado.` · dados: passos · gate: G3, ≥20 dias, razão ≥3

**`N3-PES-401`** ⭐ · ambos · *Seu peso oscila mais do que parece*
- `Seu peso oscila cerca de {osc} kg entre pesagens, mesmo em dias seguidos.`
- → *"Seu peso oscila cerca de 1,2 kg entre pesagens, mesmo em dias seguidos."*
- ctx: `Com base em {n} pesagens. Oscilação diária é normal e não indica mudança de composição.` · dados: peso com data · gate: G3, ≥8 pesagens, ≥3 pares em dias consecutivos
- **nota:** raro — um insight que **reduz** ansiedade em vez de criar. Vale muito num produto de saúde.

**`N3-ALI-401`** · ambos · *O horário da sua primeira refeição varia muito*
- `O horário da sua primeira refeição registrada varia mais de {var} de um dia para o outro.`
- → *"O horário da sua primeira refeição registrada varia mais de 2 horas de um dia para o outro."*
- ctx: `Reflete quando você registra, que pode não ser quando você come.` · dados: refeições com hora · gate: G3, ≥15 dias, variação ≥90 min

**`N3-ALI-402`** · ambos · *O horário da sua última refeição varia muito*
- `O horário da sua última refeição registrada varia {var} entre os dias.`
- → *"O horário da sua última refeição registrada varia 1h50 entre os dias."*
- ctx: `Reflete quando você registra.` · dados: refeições com hora · gate: G3, ≥15 dias, variação ≥60 min

**`N3-CAL-401`** · ambos · *Suas calorias diárias variam muito*
- `Seu dia de maior registro teve {max} kcal e o de menor, {min}.`
- → *"Seu dia de maior registro teve 3.180 kcal e o de menor, 1.240."*
- ctx: `Considera apenas dias com registro completo das refeições principais.` · dados: refeições · gate: G3, ≥15 dias, razão ≥2

**`N3-PRO-401`** · ambos · *Sua proteína varia muito entre os dias*
- `Sua proteína registrada foi de {min} g no dia mais baixo a {max} g no mais alto.`
- → *"Sua proteína registrada foi de 62 g no dia mais baixo a 168 g no mais alto."*
- ctx: `Dias com as refeições principais registradas.` · dados: refeições com macros · gate: G3, ≥15 dias, razão ≥1,8

**`N3-REF-401`** ⭐ · ambos · *Qual das suas refeições é a mais previsível*
- `Seu {refeicao_estavel} é sua refeição mais previsível: varia {var_estavel} kcal entre dias. Seu {refeicao_variavel} varia {var_variavel}.`
- → *"Seu café da manhã é sua refeição mais previsível: varia 150 kcal entre dias. Seu jantar varia 600."*
- ctx: `Com base nos dias em que as duas refeições foram registradas.` · dados: refeições com kcal e tipo · gate: G3, ≥15 dias com ambas, razão entre as variações ≥2
- **nota:** clinicamente é o achado mais útil para quem acompanha alguém, e para o usuário solo é revelação pura.

**`N3-TRE-401`** · ambos · *Suas sessões variam muito de duração*
- `Seu treino mais longo teve {max} e o mais curto, {min}.`
- → *"Seu treino mais longo teve 1h50 e o mais curto, 22 minutos."*
- ctx: `Com base em {n} sessões de {modalidade}.` · dados: sessões com duração · gate: G3, ≥8 sessões, razão ≥2,5

**`N3-FCM-401`** · ambos · *Seu esforço varia entre treinos da mesma modalidade*
- `Nas suas {modalidade}, sua frequência média foi de {min} a {max} bpm.`
- → *"Nas suas corridas, sua frequência média foi de 132 a 158 bpm."*
- ctx: `Com base em {n} sessões da mesma modalidade.` · dados: sessões com FC média + modalidade · gate: G3, ≥6 sessões, **sem zona de treino nem leitura clínica**

**`N3-AGU-401`** · ambos · *Sua água registrada varia muito*
- `Seu dia de mais água registrada teve {max} ml e o de menos, {min}.`
- → *"Seu dia de mais água registrada teve 3.200 ml e o de menos, 800."*
- ctx: `Soma do que foi anotado.` · dados: água · gate: G3, ≥15 dias, razão ≥2,5

## 8.5 Família E — Faixa habitual (8)
*Melhor que média: dá ao usuário uma régua para se reconhecer.*

**`N3-SON-501`** ⭐ · ambos · *Sua faixa habitual de sono*
- `Na maioria das noites você dorme entre {min} e {max}. Foram {n_fora} noites fora dessa faixa no mês.`
- → *"Na maioria das noites você dorme entre 6h30 e 7h40. Foram 5 noites fora dessa faixa no mês."*
- ctx: `Faixa que cobre {pct}% das suas noites com dado.` · dados: sono total · gate: G3, ≥18 noites, faixa cobre 60–80%

**`N3-PAS-501`** ⭐ · ambos · *Sua faixa habitual de passos*
- `Na maioria dos dias você anda entre {min} e {max} passos.`
- → *"Na maioria dos dias você anda entre 5.800 e 8.900 passos."*
- ctx: `Faixa que cobre {pct}% dos seus dias com dado.` · dados: passos · gate: G3, ≥20 dias, faixa cobre 60–80%

**`N3-CAL-501`** · ambos · *Sua faixa habitual de calorias registradas*
- `Na maioria dos dias você registra entre {min} e {max} kcal.`
- → *"Na maioria dos dias você registra entre 1.950 e 2.480 kcal."*
- ctx: `Faixa que cobre {pct}% dos dias com registro.` · dados: refeições · gate: G3, ≥18 dias

**`N3-PRO-501`** · ambos · *Sua faixa habitual de proteína*
- `Na maioria dos dias você registra entre {min} e {max} g de proteína.`
- → *"Na maioria dos dias você registra entre 95 e 135 g de proteína."*
- ctx: `Faixa que cobre {pct}% dos dias com registro.` · dados: refeições com macros · gate: G3, ≥18 dias

**`N3-FCM-501`** · ambos · *Sua faixa de esforço nos treinos*
- `Nos seus treinos, sua frequência média fica quase sempre entre {min} e {max} bpm.`
- → *"Nos seus treinos, sua frequência média fica quase sempre entre 138 e 152 bpm."*
- ctx: `Com base em {n} sessões de {modalidade}.` · dados: sessões com FC média + modalidade · gate: G3, ≥6 sessões mesma modalidade, **sem zona nem juízo clínico**

**`N3-PES-501`** · ambos · *Sua faixa habitual de peso*
- `No último mês seu peso ficou quase sempre entre {min} e {max} kg.`
- → *"No último mês seu peso ficou quase sempre entre 82,0 e 83,4 kg."*
- ctx: `Com base em {n} pesagens.` · dados: peso · gate: G3, ≥8 pesagens

**`N3-AGU-501`** · ambos · *Sua faixa habitual de água*
- `Na maioria dos dias você registra entre {min} e {max} ml de água.`
- → *"Na maioria dos dias você registra entre 1.600 e 2.400 ml de água."*
- ctx: `Soma do que foi anotado.` · dados: água · gate: G3, ≥18 dias

**`N3-TRE-501`** · ambos · *Sua faixa habitual de duração de treino*
- `Seus treinos de {modalidade} duram quase sempre entre {min} e {max} minutos.`
- → *"Seus treinos de corrida duram quase sempre entre 35 e 52 minutos."*
- ctx: `Com base em {n} sessões.` · dados: sessões com duração + modalidade · gate: G3, ≥8 sessões mesma modalidade

## 8.6 Família F — Bimodalidade (5)
*"Eu tenho duas vidas." O efeito mais forte, e o gate mais exigente — achar duas faixas a posteriori é ajustar ruído.*

**`N3-SON-601`** ⭐ · ambos · *Suas noites se dividem em dois grupos* `COND: hora de dormir` · **gate reforçado**
- `Suas noites se dividem em dois grupos: em {n_a} delas você dormiu perto das {hora_a}; em {n_b}, perto de {hora_b}.`
- → *"Suas noites se dividem em dois grupos: em 18 delas você dormiu perto das 22h50; em 8, perto de 1h10."*
- ctx: `Com base em {n} noites.` · dados: horário de dormir · gate: G3 **reforçado** — ≥24 noites, faixas separadas ≥90 min, cada grupo ≥25%, **faixas definidas por regra fixa versionada, nunca por busca oportunista de agrupamento**
- **nota honesta:** maior potencial de impacto e maior risco metodológico do catálogo. Gate frouxo inventa padrão. Construir por último, com a regra de faixa fixada **antes** de olhar o dado. Não entra no UAU (30 dias não bastam para este gate).

**`N3-TRE-601`** · ambos · *Seus treinos têm dois formatos*
- `Seus treinos têm dois formatos: {n_curtas} sessões curtas de cerca de {dur_curta} minutos e {n_longas} longas de mais de {dur_longa}.`
- → *"Seus treinos têm dois formatos: 9 sessões curtas de cerca de 30 minutos e 5 longas de mais de 1 hora."*
- ctx: `Com base em {total} sessões de {modalidade}.` · dados: sessões com duração · gate: G3 reforçado — ≥10 sessões, separação ≥25 min, cada grupo ≥25%

**`N3-CAL-601`** · ambos · *Seus dias alimentares têm dois perfis*
- `Seus dias se dividem em dois grupos: {n_a} dias perto de {kcal_a} kcal e {n_b} perto de {kcal_b}.`
- → *"Seus dias se dividem em dois grupos: 17 dias perto de 2.050 kcal e 8 perto de 2.900."*
- ctx: `Dias com as refeições principais registradas.` · dados: refeições · gate: G3 reforçado — ≥20 dias, separação ≥500 kcal, cada grupo ≥25%

**`N3-MAC-601`** · ambos · *Seus dias se dividem entre mais carboidrato e mais gordura*
- `Em {n_a} dias o carboidrato foi seu macro dominante, com {pct_a}% das calorias; em {n_b} dias foi a gordura, com {pct_b}%.`
- → *"Em 16 dias o carboidrato foi seu macro dominante, com 52% das calorias; em 9 dias foi a gordura, com 41%."*
- ctx: `Dias com as refeições principais registradas.` · dados: refeições com macros · gate: G3 reforçado — ≥20 dias, cada grupo ≥25%

**`N3-PAS-601`** · ambos · *Seus dias de movimento têm dois padrões*
- `Seus dias se dividem em dois grupos: {n_a} dias perto de {passos_a} passos e {n_b} perto de {passos_b}.`
- → *"Seus dias se dividem em dois grupos: 17 dias perto de 9.100 passos e 9 perto de 4.200."*
- ctx: `Com base em {n} dias com dado.` · dados: passos · gate: G3 reforçado — ≥24 dias, separação ≥3.000 passos, cada grupo ≥25%

## 8.7 Família G — Sequência e persistência (6)

**`N3-PAS-701`** · ambos · *Sua maior sequência de dias ativos*
- `Sua maior sequência foi de {n} dias seguidos acima de {limiar} passos.`
- → *"Sua maior sequência foi de 11 dias seguidos acima de 7.000 passos."*
- ctx: `Limiar calculado a partir da sua própria faixa habitual, não de uma referência externa.` · dados: passos · gate: G3, ≥20 dias, sequência ≥5 dias, **limiar em config** (regra 16)

**`N3-TRE-701`** · ambos · *Seu maior intervalo sem treinar*
- `Seu maior intervalo sem treinar foi de {n} dias.`
- → *"Seu maior intervalo sem treinar foi de 3 dias."*
- ctx: `Com base em {n_sessoes} sessões no mês.` · dados: sessões com data · gate: G3, ≥6 sessões, **sem juízo** (R10)

**`N3-TRE-702`** ⭐ · ambos · *Seus treinos acontecem em blocos*
- `Seus treinos acontecem em blocos: {n_seguidos} dias seguidos, depois {n_pausa} de pausa.`
- → *"Seus treinos acontecem em blocos: três dias seguidos, depois dois de pausa."*
- ctx: `Padrão identificado em {n} ciclos do mês.` · dados: sessões com data · gate: G3, ≥10 sessões, padrão repetido ≥3 vezes
- **nota:** a estrutura do descanso é outra coisa que o maior intervalo — e ninguém mostra.

**`N3-SON-701`** · ambos · *Sua maior sequência de noites na faixa habitual*
- `Você teve {n} noites seguidas dentro da sua faixa habitual de sono.`
- → *"Você teve 9 noites seguidas dentro da sua faixa habitual de sono."*
- ctx: `Faixa habitual calculada sobre os seus próprios registros.` · dados: sono total · gate: G3, ≥18 noites, sequência ≥5

**`N3-REG-701`** · ambos · *Sua sequência de dias com registro*
- `Você registrou refeições em {n} dias seguidos.`
- → *"Você registrou refeições em 24 dias seguidos."*
- ctx: `—` · dados: refeições com data · gate: G3, sequência ≥7 dias
- **nota:** no limite da R14 — mantido em N3 porque a sequência de registro é, ela mesma, um comportamento. **Prioridade baixa.**

**`N3-NAT-701`** · ambos · *Sua sequência de dias com alimentação in natura*
- `Você teve {n} dias seguidos com mais da metade das calorias vindas de alimentos in natura.`
- → *"Você teve 7 dias seguidos com mais da metade das calorias vindas de alimentos in natura."*
- ctx: `Classificação NOVA, cobertura de {cob}%.` · dados: refeições + NOVA · gate: G3, sequência ≥5 dias, cobertura ≥70%

## 8.8 Família H — Distribuição interna (10)

**`N3-ENE-801`** ⭐ · ambos · *Onde suas calorias se concentram no dia*
- `Você concentra {pct}% das calorias que registra depois das {hora}.`
- → *"Você concentra 44% das calorias que registra depois das 19h."*
- ctx: `Faixa de horário fixa. Considera apenas refeições registradas com hora.` · dados: refeições com kcal e hora · gate: G3, ≥15 dias com ≥2 refeições, **faixa de hora em config**

**`N3-ENE-802`** · ambos · *Quanto você come antes do meio-dia*
- `{pct}% das calorias que você registra vêm antes do meio-dia.`
- → *"18% das calorias que você registra vêm antes do meio-dia."*
- ctx: `Considera refeições registradas com hora.` · dados: refeições com kcal e hora · gate: G3, ≥15 dias

**`N3-SON-801`** ⭐ · ambos · *A arquitetura da sua noite se mantém*
- `Seu sono profundo representa {pct}% da noite, e isso se manteve parecido nas {n} noites do mês.`
- → *"Seu sono profundo representa 18% da noite, e isso se manteve parecido nas 26 noites do mês."*
- ctx: `Estágios de sono estimados pelo dispositivo.` · dados: sono por estágio · gate: G3, ≥18 noites, mesma fonte, **nenhuma referência a faixa "normal" ou "ideal"**

**`N3-SON-802`** ⭐⭐ · ambos · *Suas noites mais longas não são as de mais sono profundo*
- `Seu sono profundo ficou perto de {profundo} tanto nas noites de {curta} quanto nas de {longa}.`
- → *"Seu sono profundo ficou perto de 1h10 tanto nas noites de 6 horas quanto nas de 8."*
- ctx: `Estágios estimados pelo dispositivo, com base em {n} noites.` · dados: sono total + profundo · gate: G3, ≥18 noites, ≥6 noites em cada faixa de duração, mesma fonte
- **nota:** é fisiologia do sono conhecida — o sono profundo é relativamente preservado e concentrado no início da noite. Contraintuitivo para o usuário e **dentro de uma só dimensão**, logo N3 e não N4.

**`N3-TRE-801`** · ambos · *A composição dos seus treinos*
- `{modalidade} é {pct}% do seu tempo de treino; o resto se divide entre {outras}.`
- → *"Corrida é 70% do seu tempo de treino; o resto se divide entre musculação e caminhada."*
- ctx: `Com base em {n} sessões classificadas.` · dados: sessões com modalidade e duração · gate: G3, ≥8 sessões, ≥2 modalidades

**`N3-TRE-802`** · ambos · *O horário em que você treina*
- `Você treina quase sempre de manhã: {n} das {total} sessões começaram antes das {hora}.`
- → *"Você treina quase sempre de manhã: 11 das 14 sessões começaram antes das 9h."*
- ctx: `—` · dados: sessões com hora de início · gate: G3, ≥8 sessões, concentração ≥65%

**`N3-PRO-801`** · ambos · *Como sua proteína se distribui no dia*
- `Sua proteína se divide em {pct_1}% no café, {pct_2}% no almoço e {pct_3}% no jantar.`
- → *"Sua proteína se divide em 12% no café, 33% no almoço e 48% no jantar."*
- ctx: `Média dos dias com as três refeições registradas.` · dados: refeições com macros e tipo · gate: G3, ≥15 dias com as três

**`N3-AGU-801`** · ambos · *Como sua água se distribui no dia*
- `Você registra {pct}% da sua água antes das {hora}.`
- → *"Você registra 58% da sua água antes das 14h."*
- ctx: `Mede quando você anota, que pode não ser quando você bebe.` · dados: água com timestamp · gate: G3, ≥15 dias
- **nota:** mantido em N3 apenas porque a ressalva está no corpo do contexto e o horário do registro é, em si, uma rotina. A versão sem ressalva é SUPORTE (`SUP-006`).

**`N3-AND-801`** · ambos · *Seus andares se concentram em poucos dias*
- `{pct}% dos andares que você subiu no mês vieram de {n} dias.`
- → *"62% dos andares que você subiu no mês vieram de 7 dias."*
- ctx: `Com base em {n_dias} dias com dado.` · dados: andares · gate: G3, ≥20 dias

**`N3-DEN-801`** · ambos · *A densidade calórica das suas refeições*
- `Seu {refeicao_a} tem {multiplo} a densidade calórica do seu {refeicao_b}: {dens_a} contra {dens_b} kcal por 100 g.`
- → *"Seu almoço tem o dobro da densidade calórica do seu jantar: 148 contra 74 kcal por 100 g."*
- ctx: `Com base nos dias em que as duas refeições foram registradas com quantidade.` · dados: refeições com kcal e gramas · gate: G3, ≥15 dias com ambas, razão ≥1,6

## 8.9 Família I — Intervalos entre eventos (10)
*Dimensão nova. Eu tinha horários e durações; faltava a **distância entre um evento e outro** — dado derivado que ninguém calcula e que todo mundo acha interessante sobre si.*

**`N3-INT-901`** ⭐⭐ · ambos · *Seu jejum noturno real*
- `Entre sua última refeição e a primeira do dia seguinte passam {horas}, na maioria dos dias.`
- → *"Entre sua última refeição e a primeira do dia seguinte passam 12h40, na maioria dos dias."*
- ctx: `Mede o intervalo entre registros. Com base em {n} pares de dias consecutivos.` · dados: refeições com hora · gate: G3, ≥15 pares de dias consecutivos
- **nota:** não é a janela alimentar — é o complemento dela, e é o número que a cronutrição realmente usa. Nenhum concorrente calcula.

**`N3-INT-902`** ⭐ · ambos · *Quanto tempo depois de comer você vai dormir* `COND: hora de dormir`
- `Você se deita cerca de {intervalo} depois da última refeição que registra.`
- → *"Você se deita cerca de 1h40 depois da última refeição que registra."*
- ctx: `Com base em {n} noites com os dois registros.` · dados: refeições com hora + hora de dormir · gate: G3, ≥15 noites com ambos

**`N3-INT-903`** · ambos · *Esse intervalo varia muito* `COND: hora de dormir`
- `O intervalo entre sua última refeição e a hora de dormir variou de {min} a {max} no mês.`
- → *"O intervalo entre sua última refeição e a hora de dormir variou de 20 minutos a 4 horas no mês."*
- ctx: `Com base em {n} noites com os dois registros.` · dados: refeições com hora + hora de dormir · gate: G3, ≥15 noites, amplitude ≥2h

**`N3-INT-904`** ⭐ · ambos · *Quanto tempo depois de acordar você come* `COND: hora de acordar`
- `Você faz a primeira refeição {intervalo} depois de acordar.`
- → *"Você faz a primeira refeição 2h15 depois de acordar."*
- ctx: `Mede o horário do registro. Com base em {n} dias com os dois dados.` · dados: hora de acordar + refeições com hora · gate: G3, ≥15 dias com ambos

**`N3-INT-905`** · ambos · *Quando você come depois de treinar*
- `Nos dias de treino, sua primeira refeição depois da sessão vem {intervalo} mais tarde.`
- → *"Nos dias de treino, sua primeira refeição depois da sessão vem 1h50 mais tarde."*
- ctx: `Com base em {n} sessões com refeição registrada no mesmo dia.` · dados: sessões com hora + refeições com hora · gate: G3, ≥8 sessões com refeição posterior

**`N3-INT-906`** · ambos · *Seus intervalos entre refeições variam muito*
- `Seus intervalos entre refeições vão de {min} a {max} dentro do mesmo dia.`
- → *"Seus intervalos entre refeições vão de 2 a 7 horas dentro do mesmo dia."*
- ctx: `Com base em {n} dias com ao menos três refeições registradas.` · dados: refeições com hora · gate: G3, ≥15 dias com ≥3 refeições

**`N3-INT-907`** ⭐ · ambos · *Sua janela de alimentação*
- `Entre sua primeira e sua última refeição registrada passam cerca de {horas}: das {ini} às {fim}.`
- → *"Entre sua primeira e sua última refeição registrada passam cerca de 11 horas: das 7h40 às 18h50."*
- ctx: `Mede o intervalo entre registros, que pode ser menor que o intervalo real de alimentação.` · dados: refeições com hora · gate: G3, ≥15 dias com primeira e última, **ressalva obrigatória**
- **nota:** a janela alimentar é o desfecho descrito em Gill & Panda (*Cell Metab* 2015), onde a maioria dos participantes passava de 15 horas por dia. A comparação populacional, se exibida, vive no contexto e **não no corpo**.

**`N3-INT-908`** · ambos · *Sua janela de alimentação varia entre os dias*
- `Sua janela de alimentação foi de {min} no dia mais curto a {max} no mais longo.`
- → *"Sua janela de alimentação foi de 8 horas no dia mais curto a 15 no mais longo."*
- ctx: `Mede o intervalo entre registros.` · dados: refeições com hora · gate: G3, ≥15 dias, amplitude ≥4h

**`N3-INT-909`** · ambos · *Quanto tempo você espera entre treinos*
- `Entre seus treinos passam {intervalo}, na maioria das vezes.`
- → *"Entre seus treinos passam 2 dias, na maioria das vezes."*
- ctx: `Com base em {n} intervalos entre sessões.` · dados: sessões com data · gate: G3, ≥8 sessões

**`N3-INT-910`** · ambos · *Quando no dia você treina em relação a acordar* `COND: hora de acordar`
- `Você treina {intervalo} depois de acordar, na maioria das sessões.`
- → *"Você treina 2h30 depois de acordar, na maioria das sessões."*
- ctx: `Com base em {n} sessões com hora de acordar no mesmo dia.` · dados: hora de acordar + sessões com hora · gate: G3, ≥8 sessões com ambos

## 8.10 Família J — Índices publicados de sono (6)

**`N3-EFI-001`** ⭐ · ambos · *Sua eficiência de sono*
- `Você passa {acordado} acordado por noite, somados em despertares curtos. Sua eficiência de sono foi de {pct}%.`
- → *"Você passa 42 minutos acordado por noite, somados em despertares curtos. Sua eficiência de sono foi de 91%."*
- ctx: `Eficiência é o tempo dormido sobre o tempo total na cama. Estimado pelo dispositivo.` · dados: sono total + acordado · gate: G3, ≥18 noites, mesma fonte
- **nota:** eficiência de sono e tempo acordado após o início do sono são métricas padrão de actigrafia. **O campo `acordado_min` já existe e estava sem uso em todo o catálogo anterior.**

**`N3-EFI-002`** · ambos · *Seus despertares variam entre as noites*
- `Seu tempo acordado por noite foi de {min} na melhor noite a {max} na pior.`
- → *"Seu tempo acordado por noite foi de 12 minutos na melhor noite a 1h20 na pior."*
- ctx: `Estimado pelo dispositivo, com base em {n} noites.` · dados: acordado · gate: G3, ≥18 noites, amplitude ≥30 min

**`N3-DEB-001`** · ambos · *Seu acúmulo de sono abaixo da faixa habitual*
- `Você somou {deficit} abaixo da sua faixa habitual de sono ao longo do mês.`
- → *"Você somou 6h20 abaixo da sua faixa habitual de sono ao longo do mês."*
- ctx: `Comparado com a sua própria faixa habitual, não com uma referência externa.` · dados: sono total · gate: G3, ≥20 noites, **nenhuma referência a "necessidade de sono"**

**`N3-JET-001`** ⭐⭐ · ambos · *Seu sono se desloca no fim de semana* `COND: hora de dormir/acordar`
- `O meio da sua noite cai {delta} mais tarde no fim de semana que nos dias úteis.`
- → *"O meio da sua noite cai 1h10 mais tarde no fim de semana que nos dias úteis."*
- ctx: `Com base em {a} noites de dia útil e {b} de fim de semana.` · dados: horário de dormir e de acordar + calendário · gate: G3, ≥4 fins de semana, diferença ≥30 min
- **nota:** é o jet lag social (Wittmann/Roenneberg, *Chronobiology International* 2006), onde mais de 70% das pessoas têm pelo menos uma hora. **O nome do índice não aparece na tela.**

**`N3-REG-001`** · ambos · *A regularidade do seu sono* `COND: hora de dormir/acordar`
- `Seus horários de sono coincidiram de um dia para o outro em {pct}% do tempo.`
- → *"Seus horários de sono coincidiram de um dia para o outro em 78% do tempo."*
- ctx: `Calculado por aproximação de bloco único de sono, com método declarado em {versao}.` · dados: horário de dormir e de acordar · gate: G3, ≥20 noites consecutivas
- **nota de honestidade obrigatória:** o Sleep Regularity Index de Phillips et al. (2017) é definido por época ao longo das 24 horas, e existe esforço formal em curso (declaração RIRI) porque implementações open-source divergem do mesmo dado. **Esta é uma aproximação de bloco único e não deve ser chamada de SRI** em nenhuma superfície.

**`N3-SON-901`** · ambos · *Seu horário habitual de dormir* `COND: hora de dormir`
- `Na maioria das noites você vai para a cama entre {min} e {max}.`
- → *"Na maioria das noites você vai para a cama entre 22h40 e 23h25."*
- ctx: `Faixa que cobre {pct}% das suas noites com dado.` · dados: horário de dormir · gate: G3, ≥18 noites

## 8.11 Família K — Índices publicados de treino (8)

**`N3-TRI-001`** ⭐ · ambos · *Sua carga de treino da semana*
- `Sua semana mais pesada do mês teve {multiplo} a carga da mais leve: {max} contra {min}.`
- → *"Sua semana mais pesada do mês teve o triplo da carga da mais leve: 520 contra 170."*
- ctx: `Carga calculada a partir da duração e da frequência cardíaca de cada sessão (TRIMP de Banister).` · dados: sessões com FC média + FC repouso + FC máxima · gate: G3, ≥3 semanas com sessão, razão ≥2
- **nota:** TRIMP é carga de treino publicada e **não exige percepção de esforço**, que o Orynty não coleta.

**`N3-MON-001`** · ambos · *Suas semanas são parecidas ou irregulares entre si*
- `Em {n} das {total} semanas do mês, quase todo o seu volume veio de {n_dias} dias.`
- → *"Em 3 das 4 semanas do mês, quase todo o seu volume veio de 2 dias."*
- ctx: `Concentração calculada sobre a duração das sessões de cada semana.` · dados: sessões com duração e data · gate: G3, ≥3 semanas com ≥2 sessões
- **nota:** é a monotonia de Foster escrita sem a razão — média dividida pelo desvio padrão não vai para a tela (R5). A literatura própria da monotonia admite o cálculo só com duração quando não há percepção de esforço, e critica que o índice é dominado pela duração: **o proxy fica declarado**.

**`N3-CAR-001`** · ambos · *Seu volume de treino se concentra numa semana*
- `{pct}% do seu tempo de treino do mês caiu numa única semana.`
- → *"41% do seu tempo de treino do mês caiu numa única semana."*
- ctx: `Com base em {n} semanas com sessão.` · dados: sessões com duração e data · gate: G3, ≥3 semanas, concentração ≥35%

**`N3-EFF-001`** ⭐ · ambos · *Sua relação entre ritmo e esforço*
- `Nas suas {modalidade}, você manteve {vel} km/h a {fc} bpm, em média.`
- → *"Nas suas corridas, você manteve 10,2 km/h a 148 bpm, em média."*
- ctx: `Com base em {n} sessões da mesma modalidade. Relação entre velocidade e frequência cardíaca é métrica de prática de treinamento, não índice revisado por pares.` · dados: sessões com velocidade média + FC média + modalidade · gate: G3, ≥6 sessões mesma modalidade

**`N3-INT-001`** · ambos · *A distribuição de esforço dos seus treinos*
- `{pct}% do seu tempo de treino aconteceu numa faixa média de esforço; {pct_leve}% em faixa mais leve e {pct_forte}% em faixa mais forte.`
- → *"68% do seu tempo de treino aconteceu numa faixa média de esforço; 19% em faixa mais leve e 13% em faixa mais forte."*
- ctx: `Faixas definidas sobre a sua própria distribuição de frequência cardíaca registrada, não sobre zonas de referência.` · dados: sessões com FC média e duração · gate: G3, ≥10 sessões, **nenhuma zona de treino nomeada, nenhuma leitura clínica**

**`N3-NEA-001`** ⭐⭐ · ambos · *Quanto você se move fora dos treinos*
- `Fora dos treinos, você anda {passos} passos por dia — e isso quase não muda entre dias de treino e de descanso.`
- → *"Fora dos treinos, você anda 4.100 passos por dia — e isso quase não muda entre dias de treino e de descanso."*
- ctx: `Passos do dia menos os passos da própria sessão. Com base em {n} dias.` · dados: passos + sessões com passos · gate: G3, ≥8 dias em cada grupo, **passos da sessão descontados**
- **nota:** separar movimento de treino de movimento de rotina é o que explica mais variação de gasto que o treino em si. Nenhum concorrente mostra.

**`N3-VOL-001`** · ambos · *Seu volume por modalidade*
- `Você somou {horas_a} de {modalidade_a} e {horas_b} de {modalidade_b} no mês.`
- → *"Você somou 7h20 de corrida e 3h10 de musculação no mês."*
- ctx: `Com base em {n} sessões classificadas.` · dados: sessões com modalidade e duração · gate: G3, ≥6 sessões, ≥2 modalidades

**`N3-CAD-001`** · ambos · *Seu ritmo de caminhada mais forte do dia* `COND: passos intradiários`
- `Nos seus 30 minutos mais ativos do dia, você andou a {cadencia} passos por minuto.`
- → *"Nos seus 30 minutos mais ativos do dia, você andou a 94 passos por minuto."*
- ctx: `Média dos dias com dado minuto a minuto.` · dados: passos intradiários · gate: G3, ≥15 dias com dado granular
- **nota:** cadência de pico de 30 minutos é medida de intensidade em vida livre com valores normativos publicados (NHANES). **Depende de o Orynty guardar passos intradiários, não só o total do dia — a verificar.**

## 8.12 Família L — Atividade e composição publicados (6)

**`N3-WEE-001`** ⭐ · ambos · *Seu padrão de atividade concentrado no fim de semana*
- `{pct}% da sua atividade registrada no mês aconteceu no sábado e no domingo.`
- → *"58% da sua atividade registrada no mês aconteceu no sábado e no domingo."*
- ctx: `Com base em {n} sessões.` · dados: sessões + calendário · gate: G3, ≥8 sessões, concentração ≥50%
- **nota:** o padrão "weekend warrior" tem literatura própria de desfechos (O'Donovan et al., *JAMA Intern Med* 2017; revisitado com dado de passos em *JAMA Netw Open* 2023). Aqui **apenas a descrição**.

**`N3-LIM-001`** · ambos · *Em quantos dias você passou da sua faixa de referência de passos*
- `Você passou de {limiar} passos em {n} dos {total} dias.`
- → *"Você passou de 7.000 passos em 19 dos 26 dias."*
- ctx: `Limiar em tabela de configuração, versionado com a fonte.` · dados: passos · gate: G3, ≥20 dias, **limiar em config** (regra 16)

**`N3-FFM-001`** · ambos · *Seu índice de massa magra*
- `Sua massa magra corresponde a um índice de {ffmi}.`
- → *"Sua massa magra corresponde a um índice de 18,6."*
- ctx: `Massa magra dividida pela altura ao quadrado. Medição de {data}, por bioimpedância.` · dados: massa magra + altura · gate: G3, medição <45 dias
- **nota:** a comparação com valores normativos é `prof`. Aqui só o número.

**`N3-PER-001`** ⭐ · ambos · *Sua velocidade de perda de peso e sua massa magra*
- `Seu peso caiu {pct}% por semana no último mês. Sua massa magra {direcao_magra} {delta_magra} kg no mesmo período.`
- → *"Seu peso caiu 1,4% por semana no último mês. Sua massa magra caiu 0,8 kg no mesmo período."*
- ctx: `Com base em {n} pesagens e {m} medições de composição, pela mesma balança.` · dados: peso seriado + massa magra · gate: G3, ≥6 pesagens e ≥2 medições de composição
- **nota:** a comparação com faixa de referência é `N2-PER-001`, **somente Painel Web**. Esta versão **descreve os dois fatos lado a lado**, sem referência e sem juízo.

**`N3-OSC-001`** · ambos · *A oscilação do seu peso no mês*
- `Seu peso oscilou entre {min} e {max} kg no mês, numa amplitude de {amp} kg.`
- → *"Seu peso oscilou entre 82,0 e 84,2 kg no mês, numa amplitude de 2,2 kg."*
- ctx: `Com base em {n} pesagens. Oscilação entre dias é normal.` · dados: peso seriado · gate: G3, ≥8 pesagens

**`N3-WHT-002`** · ambos · *Sua cintura em relação à sua altura* `COND: cintura`
- `Sua cintura corresponde a {pct}% da sua altura.`
- → *"Sua cintura corresponde a 52% da sua altura."*
- ctx: `Medição de {data}. A faixa de referência {faixa} vem da diretriz NICE NG7 (2022).` · dados: cintura + altura · gate: G3, **faixa omitida se IMC ≥35**

## 8.13 Família M — Índices publicados de nutrição (8)

**`N3-DIS-001`** ⭐⭐ · ambos · *Como sua proteína se distribui entre as refeições*
- `Sua proteína está concentrada no {refeicao}: {g_ref} g de um total de {g_dia} g. Nas outras duas refeições somadas, você registrou {g_outras} g.`
- → *"Sua proteína está concentrada no jantar: 58 g de um total de 112 g. Nas outras duas refeições somadas, você registrou 31 g."*
- ctx: `Média dos dias com as três refeições registradas.` · dados: refeições com macros e tipo · gate: G3, ≥15 dias com as três
- **nota:** a distribuição de proteína entre refeições foi testada em ensaio controlado com desfecho de síntese proteica (Mamerow et al., *J Nutr* 2014). **O template descreve a distribuição; a interpretação cabe ao profissional.** A versão com referência é `prof`.

**`N3-JAN-001`** ⭐ · ambos · *Sua janela alimentar comparada à literatura*
- `Entre sua primeira e sua última refeição registrada passam {horas}.`
- → *"Entre sua primeira e sua última refeição registrada passam 14h20."*
- ctx: `No estudo que descreveu esse padrão pela primeira vez, a maioria das pessoas também passava de 15 horas. Mede o intervalo entre registros.` · dados: refeições com hora · gate: G3, ≥15 dias
- **nota:** a comparação populacional vive **no contexto**, nunca no corpo, e descreve o estudo — não instrui o usuário. É o que mantém o template dentro da finalidade de bem-estar.

**`N3-EJE-001`** ⭐ · ambos · *Seus horários de refeição se deslocam no fim de semana*
- `O meio da sua janela alimentar cai {delta} mais tarde no fim de semana.`
- → *"O meio da sua janela alimentar cai 1h35 mais tarde no fim de semana."*
- ctx: `Com base em {a} dias úteis e {b} de fim de semana com registro.` · dados: refeições com hora + calendário · gate: G3, ≥4 fds e ≥8 úteis, diferença ≥30 min
- **nota:** o deslocamento do horário das refeições entre dias úteis e fim de semana tem literatura própria (Zerón-Rugerio et al., *Nutrients* 2019; coorte Go Red for Women, *JAHA* 2022). **Limiar de referência a confirmar antes de exibir qualquer comparação populacional.**

**`N3-ACU-001`** · ambos · *Quanto das suas calorias vem de açúcares*
- `Os açúcares respondem por {pct}% das calorias que você registra.`
- → *"Os açúcares respondem por 18% das calorias que você registra."*
- ctx: `Açúcares totais da tabela de alimentos, que não separa açúcar livre de açúcar naturalmente presente. Comparação com recomendação exigiria essa separação.` · dados: refeições com açúcares · gate: G3, ≥15 dias
- **limite declarado:** a TACO traz açúcares totais. **Não é possível afirmar conformidade com recomendação de açúcar livre.** A ressalva é obrigatória.

**`N3-GKG-001`** · ambos · *Sua proteína por quilo de peso*
- `Você registrou {gkg} g de proteína por quilo de peso, em média.`
- → *"Você registrou 1,4 g de proteína por quilo de peso, em média."*
- ctx: `Peso da sua última pesagem. Com base nos dias com registro.` · dados: refeições com macros + peso · gate: G3, ≥15 dias
- **nota:** gramas absolutos não dizem nada clinicamente; por quilo, sim. A comparação com faixa recomendada é `N2-PRO-002`, **somente Painel Web**.

**`N3-DIV-001`** ⭐⭐ · ambos · *Sua variedade alimentar*
- `Você registrou {n_grupos} dos dez grupos alimentares por dia, em média.`
- → *"Você registrou 5,2 dos dez grupos alimentares por dia, em média."*
- ctx: `Dez grupos da classificação da FAO. Com base em {cob}% dos alimentos que pudemos classificar.` · dados: refeições + grupo FAO · gate: G3, ≥15 dias, cobertura ≥70% **declarada**

**`N3-DIV-002`** · ambos · *Os grupos que quase não aparecem no seu registro*
- `{grupos} apareceram em menos de {n} dos {total} dias com registro.`
- → *"Folhosos verde-escuros e leguminosas apareceram em menos de 5 dos 26 dias com registro."*
- ctx: `Dez grupos da classificação da FAO. Cobertura de {cob}%.` · dados: refeições + grupo FAO · gate: G3, ≥15 dias, cobertura ≥70%, **sem juízo** (R10)

**`N3-NAT-001`** ⭐⭐ · ambos · *Quanto você come de alimento in natura*
- `{pct}% das calorias que você registrou vieram de alimentos in natura ou minimamente processados.`
- → *"58% das calorias que você registrou vieram de alimentos in natura ou minimamente processados."*
- ctx: `Classificação NOVA, criada na USP e usada no Guia Alimentar para a População Brasileira. Com base em {cob}% das calorias que pudemos classificar.` · dados: refeições + coluna NOVA · gate: G3, ≥15 dias, cobertura ≥70% **declarada no corpo do contexto**
- **nota:** métrica invertida de propósito. O grupo 1 do NOVA é inequívoco e dispensa a fronteira difícil entre grupo 3 e grupo 4 — que depende de validação por nutricionista e está em `backlog`. E "prefira alimentos in natura ou minimamente processados" é a recomendação principal do próprio Guia Alimentar.

## 8.14 Família N — Somente Painel Web (11)

> Carregam referência clínica, meta ou leitura prognóstica. O profissional responde por elas.

**`N3-EA-001`** ⭐ · prof · *Sua disponibilidade energética*
- `Sua disponibilidade energética no período foi de {ea} kcal por quilo de massa magra por dia.`
- → *"Sua disponibilidade energética no período foi de 28 kcal por quilo de massa magra por dia."*
- ctx: `Ingestão registrada menos gasto das sessões, dividido pela massa magra. Depende da completude do registro alimentar.` · dados: refeições + calorias de sessão + massa magra · gate: G3, ≥14 dias com os três
- **nota:** baixa disponibilidade energética é diagnóstico clínico (consenso IOC 2023 sobre REDs). **Nunca no app solo.** Nenhuma ferramenta brasileira calcula isso a partir de telemetria — é argumento de venda B2B sozinho.

**`N3-EA-002`** · prof · *Os dias de disponibilidade energética mais baixa*
- `Em {n} dos {total} dias, sua disponibilidade energética ficou abaixo de {limiar} kcal por quilo de massa magra.`
- → *"Em 8 dos 26 dias, sua disponibilidade energética ficou abaixo de 30 kcal por quilo de massa magra."*
- ctx: `Limiar definido pelo profissional. Depende da completude do registro.` · dados: idem · gate: G3, ≥14 dias, limiar em config

**`N3-MON-002`** · prof · *Leitura de carga e monotonia da semana*
- `Sua carga semanal foi {carga} com concentração em {n_dias} dias. A faixa de referência definida para você é {faixa}.`
- → *"Sua carga semanal foi 520 com concentração em 2 dias. A faixa de referência definida para você é 300 a 450."*
- ctx: `Faixa definida pelo profissional.` · dados: sessões + FC + faixa · gate: G3, ≥3 semanas

**`N3-INT-002`** · prof · *Leitura da distribuição de intensidade*
- `{pct}% do seu tempo de treino ficou na faixa média de esforço, contra a distribuição de referência de {referencia}.`
- → *"68% do seu tempo de treino ficou na faixa média de esforço, contra a distribuição de referência de 20%."*
- ctx: `Distribuição de referência definida pelo profissional.` · dados: sessões com FC + referência · gate: G3, ≥10 sessões

**`N3-FFM-002`** · prof · *Seu índice de massa magra em relação à referência*
- `Seu índice de massa magra é {ffmi}. A faixa de referência para seu perfil é de {min} a {max}.`
- → *"Seu índice de massa magra é 18,6. A faixa de referência para seu perfil é de 18,0 a 20,0."*
- ctx: `Faixa definida pelo profissional; bioimpedância tem margem de erro.` · dados: massa magra + altura + faixa · gate: G3

**`N3-DIS-002`** · prof · *Sua distribuição de proteína em relação à referência*
- `Em {n} das {total} refeições registradas, a proteína ficou abaixo de {limiar} g. A distribuição de referência definida para você é {ref} g por refeição.`
- → *"Em 42 das 78 refeições registradas, a proteína ficou abaixo de 25 g. A distribuição de referência definida para você é 30 g por refeição."*
- ctx: `Referência definida pelo profissional.` · dados: refeições com macros + referência · gate: G3, ≥15 dias

**`N3-FIB-001`** · prof · *Sua fibra registrada* `COND: N30`
- `Você registrou {g} g de fibra por dia, em média.`
- → *"Você registrou 19 g de fibra por dia, em média."*
- ctx: `Com base nos dias com registro.` · dados: refeições + fibra · gate: G3, ≥15 dias
- **nota:** no app solo, fibra aparece **sem meta e sem referência** (decisão 50) — nesse caso o template é o `N1`-equivalente de exibição, não descoberta.

**`N3-SOD-001`** · prof · *Seu sódio registrado* `COND: N30`
- `Você registrou {mg} mg de sódio por dia, em média.`
- → *"Você registrou 2.900 mg de sódio por dia, em média."*
- ctx: `Com base nos dias com registro.` · dados: refeições + sódio · gate: G3, ≥15 dias

**`N3-UPF-001`** · backlog · *Quanto você come de ultraprocessado*
- `{pct}% das calorias que você registrou vieram de alimentos ultraprocessados.`
- → *"46% das calorias que você registrou vieram de alimentos ultraprocessados."*
- ctx: `Classificação NOVA, com base em {cob}% das calorias classificadas.` · dados: refeições + NOVA grupo 4 · gate: G3, cobertura ≥70%
- **bloqueio:** depende da validação da fronteira entre grupo 3 e grupo 4 por nutricionista. **Backlog até haver parceiro.** A versão liberada é o `N3-NAT-001` (grupo 1, inequívoco).

**`N3-UPF-002`** · backlog · *Seu ultraprocessado comparado à população*
- `{pct}% das suas calorias vieram de ultraprocessados.`
- → *"46% das suas calorias vieram de ultraprocessados."*
- ctx: `No ensaio que testou isso de forma controlada, pessoas comendo dieta ultraprocessada consumiram cerca de 500 kcal por dia a mais, com o mesmo valor nutricional no prato.` · dados: idem · gate: idem
- **bloqueio:** idem. A citação é de Hall et al. (*Cell Metab* 2019) e descreve o ensaio, não instrui o usuário.

**`N3-UPF-003`** · backlog · *Onde seu ultraprocessado se concentra*
- `{pct}% dos ultraprocessados que você registra aparecem no {refeicao}.`
- → *"62% dos ultraprocessados que você registra aparecem no jantar."*
- ctx: `Classificação NOVA, cobertura de {cob}%.` · dados: refeições + NOVA + tipo · gate: G3, cobertura ≥70%
- **bloqueio:** idem.

---

# 9. NÍVEL 4 — COMPARATIVO MULTIDIMENSIONAL (38)

> **Renomeado.** Era "Associativo" no v1.2. A palavra prometia exatamente o que a regra proíbe, e vocabulário interno vaza para a interface com o tempo.
>
> **Permissão:** pela **Regra 28 revista** (Mestre, Parte 0), comparar grupos de dias observados é permitido quando o cruzamento consta de `perguntas_analiticas`, cada grupo atinge o tamanho mínimo, a dispersão aparece junto da diferença, e a frase descreve os grupos sem afirmar vínculo.
>
> **Marcação:** `lib:v1` consta da primeira versão da biblioteca e é publicável · `lib:pendente` escrito e **inativo**, aguardando revisor nomeado · `R25` travado pela pendência regulatória de frequência cardíaca, não pela regra 28.
>
> **Redação obrigatória:** descreve os grupos, nunca o vínculo. *"Nas noites depois de um treino"* descreve o grupo. *"Treinar melhora seu sono"* afirma causa — proibido, inclusive por insinuação ("coincidiu com", "por isso", "graças a").

## 9.1 Sono e treino (5)

**`N4-SON-TRE-001`** ⭐⭐⭐ · ambos · `lib:v1` · *Você dorme mais depois de treinar*
- `Nas noites depois de um treino, você dormiu {delta} mais: {com} contra {sem} nas outras noites.`
- → *"Nas noites depois de um treino, você dormiu 34 minutos mais: 7h22 contra 6h48 nas outras noites."*
- ctx: `{a} noites depois de treino e {b} noites sem. A duração variou {disp_a} e {disp_b} em cada grupo.` · dados: sessões + sono total · gate: G4, ≥8 noites por grupo, controle de dia da semana
- **nota:** é a frase que vende o produto. Primeira a construir depois dos dois do fosso.

**`N4-SON-TRE-002`** · ambos · `lib:v1` · *Seu sono depois de treinos longos e curtos*
- `Depois dos seus treinos mais longos, você dormiu {sono_a}; depois dos mais curtos, {sono_b}.`
- → *"Depois dos seus treinos mais longos, você dormiu 7h30; depois dos mais curtos, 6h55."*
- ctx: `{a} e {b} noites em cada grupo; faixas de duração definidas antes da análise.` · dados: sessões com duração + sono · gate: G4, ≥6 por grupo, faixas em config

**`N4-SON-TRE-003`** · ambos · `lib:v1` · *Seu sono depois de treinar de manhã ou de tarde*
- `Depois de treinos até as {hora}, você dormiu {sono_a}; depois de treinos mais tarde, {sono_b}.`
- → *"Depois de treinos até as 10h, você dormiu 7h20; depois de treinos mais tarde, 6h50."*
- ctx: `{a} e {b} noites em cada grupo; faixa horária fixada antes da análise.` · dados: sessões com hora + sono · gate: G4, ≥6 por grupo

**`N4-SON-TRE-004`** ⭐ · ambos · `lib:v1` · *A diferença muda entre semana e fim de semana*
- `A diferença de sono entre dias com e sem treino foi de {delta_uteis} nos dias úteis e {delta_fds} no fim de semana.`
- → *"A diferença de sono entre dias com e sem treino foi de 28 minutos nos dias úteis e 6 minutos no fim de semana."*
- ctx: `Cada grupo com ao menos {n} noites. A separação por tipo de dia evita atribuir ao treino o que é do calendário.` · dados: sessões + sono + calendário · gate: G4, ≥6 por célula
- **nota:** tecnicamente o mais correto do catálogo — controla o dia da semana, que é exatamente o fator de confusão que a regra pede para tratar.

**`N4-SON-TRE-005`** · ambos · `lib:v1` · *Sua regularidade de sono em semanas de mais treino* `COND: hora de dormir`
- `Nas semanas com mais sessões registradas, seu horário de dormir variou {var_a}; nas outras, {var_b}.`
- → *"Nas semanas com mais sessões registradas, seu horário de dormir variou 26 minutos; nas outras, 48."*
- ctx: `{a} e {b} semanas em cada grupo.` · dados: sessões + horário de dormir · gate: G4, ≥4 semanas por grupo

## 9.2 Movimento e sono (3)

**`N4-PAS-SON-001`** ⭐⭐ · ambos · `lib:v1` · *Noites curtas e o dia seguinte*
- `Depois das suas noites mais curtas, você andou {passos_a}; depois das mais longas, {passos_b}.`
- → *"Depois das suas noites mais curtas, você andou 5.300 passos; depois das mais longas, 7.200."*
- ctx: `{a} e {b} dias em cada grupo; faixas de duração de sono definidas antes da análise. Variação de {disp_a} e {disp_b}.` · dados: sono + passos pareados D→D+1 · gate: G4, ≥8 por grupo, controle de dia da semana

**`N4-PAS-SON-002`** · ambos · `lib:v1` · *Seus dias depois das melhores noites*
- `Nos dias seguintes às noites dentro da sua faixa habitual, você andou {passos_a}; nos outros, {passos_b}.`
- → *"Nos dias seguintes às noites dentro da sua faixa habitual, você andou 7.100 passos; nos outros, 5.600."*
- ctx: `Faixa habitual calculada sobre os seus próprios registros. {a} e {b} dias.` · dados: sono + passos · gate: G4, ≥8 por grupo

**`N4-SON-PAS-001`** · ambos · `lib:v1` · *Seu sono depois dos dias de mais movimento*
- `Depois dos seus dias de mais passos, você dormiu {sono_a}; depois dos de menos, {sono_b}.`
- → *"Depois dos seus dias de mais passos, você dormiu 7h15; depois dos de menos, 6h50."*
- ctx: `{a} e {b} noites; faixas de passos definidas antes da análise.` · dados: passos + sono pareados D→D+1 · gate: G4, ≥8 por grupo

## 9.3 Alimentação e sono (5)

**`N4-SON-ALI-001`** ⭐⭐ · ambos · `lib:v1` · *Jantar tarde e suas noites*
- `Nas noites em que sua última refeição registrada foi depois das {hora}, você dormiu {sono_a}; nas outras, {sono_b}.`
- → *"Nas noites em que sua última refeição registrada foi depois das 21h, você dormiu 6h40; nas outras, 7h06."*
- ctx: `Faixa de hora fixada antes da análise. Mede o horário do registro. {a} e {b} noites.` · dados: refeições com hora + sono · gate: G4, ≥8 por grupo

**`N4-SON-ALI-002`** · ambos · `lib:v1` · *O intervalo entre comer e dormir* `COND: hora de dormir`
- `Nas noites em que você se deitou menos de {limiar} depois de comer, dormiu {sono_a}; nas outras, {sono_b}.`
- → *"Nas noites em que você se deitou menos de 1 hora depois de comer, dormiu 6h35; nas outras, 7h10."*
- ctx: `Limiar fixado antes da análise. {a} e {b} noites.` · dados: refeições com hora + hora de dormir + sono · gate: G4, ≥8 por grupo

**`N4-SON-ACU-001`** · ambos · `lib:v1` · *Seus açúcares e a noite seguinte*
- `Nas noites depois dos dias de mais açúcar registrado, você dormiu {sono_a}; depois dos de menos, {sono_b}.`
- → *"Nas noites depois dos dias de mais açúcar registrado, você dormiu 6h50; depois dos de menos, 7h12."*
- ctx: `Faixas de açúcar definidas antes da análise; dias com as refeições principais registradas. {a} e {b} noites.` · dados: refeições com açúcares + sono · gate: G4, ≥8 por grupo, cobertura declarada

**`N4-SON-CAL-001`** · ambos · `lib:pendente` · *Suas calorias e a noite seguinte*
- `Nas noites depois dos dias de mais calorias registradas, você dormiu {sono_a}; depois dos de menos, {sono_b}.`
- → *"Nas noites depois dos dias de mais calorias registradas, você dormiu 6h55; depois dos de menos, 7h08."*
- ctx: `Faixas definidas antes da análise. {a} e {b} noites.` · dados: refeições + sono · gate: G4, ≥8 por grupo

**`N4-DOR-ALI-001`** · ambos · `lib:v1` · *Comer tarde e a hora de ir para a cama* `COND: hora de dormir`
- `Nos dias em que sua última refeição foi depois das {hora}, você foi para a cama {delta} mais tarde.`
- → *"Nos dias em que sua última refeição foi depois das 21h, você foi para a cama 48 minutos mais tarde."*
- ctx: `Faixa de hora fixada antes da análise. {a} e {b} noites.` · dados: refeições com hora + hora de dormir · gate: G4, ≥8 por grupo

## 9.4 Alimentação e treino (5)

**`N4-CAL-TRE-001`** · ambos · `lib:v1` · *Você come mais nos dias que treina*
- `Nos dias de treino você registrou {kcal_a} kcal; nos dias sem, {kcal_b}.`
- → *"Nos dias de treino você registrou 2.480 kcal; nos dias sem, 2.100."*
- ctx: `{a} e {b} dias com registro em cada grupo; cobertura parecida nos dois.` · dados: sessões + refeições · gate: G4, ≥8 por grupo, controle de dia da semana

**`N4-PRO-TRE-001`** · ambos · `lib:v1` · *Sua proteína nos dias de treino*
- `Nos dias de treino você registrou {g_a} g de proteína; nos dias sem, {g_b} g.`
- → *"Nos dias de treino você registrou 128 g de proteína; nos dias sem, 104 g."*
- ctx: `{a} e {b} dias com registro em cada grupo.` · dados: sessões + refeições com macros · gate: G4, ≥8 por grupo

**`N4-CAR-TRE-001`** · ambos · `lib:v1` · *Seu carboidrato nos dias de treino*
- `Nos dias de treino você registrou {g_a} g de carboidrato; nos dias sem, {g_b} g.`
- → *"Nos dias de treino você registrou 290 g de carboidrato; nos dias sem, 240 g."*
- ctx: `{a} e {b} dias com registro em cada grupo.` · dados: sessões + refeições com macros · gate: G4, ≥8 por grupo

**`N4-AGU-TRE-001`** · ambos · `lib:v1` · *Sua água registrada nos dias de treino*
- `Nos dias de treino você registrou {ml_a} ml de água; nos dias sem, {ml_b} ml.`
- → *"Nos dias de treino você registrou 2.600 ml de água; nos dias sem, 1.900 ml."*
- ctx: `Soma do que foi anotado; pode refletir o hábito de registrar em dias de treino.` · dados: sessões + água · gate: G4, ≥8 por grupo
- **nota:** prioridade baixa — mede parcialmente comportamento de registro.

**`N4-NAT-TRE-001`** · ambos · `lib:pendente` · *Seu perfil alimentar nos dias de treino*
- `Nos dias de treino, {pct_a}% das suas calorias vieram de alimentos in natura; nos dias sem, {pct_b}%.`
- → *"Nos dias de treino, 64% das suas calorias vieram de alimentos in natura; nos dias sem, 51%."*
- ctx: `Classificação NOVA, cobertura de {cob}%. {a} e {b} dias.` · dados: sessões + refeições + NOVA · gate: G4, ≥8 por grupo, cobertura ≥70%

## 9.5 Movimento e treino (2)

**`N4-PAS-TRE-001`** ⭐⭐ · ambos · `lib:v1` · *Dias de treino mexem no resto do seu dia*
- `Nos dias de treino você também se movimentou mais fora dele: {delta} passos a mais.`
- → *"Nos dias de treino você também se movimentou mais fora dele: 2.100 passos a mais."*
- ctx: `Passos da própria sessão descontados. {a} e {b} dias.` · dados: sessões com passos + passos do dia · gate: G4, ≥8 por grupo, **passos da sessão descontados**

**`N4-AND-TRE-001`** · ambos · `lib:pendente` · *Seus andares nos dias de treino*
- `Nos dias de treino você subiu {and_a} andares; nos dias sem, {and_b}.`
- → *"Nos dias de treino você subiu 14 andares; nos dias sem, 8."*
- ctx: `{a} e {b} dias.` · dados: sessões + andares · gate: G4, ≥8 por grupo

## 9.6 Regularidades cruzadas (2)

**`N4-REG-REG-001`** ⭐⭐ · ambos · `lib:v1` · *Suas duas regularidades andam juntas* `COND: hora de dormir`
- `Nas semanas em que seus horários de refeição foram mais regulares, seu horário de dormir variou {var_a}; nas outras semanas, {var_b}.`
- → *"Nas semanas em que seus horários de refeição foram mais regulares, seu horário de dormir variou 24 minutos; nas outras semanas, 51."*
- ctx: `{a} e {b} semanas em cada grupo; critério de regularidade fixado antes da análise.` · dados: refeições com hora + horário de dormir · gate: G4, ≥4 semanas por grupo
- **nota:** duas regularidades comparadas entre si. Veio do inventário de pares do v1.2 e é dos melhores cruzamentos do catálogo.

**`N4-REG-PAS-001`** · ambos · `lib:pendente` · *Sua regularidade de sono e seu movimento* `COND: hora de dormir`
- `Nas semanas de horários de sono mais regulares, você andou {passos_a} por dia; nas outras, {passos_b}.`
- → *"Nas semanas de horários de sono mais regulares, você andou 7.600 passos por dia; nas outras, 6.200."*
- ctx: `{a} e {b} semanas.` · dados: horário de dormir + passos · gate: G4, ≥4 semanas por grupo

## 9.7 Energia, peso e composição (5)

**`N4-ENE-GAS-001`** ⭐ · ambos · `lib:v1` · *Seu registro e o gasto medido por faixa de atividade*
- `Nos seus dias de mais movimento, você registrou {kcal_a} kcal contra um gasto medido de {gasto_a}. Nos dias de menos movimento, {kcal_b} contra {gasto_b}.`
- → *"Nos seus dias de mais movimento, você registrou 2.420 kcal contra um gasto medido de 2.980. Nos dias de menos movimento, 2.160 contra 2.440."*
- ctx: `Faixas de movimento fixadas antes da análise. {a} e {b} dias.` · dados: refeições + calorias totais + passos · gate: G4, ≥8 por grupo

**`N4-PES-ENE-001`** · ambos · `lib:pendente` · *Semanas de saldo negativo e seu peso*
- `Nas semanas em que você registrou menos calorias do que gastou, seu peso na pesagem seguinte foi {peso_a}; nas outras semanas, {peso_b}.`
- → *"Nas semanas em que você registrou menos calorias do que gastou, seu peso na pesagem seguinte foi 0,4 kg menor; nas outras semanas, 0,1 kg maior."*
- ctx: `{a} e {b} semanas com pesagem. Nenhuma relação de causa é afirmada.` · dados: refeições + calorias totais + peso · gate: G4, ≥6 semanas por grupo
- **nota:** a versão **liberada hoje** desta ideia é o `N2-FOS-002`, que justapõe os dois fatos sem agrupar. Construa o N2 e deixe este na biblioteca pendente.

**`N4-COR-PRO-001`** · ambos · `lib:pendente` · *Sua massa magra em períodos de mais proteína*
- `Nos períodos em que você registrou mais proteína, sua massa magra foi {magra_a}; nos outros, {magra_b}.`
- → *"Nos períodos em que você registrou mais proteína, sua massa magra foi 59,2 kg; nos outros, 58,4 kg."*
- ctx: `Medições pela mesma balança; bioimpedância tem margem de erro.` · dados: refeições com macros + massa magra · gate: G4, ≥4 medições por grupo, mesma fonte

**`N4-COR-TRE-001`** · ambos · `lib:pendente` · *Sua massa magra em períodos de mais volume de treino*
- `Nos períodos de mais volume de treino, sua massa magra foi {magra_a}; nos outros, {magra_b}.`
- → *"Nos períodos de mais volume de treino, sua massa magra foi 59,0 kg; nos outros, 58,2 kg."*
- ctx: `Medições pela mesma balança.` · dados: sessões com duração + massa magra · gate: G4, ≥4 medições por grupo

**`N4-EA-TRE-001`** · prof · `lib:v1` · *Sua disponibilidade energética em dias de treino e descanso*
- `Nos dias de treino, sua disponibilidade energética foi {ea_a} kcal por quilo de massa magra; nos dias de descanso, {ea_b}.`
- → *"Nos dias de treino, sua disponibilidade energética foi 24 kcal por quilo de massa magra; nos dias de descanso, 34."*
- ctx: `Depende da completude do registro alimentar. {a} e {b} dias.` · dados: refeições + calorias de sessão + massa magra · gate: G4, ≥8 por grupo
- **nota:** **somente Painel Web.** Disponibilidade energética baixa é diagnóstico clínico.

## 9.8 Intervalos cruzados (2)

**`N4-INT-SON-001`** · ambos · `lib:pendente` · *Seu jejum noturno e sua noite*
- `Nas noites de jejum mais longo, você dormiu {sono_a}; nas de jejum mais curto, {sono_b}.`
- → *"Nas noites de jejum mais longo, você dormiu 7h15; nas de jejum mais curto, 6h45."*
- ctx: `Faixas de jejum fixadas antes da análise. Mede o intervalo entre registros.` · dados: refeições com hora + sono · gate: G4, ≥8 por grupo

**`N4-INT-PAS-001`** · ambos · `lib:pendente` · *Quando você come e quanto você anda* `COND: hora de acordar`
- `Nos dias em que você comeu mais cedo depois de acordar, andou {passos_a}; nos outros, {passos_b}.`
- → *"Nos dias em que você comeu mais cedo depois de acordar, andou 7.400 passos; nos outros, 6.100."*
- ctx: `Faixas de intervalo fixadas antes da análise.` · dados: hora de acordar + refeições com hora + passos · gate: G4, ≥8 por grupo

## 9.9 Perfil alimentar cruzado (3)

**`N4-NAT-CAL-001`** ⭐ · ambos · `lib:v1` · *Seu perfil alimentar e o quanto você come*
- `Nos dias em que mais da metade das calorias veio de alimentos in natura, você registrou {kcal_a} kcal; nos outros dias, {kcal_b}.`
- → *"Nos dias em que mais da metade das calorias veio de alimentos in natura, você registrou 2.050 kcal; nos outros dias, 2.420."*
- ctx: `Classificação NOVA, cobertura de {cob}%. {a} e {b} dias.` · dados: refeições + NOVA · gate: G4, ≥8 por grupo, cobertura ≥70%

**`N4-DIV-CAL-001`** · ambos · `lib:pendente` · *Sua variedade e o quanto você come*
- `Nos dias de mais variedade de grupos alimentares, você registrou {kcal_a} kcal; nos de menos, {kcal_b}.`
- → *"Nos dias de mais variedade de grupos alimentares, você registrou 2.280 kcal; nos de menos, 2.040."*
- ctx: `Dez grupos da FAO, cobertura de {cob}%.` · dados: refeições + grupo FAO · gate: G4, ≥8 por grupo

**`N4-AGU-PAS-001`** · ambos · `lib:pendente` · *Sua água registrada e seu movimento*
- `Nos seus dias de mais passos, você registrou {ml_a} ml de água; nos de menos, {ml_b}.`
- → *"Nos seus dias de mais passos, você registrou 2.400 ml de água; nos de menos, 1.800."*
- ctx: `Soma do que foi anotado.` · dados: passos + água · gate: G4, ≥8 por grupo
- **nota:** prioridade baixa — mede parcialmente comportamento de registro.

## 9.10 Travados pelo R25 — frequência cardíaca pareada (6)

> **Não** travados pela regra 28: pelas três perguntas da regra, passam. Travados pela **pendência regulatória de FC** e pela decisão deliberada de **não** incluir pareamento de FC na primeira versão da biblioteca. FC pareada com sono é o material mais perto da fronteira clínica em todo o catálogo.

**`N4-FCR-SON-001`** · `R25` · *Sua frequência de repouso e suas noites*
- `Sua frequência de repouso foi {fc_a} bpm depois das noites mais longas e {fc_b} bpm depois das mais curtas.`
- dados: sono + FC repouso · gate: G4, mesma fonte, ≥10 por grupo

**`N4-FCR-TRE-001`** · `R25` · *Sua frequência de repouso em semanas de mais treino*
- `Nas semanas com mais sessões registradas, sua frequência de repouso foi {fc_a} bpm; nas outras, {fc_b}.`
- dados: sessões + FC repouso · gate: G4, ≥4 semanas por grupo

**`N4-FCM-SON-001`** · `R25` · *Seu esforço nos treinos depois de dormir pouco*
- `Nos treinos depois de noites curtas, sua frequência média foi {delta} bpm mais alta na mesma faixa de velocidade.`
- dados: sono + sessões com FC média e velocidade · gate: G4, mesma modalidade, faixa de velocidade comparável, ≥6 por grupo
- **nota:** tecnicamente o mais sofisticado do catálogo e o mais difícil de o usuário descobrir sozinho. Também o mais perto da fronteira clínica — o custo-benefício regulatório é ruim. Deixar para o fim.

**`N4-FCR-PAS-001`** · `R25` · *Sua frequência de repouso depois dos dias de mais movimento*
- `Depois dos seus dias de mais passos, sua frequência de repouso foi {fc_a} bpm; depois dos de menos, {fc_b}.`
- dados: passos + FC repouso · gate: G4, ≥10 por grupo

**`N4-FCR-REG-001`** · `R25` · *Sua frequência de repouso em semanas de sono mais regular*
- `Nas semanas de horários de sono mais regulares, sua frequência de repouso foi {fc_a} bpm; nas outras, {fc_b}.`
- dados: horário de dormir + FC repouso · gate: G4, ≥4 semanas por grupo

**`N4-FCR-PES-001`** · `R25` · *Sua frequência de repouso por faixa de peso*
- `Nos períodos de peso mais alto, sua frequência de repouso foi {fc_a} bpm; nos de peso mais baixo, {fc_b}.`
- dados: peso + FC repouso · gate: G4, ≥10 medições por grupo
- **nota:** peso como estrato é sensível. **Não incluir na biblioteca sem revisão regulatória.**

---

# 10. NÍVEL 5 — LONGITUDINAL DESCRITIVO (49)

> **Renomeado.** Era "Longitudinal personalizado".
> **Restrição de calendário, não de código:** N5 exige **duas janelas comparáveis**. Com janela de 30 dias, o primeiro N5 só existe por volta do **terceiro mês de uso**. O UAU, que carrega 30 dias, **não publica nenhum N5.**
> **Proibições próprias do N5:** nunca publicar tendência como previsão; nunca afirmar que um padrão "desapareceu" por falta de observação — preferir *"não se repetiu com a mesma frequência"*; nunca chamar mudança de melhora ou piora.
> **Formato comum:** `ctx` sempre declara as duas janelas, a cobertura de cada uma e que a fonte se manteve.

## 10.1 Sono (10)

**`N5-SON-001`** ⭐ · ambos · *Seu horário de dormir ficou mais previsível* `COND: hora de dormir`
- `Seu horário de dormir ficou mais previsível: a variação caiu de {antes} para {depois} minutos.`
- → *"Seu horário de dormir ficou mais previsível: a variação caiu de 68 para 31 minutos."*
- ctx: `Duas janelas de {n} noites, mesma fonte.` · gate: G5, ≥20 noites por janela, mudança ≥20 min

**`N5-SON-002`** · ambos · *Sua pior noite da semana mudou*
- `Sua noite mais curta da semana era {dia_antes}; agora é {dia_agora}.`
- → *"Sua noite mais curta da semana era domingo; agora é quarta."*
- ctx: `Duas janelas com cobertura parecida; ao menos {n} ocorrências de cada dia.` · gate: G5, **mudança replicada, não ranking por ruído**

**`N5-SON-003`** · ambos · *Um padrão seu não se repetiu* `COND: hora de dormir`
- `Sua faixa habitual de horário de dormir do mês passado não se repetiu com a mesma frequência neste.`
- → *"Sua faixa habitual de horário de dormir do mês passado não se repetiu com a mesma frequência neste."*
- ctx: `Cobertura e método iguais nas duas janelas. O padrão pode voltar.` · gate: G5, **proibido afirmar que o padrão "desapareceu"**

**`N5-SON-004`** ⭐ · ambos · *Seu deslocamento de fim de semana mudou* `COND: hora de dormir/acordar`
- `A diferença entre o meio da sua noite nos dias úteis e no fim de semana passou de {antes} para {depois}.`
- → *"A diferença entre o meio da sua noite nos dias úteis e no fim de semana passou de 1h40 para 55 minutos."*
- ctx: `Duas janelas com ambos os grupos de dias.` · gate: G5, ≥4 fins de semana por janela

**`N5-SON-005`** · ambos · *Sua eficiência de sono mudou*
- `Sua eficiência de sono passou de {antes}% para {depois}%.`
- → *"Sua eficiência de sono passou de 86% para 91%."*
- ctx: `Duas janelas de {n} noites, mesma fonte. Estimado pelo dispositivo.` · gate: G5, ≥18 noites por janela

**`N5-SON-006`** · ambos · *Sua duração de sono mudou*
- `Você dormiu {antes} por noite na janela anterior e {depois} na atual.`
- → *"Você dormiu 6h50 por noite na janela anterior e 7h20 na atual."*
- ctx: `Duas janelas de {n} noites, cobertura parecida.` · gate: G5, diferença ≥20 min

**`N5-SON-007`** · ambos · *Sua faixa habitual de sono se deslocou*
- `Sua faixa habitual de sono era de {min_a} a {max_a}; agora é de {min_b} a {max_b}.`
- → *"Sua faixa habitual de sono era de 6h10 a 7h20; agora é de 6h40 a 7h50."*
- ctx: `Faixa cobrindo {pct}% das noites em cada janela.` · gate: G5, ≥18 noites por janela

**`N5-SON-008`** · ambos · *Seu sono profundo mudou de proporção*
- `Seu sono profundo representava {antes}% da noite e passou a representar {depois}%.`
- → *"Seu sono profundo representava 15% da noite e passou a representar 19%."*
- ctx: `Estágios estimados pelo dispositivo; mesma fonte nas duas janelas.` · gate: G5, ≥18 noites por janela, mesma fonte

**`N5-SON-009`** · ambos · *Seus despertares mudaram*
- `Seu tempo acordado por noite passou de {antes} para {depois}.`
- → *"Seu tempo acordado por noite passou de 1h05 para 42 minutos."*
- ctx: `Estimado pelo dispositivo; mesma fonte nas duas janelas.` · gate: G5, ≥18 noites por janela, mudança ≥15 min

**`N5-SON-010`** · ambos · *Seu horário habitual de dormir se deslocou* `COND: hora de dormir`
- `Você ia para a cama habitualmente entre {min_a} e {max_a}; agora, entre {min_b} e {max_b}.`
- → *"Você ia para a cama habitualmente entre 23h10 e 00h05; agora, entre 22h35 e 23h20."*
- ctx: `Faixa cobrindo {pct}% das noites em cada janela.` · gate: G5, ≥18 noites por janela

## 10.2 Movimento (8)

**`N5-PAS-001`** ⭐ · ambos · *Seu ritmo semanal mudou*
- `Sua diferença de passos entre semana e fim de semana {direcao}: era de {antes} passos, agora é de {depois}.`
- → *"Sua diferença de passos entre semana e fim de semana diminuiu: era de 4.100 passos, agora é de 1.800."*
- ctx: `Duas janelas de ≥24 dias, cobertura parecida, mesma fonte.` · gate: G5, mudança ≥30%

**`N5-PAS-002`** ⭐ · ambos · *Sua atividade ficou mais distribuída*
- `Seus {n} dias mais ativos concentravam {antes}% dos seus passos; agora concentram {depois}%.`
- → *"Seus 6 dias mais ativos concentravam 54% dos seus passos; agora concentram 38%."*
- ctx: `Mesmo número de dias nas duas janelas.` · gate: G5, `n` fixo, mudança ≥10 pontos

**`N5-PAS-003`** · ambos · *Seu dia mais ativo da semana mudou*
- `Seu dia de mais passos era {dia_antes}; agora é {dia_agora}.`
- → *"Seu dia de mais passos era quarta; agora é sábado."*
- ctx: `Ao menos {n} ocorrências de cada dia nas duas janelas.` · gate: G5, mudança replicada

**`N5-PAS-004`** · ambos · *Sua faixa habitual de passos se deslocou*
- `Sua faixa habitual era de {min_a} a {max_a} passos; agora é de {min_b} a {max_b}.`
- → *"Sua faixa habitual era de 4.900 a 7.600 passos; agora é de 5.800 a 8.900."*
- ctx: `Faixa cobrindo {pct}% dos dias em cada janela.` · gate: G5, ≥20 dias por janela

**`N5-PAS-005`** · ambos · *A variação entre seus dias mudou*
- `A diferença entre seu dia mais ativo e o mais parado passou de {antes} para {depois} vezes.`
- → *"A diferença entre seu dia mais ativo e o mais parado passou de 5 para 3 vezes."*
- ctx: `Duas janelas de ≥20 dias.` · gate: G5

**`N5-NEA-001`** ⭐ · ambos · *Seu movimento fora dos treinos mudou*
- `Fora dos treinos, você andava {antes} passos por dia; agora anda {depois}.`
- → *"Fora dos treinos, você andava 3.600 passos por dia; agora anda 4.400."*
- ctx: `Passos da sessão descontados nas duas janelas.` · gate: G5, ≥20 dias por janela, mudança ≥15%

**`N5-CAD-001`** · ambos · *Seu ritmo de caminhada mudou* `COND: passos intradiários`
- `Nos seus 30 minutos mais ativos, sua cadência passou de {antes} para {depois} passos por minuto.`
- → *"Nos seus 30 minutos mais ativos, sua cadência passou de 88 para 96 passos por minuto."*
- ctx: `Duas janelas com dado minuto a minuto.` · gate: G5, ≥15 dias por janela

**`N5-AND-001`** · ambos · *Seus andares mudaram*
- `Você subia {antes} andares por mês; agora sobe {depois}.`
- → *"Você subia 170 andares por mês; agora sobe 312."*
- ctx: `Duas janelas com cobertura parecida.` · gate: G5, mudança ≥25%

## 10.3 Treino (8)

**`N5-TRE-001`** ⭐ · ambos · *Sua mistura de treinos mudou*
- `{modalidade} era {antes}% do seu tempo de treino; agora é {depois}%.`
- → *"Corrida era 70% do seu tempo de treino; agora é 45%."*
- ctx: `Mesma classificação de modalidade nas duas janelas.` · gate: G5, ≥8 sessões por janela, mudança ≥15 pontos

**`N5-TRE-002`** ⭐ · ambos · *Seus treinos mudaram de formato*
- `Seus treinos passaram de {freq_a} por semana de {dur_a} minutos para {freq_b} de {dur_b}.`
- → *"Seus treinos passaram de 3 por semana de 55 minutos para 5 de 32."*
- ctx: `Duas janelas de {n} semanas.` · gate: G5, ≥8 sessões por janela

**`N5-TRI-001`** · ambos · *Sua carga de treino mudou*
- `Sua carga semanal passou de {antes} para {depois}.`
- → *"Sua carga semanal passou de 310 para 420."*
- ctx: `Carga calculada a partir da duração e da frequência cardíaca; mesma fonte de FC nas duas janelas.` · gate: G5, ≥3 semanas por janela

**`N5-MON-001`** · ambos · *Suas semanas ficaram mais ou menos concentradas*
- `Seu volume semanal se concentrava em {antes} dias; agora se concentra em {depois}.`
- → *"Seu volume semanal se concentrava em 2 dias; agora se concentra em 4."*
- ctx: `Duas janelas de ≥3 semanas com sessão.` · gate: G5

**`N5-EFF-001`** ⭐ · ambos · *Sua relação entre ritmo e esforço mudou*
- `Na mesma faixa de ritmo, sua frequência média passou de {antes} para {depois} bpm.`
- → *"Na mesma faixa de ritmo, sua frequência média passou de 152 para 144 bpm."*
- ctx: `Mesma modalidade e mesma faixa de velocidade nas duas janelas; mesma fonte de FC. Relação entre velocidade e frequência é métrica de prática de treinamento, não índice revisado por pares.` · gate: G5, ≥6 sessões por janela, faixa de velocidade comparável
- **nota:** para quem corre, é a frase que prova que o produto funciona — condicionamento virando visível. **Confirmar que não cai no R25** antes de publicar: é descrição de FC, não detecção de anomalia.

**`N5-VOL-001`** · ambos · *Seu volume de treino mudou*
- `Você treinava {antes} horas por semana; agora treina {depois}.`
- → *"Você treinava 2h10 por semana; agora treina 3h30."*
- ctx: `Duas janelas de ≥3 semanas.` · gate: G5, mudança ≥20%

**`N5-TRE-003`** · ambos · *Seu padrão de blocos de treino mudou*
- `Seus treinos vinham em blocos de {antes} dias seguidos; agora vêm em blocos de {depois}.`
- → *"Seus treinos vinham em blocos de 3 dias seguidos; agora vêm em blocos de 2."*
- ctx: `Padrão identificado em ≥3 ciclos de cada janela.` · gate: G5, ≥10 sessões por janela

**`N5-TRE-004`** · ambos · *Seu intervalo entre treinos mudou*
- `O intervalo entre seus treinos passou de {antes} para {depois} dias.`
- → *"O intervalo entre seus treinos passou de 3 para 2 dias."*
- ctx: `Duas janelas com ≥8 sessões.` · gate: G5

## 10.4 Composição corporal e cardíaco (7)

**`N5-COR-001`** ⭐⭐ · ambos · *Seu peso caiu e sua massa magra se manteve*
- `Seu peso caiu {delta} kg em {meses} meses, e sua massa magra {direcao}.`
- → *"Seu peso caiu 2,4 kg em três meses, e sua massa magra se manteve."*
- ctx: `Medições pela mesma balança, com margem de erro de bioimpedância.` · gate: G5, ≥3 medições mesma fonte, intervalo ≥60 dias
- **nota:** o insight de composição corporal mais valioso possível sem inferência. É a história que o usuário quer ouvir, contada só com fatos observados.

**`N5-FFM-001`** · ambos · *Seu índice de massa magra mudou*
- `Seu índice de massa magra passou de {antes} para {depois}.`
- → *"Seu índice de massa magra passou de 18,1 para 18,7."*
- ctx: `Mesma balança nas medições; margem de erro de bioimpedância.` · gate: G5, ≥3 medições, intervalo ≥60 dias

**`N5-COR-002`** · ambos · *Seu percentual de gordura mudou ao longo dos meses*
- `Seu percentual de gordura foi de {m1}%, {m2}% e {m3}% nos últimos três meses.`
- → *"Seu percentual de gordura foi de 25,4%, 24,1% e 22,8% nos últimos três meses."*
- ctx: `Mesma balança; três pontos não definem uma tendência.` · gate: G5, 3 janelas, **proibida projeção**

**`N5-WHT-001`** · ambos · *Sua relação cintura-estatura mudou ao longo dos meses* `COND: cintura`
- `Sua relação cintura-estatura foi de {m1}, {m2} e {m3} nas três últimas medições.`
- → *"Sua relação cintura-estatura foi de 0,56, 0,54 e 0,52 nas três últimas medições."*
- ctx: `Medições de {datas}. Três pontos não definem uma tendência.` · gate: G5, 3 medições, intervalo ≥30 dias cada

**`N5-OSC-001`** · ambos · *A oscilação do seu peso mudou*
- `Seu peso oscilava {antes} kg entre pesagens; agora oscila {depois}.`
- → *"Seu peso oscilava 1,8 kg entre pesagens; agora oscila 0,9."*
- ctx: `Duas janelas com ≥8 pesagens.` · gate: G5

**`N5-FCR-001`** · ambos · *Sua frequência de repouso ao longo dos meses*
- `Sua frequência de repouso nos últimos três meses foi {m1}, {m2} e {m3} bpm.`
- → *"Sua frequência de repouso nos últimos três meses foi 63, 60 e 58 bpm."*
- ctx: `Três medições mensais, mesma fonte. Três pontos não definem uma tendência.` · gate: G5, 3 janelas, mesma fonte, **proibida projeção**, **nenhuma leitura clínica**
- **nota:** destravado pelo R25 (decisão 70) — é espelho e descrição, não detecção de anomalia.

**`N5-PER-001`** · prof · *Sua velocidade de perda mudou*
- `Seu peso caía {antes}% por semana; agora cai {depois}%. A faixa de referência definida para você é {faixa}.`
- → *"Seu peso caía 1,4% por semana; agora cai 0,7%. A faixa de referência definida para você é 0,5% a 1,0%."*
- ctx: `Faixa definida pelo profissional.` · gate: G5, ≥6 pesagens por janela
- **nota:** **somente Painel Web** (carrega referência).

## 10.5 Nutrição (10)

**`N5-ALI-001`** ⭐ · ambos · *Sua janela de alimentação encurtou*
- `O intervalo entre sua primeira e sua última refeição registrada passou de {antes} para {depois}.`
- → *"O intervalo entre sua primeira e sua última refeição registrada passou de 13 horas para 11 horas e meia."*
- ctx: `Mede o intervalo entre registros. Cobertura parecida nas duas janelas.` · gate: G5, ≥15 dias por janela

**`N5-INT-001`** ⭐ · ambos · *Seu jejum noturno mudou*
- `O intervalo entre sua última refeição e a primeira do dia seguinte passou de {antes} para {depois}.`
- → *"O intervalo entre sua última refeição e a primeira do dia seguinte passou de 11h20 para 13h10."*
- ctx: `Mede o intervalo entre registros. Duas janelas de ≥15 pares de dias.` · gate: G5

**`N5-PRO-001`** ⭐ · ambos · *Sua proteína ficou mais distribuída no dia*
- `O {refeicao} concentrava {antes}% da sua proteína; agora concentra {depois}%.`
- → *"O jantar concentrava 58% da sua proteína; agora concentra 41%."*
- ctx: `Dias com as refeições principais registradas nas duas janelas.` · gate: G5, ≥15 dias por janela, mudança ≥10 pontos

**`N5-NAT-001`** ⭐ · ambos · *Sua proporção de alimento in natura mudou*
- `A parcela das suas calorias vinda de alimentos in natura passou de {antes}% para {depois}%.`
- → *"A parcela das suas calorias vinda de alimentos in natura passou de 48% para 61%."*
- ctx: `Classificação NOVA; cobertura de {cob_a}% e {cob_b}% nas duas janelas.` · gate: G5, ≥15 dias por janela, cobertura ≥70% em ambas

**`N5-DIV-001`** ⭐ · ambos · *Sua variedade alimentar mudou*
- `Você registrava {antes} grupos alimentares por dia; agora registra {depois}.`
- → *"Você registrava 4,1 grupos alimentares por dia; agora registra 5,6."*
- ctx: `Dez grupos da FAO; cobertura de {cob_a}% e {cob_b}%.` · gate: G5, ≥15 dias por janela

**`N5-REP-001`** · ambos · *Seu repertório alimentar mudou de tamanho*
- `Você registrava {antes} alimentos diferentes por mês; agora registra {depois}.`
- → *"Você registrava 24 alimentos diferentes por mês; agora registra 38."*
- ctx: `Conta alimentos distintos do catálogo.` · gate: G5, ≥15 dias por janela

**`N5-ACU-001`** · ambos · *Seus açúcares mudaram de proporção*
- `Os açúcares respondiam por {antes}% das suas calorias registradas; agora respondem por {depois}%.`
- → *"Os açúcares respondiam por 22% das suas calorias registradas; agora respondem por 17%."*
- ctx: `Açúcares totais da tabela de alimentos.` · gate: G5, ≥15 dias por janela

**`N5-ENE-001`** · ambos · *Onde suas calorias se concentram mudou de horário*
- `A parcela das suas calorias registradas depois das {hora} passou de {antes}% para {depois}%.`
- → *"A parcela das suas calorias registradas depois das 19h passou de 52% para 38%."*
- ctx: `Faixa de horário fixa nas duas janelas.` · gate: G5, ≥15 dias por janela

**`N5-ALI-002`** · ambos · *Sua primeira refeição mudou de horário*
- `O horário da sua primeira refeição registrada passou de {antes} para {depois}.`
- → *"O horário da sua primeira refeição registrada passou de 9h20 para 7h45."*
- ctx: `Mede o horário do registro.` · gate: G5, ≥15 dias por janela, mudança ≥45 min

**`N5-DEN-001`** · ambos · *A densidade calórica do que você registra mudou*
- `A densidade calórica média do que você registra passou de {antes} para {depois} kcal por 100 g.`
- → *"A densidade calórica média do que você registra passou de 168 para 132 kcal por 100 g."*
- ctx: `Considera refeições registradas com quantidade.` · gate: G5, ≥15 dias por janela

## 10.6 Fosso (3)

**`N5-FOS-001`** ⭐⭐ · ambos · *Seu gasto declarado e o medido se aproximaram*
- `A diferença entre o que você registra e o que o relógio mede {direcao}: era de {antes} kcal por dia, agora é de {depois}.`
- → *"A diferença entre o que você registra e o que o relógio mede diminuiu: era de 520 kcal por dia, agora é de 140."*
- ctx: `Pode refletir registro mais completo, mudança real de consumo, ou as duas coisas.` · gate: G5, ≥20 dias por janela com ambos, **ressalva obrigatória**
- **nota:** continuação natural do `N2-FOS-001`. Mostra ao usuário que ele está aprendendo a usar o produto — e isso é retenção.

**`N5-FOS-002`** · ambos · *Seu saldo acumulado e seu peso ao longo dos meses*
- `Nos últimos {meses} meses, seu saldo registrado foi de {saldo} kcal e seu peso {direcao} {delta} kg.`
- → *"Nos últimos três meses, seu saldo registrado foi de −12.400 kcal e seu peso caiu 1,9 kg."*
- ctx: `Dois fatos do mesmo período, lado a lado. O consumo considera apenas o que você registrou.` · gate: G5, ≥20 dias por mês com ambos, **nenhuma relação de causa afirmada, nenhuma projeção**

**`N5-COB-001`** · ambos · *Sua cobertura de dados mudou*
- `Seus dados cobriam {antes}% dos dias; agora cobrem {depois}%.`
- → *"Seus dados cobriam 62% dos dias; agora cobrem 88%."*
- ctx: `Dias sem dado não entram como zero. Comparações que atravessam troca de dispositivo ficam de fora.` · gate: G5
- **nota:** no limite da R14, mas sustenta a interpretação de todas as outras comparações longitudinais. Exibir como contexto, não como cartão.

## 10.7 Coocorrência de mudanças (3)

> Formato que entrega a justaposição **e** o limite epistêmico na mesma frase. É a letra da regra 28.

**`N5-COO-001`** ⭐ · ambos · *Duas coisas mudaram no mesmo período* `COND: hora de dormir`
- `Entre {janela_a} e {janela_b}, seus passos {dir_a} e seu horário de dormir {dir_b}. Os dois mudaram no mesmo período; não é possível dizer se têm relação.`
- → *"Entre setembro e outubro, seus passos aumentaram e seu horário de dormir ficou mais regular. Os dois mudaram no mesmo período; não é possível dizer se têm relação."*
- ctx: `Cada mudança foi avaliada separadamente, com cobertura e dispersão próprias.` · gate: G5, **as duas mudanças robustas por conta própria**, nenhuma atribuição

**`N5-COO-002`** · ambos · *Seu peso e sua atividade mudaram no mesmo período*
- `Entre {janela_a} e {janela_b}, seu peso {dir_a} e seu volume de treino {dir_b}. Os dois mudaram no mesmo período; não é possível dizer se têm relação.`
- → *"Entre agosto e outubro, seu peso caiu 2,1 kg e seu volume de treino aumentou 40%. Os dois mudaram no mesmo período; não é possível dizer se têm relação."*
- ctx: `Cada mudança avaliada separadamente.` · gate: G5, idem

**`N5-COO-003`** · ambos · *Sua alimentação e seu sono mudaram no mesmo período*
- `Entre {janela_a} e {janela_b}, sua janela de alimentação {dir_a} e sua duração de sono {dir_b}. Os dois mudaram no mesmo período; não é possível dizer se têm relação.`
- → *"Entre setembro e outubro, sua janela de alimentação encurtou 1h30 e sua duração de sono aumentou 25 minutos. Os dois mudaram no mesmo período; não é possível dizer se têm relação."*
- ctx: `Cada mudança avaliada separadamente.` · gate: G5, idem

---

# 11. SUPORTE — ESTADO E QUALIDADE DO DADO (19)

> Nunca disputam ranking. Nunca aparecem como cartão de descoberta. São estado de tela, aviso operacional ou linha de qualidade.
> **Esta família é a regra 29 na camada visual e a diferença entre um produto que diz onde não sabe e um que finge saber.** É também, por si, um diferencial: o líder global acumula dupla contagem no saldo há uma década sem avisar ninguém.

**`SUP-001`** · *Refeição não sincronizada*
`Você tem {n} refeições registradas que ainda não subiram. Elas sobem sozinhas quando você tiver rede.`
→ indicador **passivo** na tela inicial · não bloqueia nada

**`SUP-002`** · *Medida pendente de tratamento*
`Uma refeição ficou com a medida em aberto: "{descricao}". Toque para resolver.`
→ alerta **acionável** na tela inicial (regra 23 — nunca arbitrar em silêncio) · linguagem operacional, **nunca "atenção"**

**`SUP-003`** · *Cobertura insuficiente no período*
`Seus dados cobriram {n} dos {total} dias. Algumas análises precisam de mais dias para aparecer.`
→ linha de contexto · **nunca cartão** (R13)

**`SUP-004`** · *Sua meta mudou, e o histórico foi preservado*
`Sua meta mudou em {data}. As análises anteriores continuam usando a meta que valia na época.`
→ aparece junto do insight de meta · é descoberta de **confiança**, não de comportamento

**`SUP-005`** · *A fonte do dado mudou*
`Seus dados de {metrica} passaram a vir de {fonte_nova} em {data}. Comparações que atravessam essa data ficam de fora.`
→ linha de transparência · **bloqueia** comparações que cruzem a data

**`SUP-006`** · *Seu padrão de registro de água* `rebaixado de N3 pela R14`
`{pct}% da sua água foi anotada antes do meio-dia.`
→ tela de qualidade do dado · **nunca cartão de descoberta** — é sobre quando você anota, não quando você bebe

**`SUP-007`** · *Sua rotina de pesagem* `rebaixado de N3 pela R14`
`Você se pesa quase sempre na {dia}: {pct}% das pesagens.`
→ tela de qualidade do dado

**`SUP-008`** · *Completude do seu registro alimentar* `rebaixado de N3 pela R14`
`Você registrou as três refeições principais em {n} dos {total} dias.`
→ tela de qualidade do dado · **nunca inferir consumo nos dias restantes**

**`SUP-009`** · *Uma medição ficou fora da sua faixa habitual*
`Uma medição de {metrica} em {data} ficou fora da sua faixa habitual. Vale conferir se a medição saiu certa.`
→ linha de qualidade · herdado do v1.2, onde dizia "verifique a qualidade da medição antes de interpretá-lo" — **instrução trocada por descrição**

**`SUP-010`** · *Dados que não passaram pela verificação de qualidade*
`Para {metrica}, os registros de {periodo} não passaram pelas verificações de qualidade. Isso não permite concluir que o comportamento não ocorreu.`
→ linha de transparência · a ressalva final é obrigatória

**`SUP-011`** · *Por que uma comparação não apareceu*
`A comparação de {metrica} entre os dois períodos precisa de mais dias para ser confiável.`
→ aparece **sob demanda**, ao lado de uma análise ausente · **nunca como cartão** (R13)

**`SUP-012`** · *Alimentos ainda não classificados*
`{pct}% das calorias do período vieram de alimentos que ainda não têm classificação. Eles não entram nos cálculos de perfil alimentar.`
→ obrigatório ao lado de qualquer número de NOVA ou de grupos FAO · **sem isso, a porcentagem mente para baixo**

**`SUP-013`** · *Estimativas no total*
`{n} itens deste total vieram de estimativa, não de medição.`
→ regra 29 na camada visual · todo total que inclua estimativa carrega a marca

**`SUP-014`** · *Última sincronização do relógio*
`Seus dados do relógio foram atualizados há {tempo}.`
→ indicador passivo

**`SUP-015`** · *Troca de dispositivo detectada*
`Você passou a usar outro dispositivo em {data}. Comparações entre antes e depois dessa data ficam de fora até a equivalência ser verificada.`
→ **bloqueia** comparação, não só avisa

**`SUP-016`** · *Sua anamnese está perto de vencer*
`Sua anamnese vence em {dias} dias. Depois disso, algumas análises deixam de ser atualizadas.`
→ linguagem operacional, **nunca de alerta de saúde**

**`SUP-017`** · *Dias com dado parcial*
`{n} dias do período tiveram dado parcial e entraram apenas nas análises que o suportam.`
→ linha de contexto

**`SUP-018`** · *De onde veio cada dado do dia*
`No dia {data}, {metrica} veio de {fonte} e {metrica_b} de {fonte_b}.`
→ tela de qualidade · é a hierarquia de fontes exposta ao usuário

**`SUP-019`** · *Nada novo hoje*
`Nenhuma descoberta nova hoje. Sua descoberta mais recente é de {data}.`
→ **estado da tela, nunca cartão.** O widget mostra a descoberta mais recente com a data dela e **nunca anuncia o silêncio como se fosse conteúdo** (R13)

---

# 12. OS 15 DO RELATÓRIO UAU

O UAU tem **6 telas lógicas** com até 3 descobertas cada, sobre a carga inicial de 30 dias. Precisa de material para o primeiro relatório e as duas primeiras semanas sem repetição.

| # | Template | Nível | Tela | Risco |
|---:|---|---|---|---|
| 1 | `N3-SON-401` Você dorme mais no mesmo horário do que acorda | N3 | Sono | **timestamp** |
| 2 | `N3-PAS-101` Metade dos seus passos vem de poucos dias | N3 | Movimento | — |
| 3 | `N2-FOS-001` Seu gasto declarado e o medido | N2 | Energia | estimativa declarada |
| 4 | `N3-PAS-201` Você anda quase o dobro durante a semana | N3 | Movimento | — |
| 5 | `N3-SON-202` Você acorda mais tarde no fim de semana | N3 | Sono | **timestamp** |
| 6 | `N3-REP-101` Cinco alimentos respondem por metade do que você come | N3 | Alimentação | catálogo de alimentos |
| 7 | `N3-PRO-101` Sua proteína se concentra numa refeição | N3 | Alimentação | — |
| 8 | `N3-SON-402` Suas noites variam entre 5h20 e 8h40 | N3 | Sono | — |
| 9 | `N3-INT-901` Seu jejum noturno real | N3 | Alimentação | — |
| 10 | `N3-SON-501` Sua faixa habitual de sono | N3 | Sono | — |
| 11 | `N3-PAS-301` Quarta é seu dia mais ativo | N3 | Rotina | separação do 2º lugar |
| 12 | `N3-SON-301` Suas noites de domingo são as mais curtas | N3 | Rotina | separação do 2º lugar |
| 13 | `N3-TRE-801` A composição dos seus treinos | N3 | Treino | — |
| 14 | `N3-PAS-401` Seu dia mais ativo teve 4 vezes mais passos | N3 | Movimento | — |
| 15 | `N1-PAS-001` Seus passos em quilômetros | N1 | Retrato | fallback |

**Treze N3, um N2 e um N1 de rodapé. Nenhum N5** — o UAU carrega 30 dias e N5 precisa de duas janelas. **Nenhum N4** — grupo mínimo não fecha em 30 dias de forma confiável.

**Dois dos três melhores dependem do timestamp de sono.** Sem o campo, o UAU perde `N3-SON-401` e `N3-SON-202` e cai de 13 para 11 N3 — ainda viável, mas sem a frase mais forte do produto.

---

# 13. BIBLIOTECA `perguntas_analiticas` — PRIMEIRA VERSÃO

> Exigida pela Regra 28 revista. **Cada entrada é uma pergunta, não um par de variáveis** — é o que torna o pré-registro defensável diante de um auditor.
> **Dois níveis**, para que a cláusula de revisor não seja decorativa:
> **`aprovado_fundador`** — rotina e comportamento, sem fisiologia. O fundador é competente para julgar se a pergunta é interessante e se a comparação é honesta.
> **`pendente_revisor`** — qualquer pergunta que cruze fisiologia. Fica **escrita e `ativo=false`**, esperando o parceiro.

| # | Pergunta | Nível | Templates |
|---:|---|---|---|
| 1 | Como meu sono se distribui entre dias com e sem treino registrado? | `pendente_revisor` | N4-SON-TRE-001/002/003/004 |
| 2 | Como meus passos se distribuem depois de noites mais curtas e mais longas? | `pendente_revisor` | N4-PAS-SON-001/002 |
| 3 | Como meu sono se distribui depois de dias de mais e menos movimento? | `pendente_revisor` | N4-SON-PAS-001 |
| 4 | Como meu sono se distribui quando minha última refeição é mais cedo ou mais tarde? | `pendente_revisor` | N4-SON-ALI-001/002, N4-DOR-ALI-001 |
| 5 | Como meu sono se distribui depois de dias de mais e menos açúcar registrado? | `pendente_revisor` | N4-SON-ACU-001 |
| 6 | Quanto eu registro de energia e macros em dias com e sem treino? | `aprovado_fundador` | N4-CAL-TRE-001, N4-PRO-TRE-001, N4-CAR-TRE-001 |
| 7 | Quanto eu me movimento fora do treino em dias com e sem treino? | `aprovado_fundador` | N4-PAS-TRE-001 |
| 8 | Quanto de água eu registro em dias com e sem treino? | `aprovado_fundador` | N4-AGU-TRE-001 |
| 9 | Como minha regularidade de refeição se relaciona com a regularidade do meu sono? | `pendente_revisor` | N4-REG-REG-001 |
| 10 | Quanto eu registro de energia contra o gasto medido, por faixa de movimento? | `aprovado_fundador` | N4-ENE-GAS-001 |
| 11 | Quanto eu registro de energia em dias de perfil alimentar mais e menos in natura? | `aprovado_fundador` | N4-NAT-CAL-001 |
| 12 | Como meu horário de dormir varia em semanas de mais e menos treino? | `pendente_revisor` | N4-SON-TRE-005 |
| 13 | Qual a minha disponibilidade energética em dias de treino e de descanso? | `pendente_revisor` · **prof** | N4-EA-TRE-001 |
| 14 | Como meu sono se distribui por faixa de intervalo entre comer e dormir? | `pendente_revisor` | N4-SON-ALI-002 |

**Campos da tabela:** `pergunta_id`, `versao`, `status`, `texto_da_pergunta`, `indicador_a`, `indicador_b`, `definicao_grupo_a`, `definicao_grupo_b`, `unidade_analise`, `janela`, `defasagem`, `n_minimo_a`, `n_minimo_b`, `cobertura_minima`, `medida_dispersao`, `limiar_pratico_minimo`, `fontes_permitidas`, `template_ids`, `revisor`, `aprovado_em`, `vigente_desde`, `vigente_ate`, `ativo`.

**Regra de operação:** o motor **nunca** cria cruzamento dinamicamente a partir do dado, e **nunca** escolhe qual publicar pela maior diferença. A seleção decorre de relevância pré-declarada, objetivo da anamnese, novidade e diversidade.

**Limiar de publicação:** não é estatístico — é **prático, declarado por indicador** em `limiares_praticos`. Sono 20 minutos · passos 1.000 · FC 3 bpm · peso 0,5 kg · energia 150 kcal · proteína 15 g · água 300 ml · duração de treino 10 minutos. Um limiar estatístico seria exatamente a inferência que a regra proíbe.

---

# 14. REGISTRO DE DESCARTE — O QUE SAIU DO v1.2 E POR QUÊ

Extração mecânica de `ORYNTY_CATALOGO_TEMPLATES_UAU_CONTINUOUS_RF_ET_005.md`: 2.166 entradas com corpo de texto, 254 esqueletos distintos, **20 esqueletos cobrindo 1.786 entradas (82,5%)**, 195 entradas com frase única.

## 14.1 A massa — 1.786 entradas, 20 frases

| Esqueleto | n | Veredito |
|---|---:|---|
| "a média de {} foi {}, considerando {} registros válidos" | 119 | reduz a 1 N1 |
| "encontramos {} registros válidos entre {} oportunidades de medição avaliáveis" | 119 | **SUPORTE**, não N1 — voz de engenharia |
| "as médias permaneceram próximas…; diferença observada de {}" | 119 | **FORA** — "nada mudou" vendido como descoberta |
| "os registros não permitem comparação confiável" | 119 | **SUPORTE** (`SUP-011`) |
| "o registro válido mais recente foi {} em {}" | 119 | reduz a 1 N1 |
| "{} variou entre {} e {}, entre os registros disponíveis" | 115 | **ENTRA** — é dispersão, e estava mal classificado como N2 |
| "houve registros em {} de {} datas avaliáveis; datas sem registros não indicam zero" | 115 | **SUPORTE** — a ressalva final virou regra 31 |
| "a média ficou {} acima/abaixo do período anterior ({} registros atuais e {} anteriores)" | 226 | **ENTRA reescrito** — o parêntese sai |
| menor / maior valor registrado | 218 | reduz a 2 N1 |
| "#% dos registros válidos ficaram em até {}" | 88 | **FORA** — percentil disfarçado, ilegível |
| "a variação foi de {} segundo {}" | 82 | **FORA** como está — desvio padrão na interface (R5) |
| "apresentaram uma mudança…; a magnitude observada foi {}" | 68 | **FORA** — magnitude de quê, padrão por qual método |
| "o padrão se manteve, dentro dos critérios de comparabilidade" | 68 | **FORA** — padrão mantido fica calado |
| "o padrão não foi confirmado; isso não demonstra que desapareceu" | 68 | **ENTRA** como `N5-SON-003` |
| "a mediana foi {}" | 55 | reduz a 1 N1 |
| "um registro ficou fora da faixa habitual; verifique a qualidade da medição" | 48 | **ENTRA** como `SUP-009`, com a instrução trocada por descrição |
| "no período {}, {} totalizou {} {}, nos/nas {}" (13 variantes de rodapé) | ~80 | **FORA** — total puro, concordância quebrada ("passos totalizou") |
| padrão novo / permaneceu / menor consistência / não confirmado | 32 | 2 entram, 2 saem |
| SUPORTE: ausência, qualidade, cobertura, troca de origem | 20 | **os 4 entram** |

## 14.2 As 195 únicas

| Família | n | Veredito |
|---|---:|---|
| `X-CRUZAMENTO` forma "média de X foi V1 e V2 nos grupos comparados de Y" | 6 | **ENTRA com reescrita total** — nunca dizia o que separa os grupos |
| `X-CRUZAMENTO` forma "associação exploratória; magnitude estimada {efeito} ({metodo})" | 6 | **MORRE** — tamanho de efeito com método nomeado, proibição (a). O "isso não demonstra causalidade" não salva |
| `X-CRUZAMENTO` forma "não sustentaram uma associação consistente" | 6 | **MORRE** — afirmar não-associação também é inferência, e é ausência como achado |
| `X-CRUZAMENTO` forma "a associação anteriormente observada mudou" | 6 | **MORRE** — inferência sobre inferência |
| `HV-C4` forma única "valores de X no grupo A **coincidiram com** Y de {media}" | 18 | **forma MORRE** ("coincidiram" é insinuação; grupos nunca definidos). **Os 18 pares entram como inventário** da biblioteca; 4 eram pares que não tínhamos |
| `EV-C-4` escritos individualmente | 25 | **14 entram** · 11 saem (4 por R25, 2 por exigirem "dia alimentar completo" — sinal inexistente, 1 por desfecho ser número de anotações, 2 por inferência explícita, 2 por medir registro) |
| `HV-C5` forma "{estado_mudanca}" | 17 | **forma MORRE** — `{estado_mudanca}` era o verbo da frase numa variável sem vocabulário. 13 pares entram como N5, 4 viram SUPORTE |
| `HV-C5` forma "relação exploratória entre **associação** X-Y mudou" | 4 | **MORREM** — inferência sobre inferência com a palavra "associação" dentro |
| `HV-C3` formas `{descricao_padrao}` e cobertura | 21 | formas morrem; pares entram como inventário |
| `HV-U3` e `EV-U` | 24 | **as melhores escritas do v1.2** e **convergem** com a curadoria independente. Entram com reescrita (percentual cru → "quase o dobro") |

## 14.3 As duas doenças, promovidas a regra no Mestre

**Regra 30 — variável semântica indefinida.** `{descricao_padrao}`, `{estado_mudanca}`, `{descricao_variacao_peso}`, `{efeito}`, `{metodo}` carregavam o **verbo ou o juízo** da frase sem vocabulário fechado. Mataram ~60 entradas únicas. *Nenhuma variável de template pode conter o verbo ou o juízo da frase. Variável carrega número, data, nome de métrica ou rótulo de grupo — nunca sentido.*

**Regra 31 — cobertura vendida como descoberta.** Mataram ~370 entradas. *Frase cujo sujeito é o registro, e não o comportamento, é SUPORTE por construção.*

---

# 15. ORDEM DE CONSTRUÇÃO

> **A ordem canônica vive na Parte 9.1 do Mestre v9.2.** Abaixo, só a leitura do ponto de vista do catálogo.

**Antes de qualquer template:** a migração das chaves Supabase (N44, **com prazo**) e o R25 desligado. Nenhum dos dois é de descoberta, e os dois vêm antes.

1. **N43 Etapa 1** — timestamp de sono **e** tipo de refeição, uma consulta. **Decide 29 templates.**
2. **Fundação, em quatro etapas** (Mestre, D.10.3): **N41a** tabelas → **N41b** gates como função pura → **N41d** renderizador. O **N41c** (seleção e dedup) é **opcional para o UAU** e pode ir depois. Como RPC no Postgres, não Edge Function (decisão 88).
3. **`N2-FOS-001` e `N2-FOS-002`** — o fosso. Maior valor comercial, nenhuma dependência nova.
4. **N42 — as 9 famílias + os 15 do UAU** (seção 12). Prova a cadeia e destrava 87 templates para semeadura.
5. **N1 e SUPORTE** — rápidos, e sem eles o relatório não tem rodapé nem fallback honesto.
6. **Os N3 de sono com timestamp**, se o campo existir.

**A partir daqui é Continuous, e só depois do beta começar:**

7. **N46** — gates G4/G5, biblioteca semeada, cadência, widget de descoberta recente.
8. **Lotes de família**, na ordem de retorno: dispersão (12), intervalos (10), distribuição interna (10), estrato semanal (10), concentração (9), faixa habitual (8), dia específico (8).
9. **N2 período contra período (24)** — a maior família, deixada para o fim **de propósito**: compara com a janela anterior, que não existe no primeiro mês de uso e portanto não aparece para um usuário novo de beta.
10. **N4 `aprovado_fundador`** (perguntas 6, 7, 8, 10, 11).
11. **N5** — só faz sentido por volta do segundo mês de uso real. Não bloqueia o beta.
12. **N4 `pendente_revisor`** — depois do revisor nomeado. **Não construir antes.**
13. **Os 4 descritivos de FC**, depois de desligada a detecção de anomalia. Os 6 pareados de FC ficam fora da primeira biblioteca por escolha.

---

*Fim do Catálogo de Descobertas v2.1. Documento subordinado ao DOCUMENTO MESTRE v9.2.1 — onde conflitar, o Mestre prevalece. Evolução por adendo/log (`/docs/log_dev`); próxima revisão sugerida ao fim do beta de amigos, com os dados de uso real das descobertas publicadas.*
