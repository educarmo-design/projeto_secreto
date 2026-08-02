# Configuração do Projeto de Naming Global

**Data/hora de início:** 2026-07-31
**Produto:** Plataforma de saúde preventiva com IA (jornada nascimento → velhice; app Android/iOS, web, painel profissional, APIs futuras)
**Metodologia:** Pipeline em etapas com checkpoints em arquivo, conforme briefing do usuário (seção "MODO DE EXECUÇÃO").

## Escopo calibrado com o usuário (2026-07-31)

O briefing original pede ~5.000 candidatos brutos e verificação externa real (domínio, redes sociais, app stores, busca) para uma fração muito grande do funil. Isso foi calibrado com o usuário antes de iniciar, para não inflar números nem inventar resultados de verificação:

- **Geração (Etapa 1):** 300–800 candidatos reais e diversos (não 5.000 infladados) — prioriza qualidade e diversidade metodológica real sobre volume bruto.
- **Verificação externa real (Etapa 4):** aplicada apenas aos ~30–50 melhores candidatos após pré-ranking interno (fonética, memorabilidade, força visual, neutralidade), não ao funil inteiro. Motivo: verificar centenas de nomes em 8 fontes externas cada exigiria centenas/milhares de buscas reais — inviável com rigor de "nunca inventar resultado" em uma sessão. Nomes fora da shortlist de verificação permanecem candidatos "não verificados externamente" e podem ser checados manualmente depois pelo usuário.

## Regras fixas do briefing (não alteradas)

### Evitar raízes/palavras
vita, vital, life, live, living, bio, health, healthy, doctor, med, medicine, clinic, care, fit, fitness, well, wellness, pulse, track, tracking, sync, smart, longev, longo, long, safe, guardian.

### Evitar proximidade com marcas conhecidas
Apple, Google, Microsoft, Amazon, Garmin, Whoop, Fitbit, Huawei, Samsung, Oura, Strava, Notion, Asana, Figma, Spotify, OpenAI, Anthropic, Tesla, Oracle, SAP, Epic, Philips, Abbott, Medtronic.

### Idiomas-alvo
Português, Inglês, Espanhol — pronúncia simples, sem acentos, sem caracteres especiais.

### Público
Não pode privilegiar nenhum grupo (crianças, jovens, adultos, idosos, atletas, sedentários, médicos, nutricionistas, treinadores, clínicas, empresas).

### Posicionamento desejado
Continuidade, evolução, energia, inteligência, confiança, longevidade, tecnologia humana, organização da vida, plataforma premium. "Saúde" não precisa aparecer no nome — é consequência, não o nome.

## Algoritmo de pontuação (Etapa 6) — definido antes de rodar, para não enviesar

Pontuação 0–100, média ponderada de:

| Critério | Peso |
|---|---|
| Memorabilidade | 20% |
| Pronúncia/força fonética (PT/EN/ES) | 20% |
| Neutralidade internacional / ausência de significado negativo | 15% |
| Força visual (logotipo, ícone, domínio) | 10% |
| Originalidade / distância de concorrentes | 15% |
| Escalabilidade (Nome + App/Cloud/AI/Kids/Coach/Pro/API/Labs) | 10% |
| Disponibilidade externa real (apenas para os verificados) | 10% |

Nomes não verificados externamente recebem nota neutra (não penalizada nem bonificada) nesse último critério, e isso é sinalizado explicitamente no relatório.

## Estrutura de pastas

```
Projeto_Naming_Global/
  00_Config/
  01_Geracao/
  02_Filtros/
  03_Verificacao/
  04_Ranking/
  05_Finalistas/
  06_Relatorios/
  checkpoints/
```
