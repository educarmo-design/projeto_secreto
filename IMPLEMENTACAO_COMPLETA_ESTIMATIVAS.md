# ✅ Implementação Completa: Estimativas de Peso e Líquidos

**Data:** 01/ago/2026  
**Commits:** 868f860 (main)  
**Status:** 🟢 **DEPLOYADO E PRONTO PARA TESTE**

---

## 📋 O que foi Implementado

### 1️⃣ **Backend: Tabelas Expandidas**

**Problema Original:**
```
Azeitona → 100g (errado, é 1 azeitona ~5g)
Presunto → 100g (errado, é 1 fatia ~20g)
```

**Solução Implementada:**
```typescript
const PESO_TIPICO_GRAMAS = {
  // ~50 alimentos com granularidade
  'Azeitona, 1 unidade': 5,
  'Presunto, 1 fatia': 20,
  'Pão, 1 fatia': 40,
  'Ovo, 1 unidade': 50,
  'Bolo, 1 fatia': 100,
  // ... mais 45 alimentos
};
```

**Resultado:**
- ✅ 50 alimentos órfãos com pesos típicos granulares
- ✅ Redução de erro de 2-20x em casos comuns
- ✅ Nomenclatura clara: "{alimento}, {unidade}"

---

### 2️⃣ **Backend: Suporte para Líquidos**

**Problema Original:**
```
Suco de laranja → calcular em gramas (impreciso)
"1 copo" → sem saber se é copo pequeno, médio ou grande
```

**Solução Implementada:**
```typescript
const ALIMENTOS_LIQUIDOS = new Set([
  'suco', 'leite', 'café', 'chá', 'refrigerante', 
  'água', 'vinho', 'cerveja', ...
]);

const TAMANHO_COPOS_ML = {
  'pequeno': 150,
  'médio': 250,
  'grande': 350,
  'xícara': 200,
  'lata': 350,
};

// Automaticamente:
// 1. Detecta se é líquido
// 2. Estima ml por tamanho de recipiente
// 3. Converte ml→gramas (densidade ~1)
```

**Resultado:**
- ✅ Suco automaticamente em ml em vez de g
- ✅ Estimativa de tamanho de copo
- ✅ Conversão transparente (ml = g para cálculo)

---

### 3️⃣ **Frontend: Mostrar Gramas do Peso Típico**

**Problema Original:**
```
Usuário vê: "40g (est.)"
Não sabe: qual é o peso típico exato
```

**Solução Implementada:**

Card de confirmação agora exibe:
```
Azeitona  [delete]
⚠️ Quantidade estimada — edite se necessário
   Peso típico: 5g
confiança: 90%
```

**UI Melhorada:**
- ✅ Chip amarelo com ⚠️ visual
- ✅ Tooltip educativo
- ✅ Mostra claramente: "Peso típico: Xg"
- ✅ Botões +/- permitem editar em tempo real

---

### 4️⃣ **Análise de Dados: Inventário de Órfãos**

**Documento Criado:** `INVENTARIO_ALIMENTOS_ORFAOS.md`

**Contém:**
- Query SQL para encontrar alimentos sem medidas
- Priorização: críticos (>50 usos) vs baixo (0-10 usos)
- Procedimento para agregar novos pesos
- Top 20 alimentos candidatos já pré-compilados

**Uso:**
```bash
1. Rodar query no Supabase Dashboard
2. Copiar resultados
3. Adicionar à tabela PESO_TIPICO_GRAMAS
4. Deploy e testar
```

---

## 📊 Impacto de Precisão

### Exemplos Reais:

| Alimento | Antes | Depois | Ganho |
|----------|-------|--------|-------|
| **Azeitona (1 unidade)** | 100g → 145 kcal | 5g → 7 kcal | **20x mais preciso** |
| **Presunto (1 fatia)** | 100g → 310 kcal | 20g → 62 kcal | **5x mais preciso** |
| **Suco (copo médio)** | 100g | 250ml | **+Correto!** |
| **Bolo (1 fatia)** | 100g → 360 kcal | 100g → 360 kcal | Já certo ✅ |
| **Ovo (1 unidade)** | 100g (2 ovos) | 50g (1 ovo) | **2x mais preciso** |

---

## 🚀 Roadmap Futuro

### Fase Atual (Já Feito):
- [x] Tabelas expandidas (~50 alimentos)
- [x] Suporte para líquidos (detecção + ml)
- [x] UI mostrando peso típico
- [x] Documento de inventário

### Próxima Sprint:
- [ ] Rodar query para alimentos órfãos MAIS usados
- [ ] Expandir tabela para 100-150 alimentos
- [ ] User feedback loop (ajustar pesos baseado em edições)

### Futuro (Roadmap Longo):
- [ ] ML: treinar modelo para estimar peso por foto
- [ ] Crowdsource: usuários reportam peso real
- [ ] OCR: ler peso do rótulo de produtos
- [ ] Integração com APIs nutricionais (USDA, TACO)

---

## 🧪 Como Testar

### Teste 1: Alimentos Granulares
```
1. Tirar foto com:
   - 1 azeitona
   - 1 fatia de presunto
   - 1 fatia de pão
2. Verificar:
   ✅ Azeitona → 5g (não 100g)
   ✅ Presunto → 20g (não 100g)
   ✅ Pão → 40g (não 100g)
   ✅ Cada tem ⚠️ aviso de "estimado"
   ✅ Mostra "Peso típico: Xg"
```

### Teste 2: Líquidos
```
1. Registrar refeição com:
   - Suco de laranja "copo médio"
   - Leite "xícara"
   - Café "xícara pequena"
2. Verificar:
   ✅ Suco → 250ml (não gramas)
   ✅ Leite → 200ml
   ✅ Café → 150ml
   ✅ Cálculos de macros corretos
```

### Teste 3: Edição
```
1. Confirmar refeição estimada
2. Na tela de confirmação:
   ✅ Clicar botão +/- para aumentar quantidade
   ✅ Macros recalculam em tempo real
   ✅ Exemplo: 5g → 10g (azeitona dupla)
```

---

## 📁 Arquivos Modificados

### Backend:
- `supabase/functions/extract-metric-photo/index.ts`
  - +~150 linhas: tabelas expandidas + lógica de líquidos
  - Novas funções: `ehAlimentoLiquido()`, `estimarTamanhoRecipiente()`
  - Modificado: `encontrarMedida()` para usar novas tabelas

### Frontend:
- `lib/features/nutrition/presentation/pages/confirmacao_prato_page.dart`
  - Melhorado: exibição de peso típico com estrutura Column
  - Novo: campo `pesoTipicoGramas` no aviso

### Tradução:
- `assets/i18n/pt.json`
  - Nova chave: `confirmacao_prato.peso_tipico`

### Documentação:
- `INVENTARIO_ALIMENTOS_ORFAOS.md` (novo)
- `IMPLEMENTACAO_COMPLETA_ESTIMATIVAS.md` (novo)

---

## 🔧 Commits Relacionados

```
868f860 feat(complete nutrition estimation): expanded tables, liquids, granular weights
dcc26ea feat(weight-based estimation): typical serving weights + visual warnings
fdb8d48 perf(extract-metric-photo): 40x ID lookup, 3x measure normalization
8a263a3 ui(confirmacao_prato): swap card order — show nomeIdentificado first
7c63f9a fix(extract-metric-photo): add grama fallback for foods with no measures
14083ed fix: revert embedding model from text-embedding-004 to gemini-embedding-001
4ea53bd fix(extract-metric-photo): threshold + measure normalization + semantic search logs
```

---

## ✅ Checklist Pré-Produção

- [x] Backend deployado (97 kB)
- [x] Frontend alterado (confirmacao_prato_page.dart)
- [x] Tradução adicionada
- [x] Logs de debug inclusos
- [x] Documentação completa
- [ ] Teste em device (aguardando)
- [ ] Query SQL executada para alimentos órfãos (próxima etapa)
- [ ] Tabela expandida para 100+ alimentos (futuro)

---

## 🎯 Conclusão

Implementação COMPLETA de:
1. ✅ Tabelas expandidas com granularidade (50 alimentos)
2. ✅ Suporte para líquidos (detecção automática + ml)
3. ✅ UI mostrando peso típico claramente
4. ✅ Documentação para inventário de órfãos

**Status:** 🟢 Pronto para rebuild e teste em campo!

Próximo passo: Rodar query para descobrir top 50 alimentos órfãos mais usados e expandir tabela.

