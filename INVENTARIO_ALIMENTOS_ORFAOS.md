# 📊 Inventário de Alimentos Órfãos (Sem Medidas)

**Data:** 01/ago/2026  
**Objetivo:** Identificar alimentos que não têm medidas caseiras cadastradas — candidatos para adicionar à tabela `PESO_TIPICO_GRAMAS`

---

## 🔍 Como Rodar a Query

### Via Supabase Dashboard:
1. Ir para: https://supabase.com/dashboard/project/xtipphglpqqrjguxcajn/sql
2. Colar a query abaixo
3. Clicar "Run"
4. Resultado: lista de alimentos órfãos ordenados por frequência

---

## 📋 Query SQL

```sql
-- QUERY 1: Encontrar alimentos SEM NENHUMA medida cadastrada
SELECT 
  ar.id,
  ar.nome_taco,
  ar.calorias_kcal_100g,
  ar.proteinas_g_100g,
  ar.carboidratos_g_100g,
  ar.gorduras_g_100g,
  COUNT(amc.alimento_id) as total_medidas,
  (SELECT COUNT(*) FROM coleta_diaria cd WHERE cd.alimento_id = ar.id) as vezes_selecionado
FROM alimentos_referencia ar
LEFT JOIN alimentos_medidas_caseiras amc ON ar.id = amc.alimento_id
WHERE amc.alimento_id IS NULL  -- SEM medidas
GROUP BY ar.id, ar.nome_taco, ar.calorias_kcal_100g, ar.proteinas_g_100g, ar.carboidratos_g_100g, ar.gorduras_g_100g
ORDER BY vezes_selecionado DESC, ar.nome_taco ASC
LIMIT 500;
```

---

## 📈 Interpretação dos Resultados

Colunas:
- **nome_taco** — Nome canônico do alimento
- **calorias_kcal_100g** — Valor nutricional por 100g
- **total_medidas** — Número de medidas caseiras (deve ser 0 para órfãos)
- **vezes_selecionado** — Quantas vezes usuários tentaram usar este alimento

### Prioridade de Adição à Tabela:

1. **CRÍTICO** (vezes_selecionado > 50): Muito usado, deve ter peso típico
2. **IMPORTANTE** (10-50): Usado com frequência, adicionar
3. **BAIXO** (0-10): Raramente usado, pode deixar para depois

---

## 🎯 Próximos Passos Após Obter Resultados

### Passo 1: Agregar Resultados
```bash
# Copiar CSV da query e analisar
# Exemplo de linha:
# id | nome_taco | calorias | proteinas | carboidratos | gorduras | total_medidas | vezes_selecionado
# abc | Azeitona, verde | 145 | 0.8 | 3.8 | 13.3 | 0 | 15
```

### Passo 2: Decidir Peso Típico

Para cada alimento, estimar o peso de uma "unidade" baseado em:

**Fonte 1: Google/USDA**
```bash
# Exemplo: "Azeitona verde"
# Pesquisa: "azeitona verde peso"
# Resultado: ~5g por azeitona
```

**Fonte 2: Raciocínio Comum**
```bash
# Exemplo: "Presunto, cozido"
# Se alguém diz "1 fatia", estimar peso
# Resultado: ~20g por fatia
```

**Fonte 3: User Feedback**
```bash
# Se houver muitas edições pós-estimativa
# Usuários editando de 100g → 40g = ajuste de 2.5x
# Indicativo de que estimativa inicial estava errada
```

### Passo 3: Adicionar à Tabela

Quando tiver a lista, adicionar ao código:

```typescript
const PESO_TIPICO_GRAMAS: Record<string, number> = {
  // NOVO (adicionado em 01/ago/2026):
  'Azeitona, verde, 1 unidade': 5,
  'Azeitona, preta, 1 unidade': 5,
  'Camarão, seco, 1 unidade': 3,
  'Castanha de caju, 1 unidade': 1,
  ...
};
```

---

## 📊 Alternativa: Procurar por Padrão

Se preferir algoritmo automático, usar este critério:

**Para Frutas/Sementes (unidade):**
- Peso tipicamente entre 1-200g
- Usar 10% do peso médio de fruto inteiro

**Para Carnes/Frios (fatia):**
- Peso tipicamente entre 20-50g
- Usar 25g como padrão

**Para Sobremesas (unidade/fatia):**
- Peso tipicamente entre 30-150g
- Usar 80g como padrão

**Para Alimentos Processados:**
- Consultar rótulo do produto (quando disponível)

---

## 🔧 Monitoramento Contínuo

Após adicionar pesos, monitorar:

1. **Logs de ajuste:**
```
[encontrarMedida] Fallback sólido: "..." -> "40g (est.)" para "Azeitona, verde"
```

2. **Edições pós-confirmação:**
   - Se usuários frequentemente editam a quantidade após confirmação
   - Indica que peso típico estava errado

3. **Feedback de usuário:**
   - Se reclamar que "1 azeitona não vale 5g"
   - Significa que estimativa errou

---

## 📌 Dicas Práticas

### Convenções de Nomenclatura na Tabela:
```
❌ ERRADO:
'Alimento': 100,
'Alimento, grande': 150,

✅ CORRETO:
'Alimento, 1 unidade': 50,
'Alimento, 1 fatia': 20,
'Alimento, 1 colher sopa': 15,
```

### Por Quê?
- Deixa claro qual é a "porção" sendo estimada
- Facilita auditoria (usuário vê "5g, 1 azeitona")
- Permite busca parcial no código

---

## 🚀 Implementação Rápida

### Se pressa, usar estes como "top 20":

```typescript
// TOP 20 mais críticos (rodar query primeiro para verificar)
const PESO_TIPICO_GRAMAS_TOP20 = {
  'Azeitona, 1 unidade': 5,
  'Uva, 1 unidade': 2,
  'Cereja, 1 unidade': 4,
  'Amora, 1 unidade': 1,
  'Morango, 1 unidade': 15,
  'Amendoim, 1 unidade': 1,
  'Castanha, 1 unidade': 3,
  'Presunto, 1 fatia': 20,
  'Queijo, 1 fatia': 30,
  'Bacon, 1 fatia': 15,
  'Pão, 1 fatia': 40,
  'Ovo, 1 unidade': 50,
  'Chocolate, 1 quadrado': 10,
  'Brigadeiro, 1 unidade': 20,
  'Bolo, 1 fatia': 100,
  'Biscoito, 1 unidade': 12,
  'Linguiça, 1 unidade': 80,
  'Salsicha, 1 unidade': 50,
  'Bolinho, 1 unidade': 40,
  'Coxinha, 1 unidade': 45,
};
```

---

**Próximo:** Rodar query, agregar resultados, expandir tabela com "top 50" alimentos mais usados.

