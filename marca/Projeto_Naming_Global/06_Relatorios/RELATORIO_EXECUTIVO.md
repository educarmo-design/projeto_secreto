# Relatório Executivo — Projeto de Naming Global

**Data:** 2026-07-31
**Produto:** Plataforma de saúde preventiva com IA (jornada nascimento → velhice; Android, iOS, web, painel profissional, APIs futuras)
**Metodologia completa:** ver `00_Config/config.md` e `checkpoints/checkpoint_log.md` (log completo com data/hora de cada etapa)

---

## 1. Qual foi a metodologia utilizada?

Pipeline em 6 etapas + Conselho Global de Branding, com checkpoint em arquivo após cada etapa (nunca reiniciando do zero em caso de falha):

1. **Geração** — 333 candidatos únicos criados manualmente por especialista, usando 9 métodos distintos (raízes gregas, latinas, proto-indo-europeias, nórdicas, célticas, invenção fonética moderna, blend de fonemas em português, combinação estatística de sílabas, metáfora inglesa), evitando ativamente as raízes e concorrentes proibidos pelo briefing.
2. **Filtros linguísticos** — remoção automática/manual de nomes com raiz proibida, conotação médica/esportiva excessiva, colisão conhecida com marca real, conotação negativa, dificuldade de pronúncia ou redundância sonora com outro candidato.
3. **Bucketização + pré-ranking interno** — candidatos organizados por tamanho e ranqueados internamente (memorabilidade, força fonética, posicionamento, originalidade) para selecionar os melhores para verificação externa real.
4. **Verificação externa real** — busca real (WebSearch) por empresa, app publicado, marca registrada e presença digital para cada nome pré-selecionado, em lotes, com checkpoint após cada lote.
5. **Eliminação de colisões** — remoção dos nomes com colisão relevante (mesmo setor de saúde/bem-estar, ou marca globalmente dominante em outro setor).
6. **Pontuação e ranking algorítmico** — fórmula ponderada definida antes da execução (ver `00_Config/config.md`) aplicada aos aprovados.

**Etapa Final — Conselho Global de Branding:** os 20 finalistas do ranking algorítmico passaram pelos 8 testes obrigatórios do briefing (memorabilidade, rádio, internacional, crescimento, posicionamento, visual, jurídico, escalabilidade até 2045), o que **reordenou** o ranking ao capturar riscos fonéticos e culturais que a verificação de colisão de marca, por si só, não identifica.

### Escopo calibrado com o usuário (importante para interpretar os números abaixo)
O briefing original pede ~5.000 candidatos e verificação externa de quase todo o funil. Isso foi conscientemente calibrado com o usuário **antes** de iniciar (registrado em `00_Config/config.md`), para não inflar números artificialmente nem inventar resultados de verificação:
- Geração: 300–800 candidatos reais (não 5.000), priorizando qualidade e diversidade metodológica genuína.
- Verificação externa real: aplicada aos 41 melhores candidatos após pré-ranking interno, não ao funil inteiro de 273 aprovados. Verificar centenas de nomes em 8 fontes externas cada exigiria centenas/milhares de buscas reais — inviável com o rigor de "nunca inventar resultado" combinado com o usuário.

---

## 2. Quantos nomes foram gerados?

**333 candidatos únicos** (sem duplicatas), distribuídos em 9 métodos de geração.

---

## 3. Quantos foram eliminados em cada etapa?

| Etapa | Entrada | Eliminados | Saída | Motivo principal |
|---|---|---|---|---|
| 2 — Filtros linguísticos | 333 | 60 | 273 | Raiz proibida, conotação médica/esportiva, colisão conhecida, conotação negativa, dificuldade de pronúncia, redundância sonora |
| 3 — Pré-ranking (seleção p/ verificação) | 273 | 232 não verificados* | 41 | Escopo de verificação calibrado com o usuário (ver acima) |
| 4 — Verificação externa | 41 | 0 (só classificação) | 41 | — |
| 5 — Eliminação de colisões | 41 | 17 | 24 | 11 colisões diretas no setor de saúde/bem-estar; 6 marcas globalmente dominantes em outros setores |
| 6 — Ranking algorítmico | 24 | 4 | 20 | Menor pontuação ponderada (Vaelis, Ghelan, Thallora, Heimora) |
| Final — Conselho Global de Branding | 20 | 0 (reordenação) | 20 | Reordenação qualitativa; nenhuma eliminação adicional, mas 5 nomes tiveram nota rebaixada por alertas fonéticos/culturais |

*Os 232 candidatos não verificados continuam disponíveis em `02_Filtros/candidatos_filtrados.csv` como banco de reserva caso o usuário deseje expandir a verificação no futuro.

---

## 4. Quais padrões fonéticos tiveram melhor desempenho?

Entre os 20 finalistas, a distribuição por método foi: céltico (5), nórdico (4), grego (3), proto-indo-europeu (3), latino (2), blend de fonemas (1), fonética moderna (1), metáfora inglesa (1).

- **Céltico** teve o melhor desempenho proporcional: 5 finalistas, com a maior taxa de nomes sem colisão relevante (Branora, Fionara, Torcis).
- **Blend de fonemas** produziu apenas 1 finalista, mas foi o **vencedor absoluto** (Duravia) — evidência de que combinar raízes reconhecíveis em português ("durar" + "via") com terminação neutra internacional é uma fórmula muito eficaz.
- **Nórdico** rendeu nomes sonoramente interessantes e distintos, mas foi o grupo com **maior taxa de alertas do Conselho** (3 de 4 — Vakora, Ljosa, Draumis — tiveram risco fonético/cultural identificado), sugerindo que raízes nórdicas exigem checagem multilíngue extra antes de avançar.
- **Grego** rendeu bons nomes em som e significado, mas teve a maior taxa de colisão direta no setor de saúde na fase de geração (Aion foi o pior caso, eliminado por colidir com três empresas de healthtech diferentes).

---

## 5. Quais padrões apresentaram maior disponibilidade (menor colisão)?

**Céltico e blend de fonemas** tiveram a menor taxa de colisão relevante entre os candidatos verificados. Isso provavelmente reflete o fato de raízes célticas serem menos exploradas comercialmente em tecnologia (comparado a raízes gregas/latinas, muito usadas por startups de saúde e biotech) e de blends específicos ao português serem, por definição, menos prováveis de coincidir com nomes já registrados internacionalmente.

---

## 6. Quais padrões tiveram menor risco jurídico?

Mesma resposta da pergunta 5: **céltico** (Branora, Fionara, Torcis — todos "baixo" risco jurídico) e **blend de fonemas** (Duravia — "baixo"). Em contraste, **grego** e **latino** tiveram a maior concentração de colisões de "alto" risco, especificamente por serem raízes muito usadas por empresas de biotecnologia e saúde digital já estabelecidas (Aion, Novum, Veraxa, Oriva, Astera, Itera).

---

## 7. Quais os 20 finalistas?

Ver tabela completa e fichas individuais em `05_Finalistas/TOP20_FINALISTAS.md`. Ranking final (após Conselho Global de Branding):

1. Duravia (88) · 2. Cosmora (79) · 3. Kairoa (78) · 4. Branora (74) · 5. Kaelis (73) · 6. Solvenne (72) · 7. Aevora (70) · 8. Sofira (68) · 9. Ravora (68) · 10. Fionara (66) · 11. Merisa (65) · 12. Darava (64) · 13. Kelara (63) · 14. Solvara (61) · 15. Belora (60) · 16. Vakora (58) · 17. Torcis (58) · 18. Sorenta (55) · 19. Ljosa (54) · 20. Draumis (52)

---

## 8. Se você fosse o responsável pela marca, qual escolheria e por quê?

**Duravia.**

É o único finalista que passa limpo por todos os 8 testes do Conselho sem nenhum alerta relevante: nenhuma colisão de marca encontrada na verificação externa real, pronúncia idêntica e fácil em português, inglês e espanhol, nenhuma conotação negativa em nenhum dos três idiomas, e desempenho forte em todas as extensões de crescimento testadas (Duravia App, Duravia AI, Duravia Cloud, Duravia Labs soam todos naturais e cabíveis).

Mais importante: o significado — "durar" (latim *durare*, persistir/continuar) + "via" (caminho) — comunica com precisão a proposta central do produto (acompanhar a jornada de saúde da pessoa do nascimento à velhice) sem usar nenhuma das raízes proibidas (vita/life/longev/etc.) e sem soar como uma marca clínica ou farmacêutica. É um nome que continua fazendo sentido narrativo mesmo se o produto evoluir para novas categorias no futuro — o teste de escalabilidade até 2045 favorece nomes com narrativa própria e não amarrada a uma tecnologia ou tendência específica, e "durar + caminho" é uma metáfora atemporal.

A única ressalva prática: como qualquer nome curto e pronunciável, uma busca formal de marca registrada nos escritórios relevantes (INPI no Brasil, USPTO nos EUA, EUIPO na União Europeia) e verificação formal de disponibilidade de domínio devem ser feitas antes do registro definitivo — a verificação aqui é uma triagem de alta confiança, não uma certidão jurídica.

---

## 9. Quais seriam os 5 nomes "reserva" caso o primeiro colocado não pudesse ser registrado?

Os 5 nomes seguintes no ranking, todos com desempenho forte e nenhum alerta crítico do Conselho:

1. **Cosmora** (79) — maior potencial de sistema visual (identidade "cósmica"); atenção à colisão com app de tarot já publicado (categoria de consumo diferente).
2. **Kairoa** (78) — conceito forte ("momento certo"); atenção à colisão com cervejaria (setor não relacionado, risco de confusão real baixo).
3. **Branora** (74) — segundo nome mais "limpo" do projeto inteiro (nenhuma colisão relevante encontrada), boa alternativa direta a Duravia.
4. **Kaelis** (73) — curto e moderno; colisão B2B em setor totalmente diferente (aviação/ferrovias).
5. **Solvenne** (72) — boa opção se o posicionamento evoluir para ênfase em "resolver problemas de saúde com IA" em vez de "jornada contínua".

---

## 10. Quais aprendizados importantes surgiram durante o processo?

1. **Nomes "bonitos" e pronunciáveis quase sempre já estão em uso.** Dos 41 candidatos verificados externamente com busca real, apenas 4 (~10%) não tiveram nenhuma correspondência encontrada. A taxa de colisão de qualquer tipo foi de ~83%. Isso é uma evidência prática de que gerar um nome "perfeito e livre" em escala é muito mais difícil do que os brainstorms de naming costumam sugerir — a etapa de verificação real é indispensável, não opcional.
2. **O setor de saúde digital/preventiva está saturado de nomes curtos com raízes gregas/latinas de continuidade e vitalidade.** 11 dos 41 candidatos verificados colidiram diretamente com startups de saúde/bem-estar já existentes (alguns com posicionamento quase idêntico ao do usuário, como Trellis Health e Verano Health). Isso sugere que o espaço de naming "óbvio" para saúde preventiva com IA já está bastante ocupado.
3. **Verificação de colisão de marca não é suficiente — risco fonético/cultural exige revisão humana multilíngue.** 5 dos 20 finalistas (25%) tinham um risco relevante que nenhuma busca de marca captura: Vakora soa como "vaca" em português, Draumis soa como "trauma" em três idiomas, Sorenta soa como o SUV Kia Sorento, Fionara evoca a personagem Fiona de Shrek, e Torcis pode soar como "torcicolo". Esse tipo de alerta só surge com uma leitura humana deliberada nos três idiomas-alvo, reforçando o valor da etapa de Conselho de Branding como uma camada distinta (e não redundante) da verificação jurídica.
4. **Métodos de geração menos explorados comercialmente (céltico, blends específicos ao português) tendem a ter menor taxa de colisão** do que raízes gregas/latinas mais "óbvias" para tecnologia e saúde.
5. **Limitação a ser comunicada com transparência ao usuário:** por decisão de escopo combinada previamente, a verificação externa real cobriu 41 dos 273 candidatos aprovados nos filtros linguísticos (não o funil inteiro). Os 232 candidatos restantes permanecem disponíveis em `02_Filtros/candidatos_filtrados.csv` como banco de reserva. Além disso, nenhuma verificação formal de registro de marca (INPI/USPTO/EUIPO) ou WHOIS de domínio foi realizada — a verificação aqui usa busca pública real como triagem de alta confiança, não como certidão jurídica definitiva.
