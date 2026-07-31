# 🚀 Instruções de Deployment — 2 Bug Fixes Críticos

**Data:** 2026-07-31  
**Commit:** e013f5e (BUG #1 fix)  
**Status:** Pronto para deployment imediato

---

## 🔴 BUG #1 — HTTP 502 (Edge Function)

### Passo 1: Configurar Secret no Supabase

```bash
# Obter GEMINI_API_KEY do Google AI Studio
# Acesse: https://aistudio.google.com/app/apikey
# Formato: ai-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Configurar no Supabase (escolha uma opção)

# OPÇÃO A — Via CLI (recomendado)
supabase secrets set GEMINI_API_KEY="seu-gemini-api-key-aqui"

# OPÇÃO B — Via Dashboard
# 1. Ir para: https://supabase.com/dashboard
# 2. Projeto → Settings → Secrets
# 3. Clicar "Create new secret"
# 4. Name: GEMINI_API_KEY
# 5. Value: seu-gemini-api-key-aqui
# 6. Salvar

# Verificar (mascarado por segurança)
supabase secrets list
# Output:
# name              | value
# GEMINI_API_KEY    | ai-****...****
```

### Passo 2: Deploy Edge Function Corrigida

```bash
# Navegar para diretório
cd supabase/functions/extract-metric-photo

# Deploy
supabase functions deploy extract-metric-photo

# Esperado:
# Bundling Function: extract-metric-photo
# Deploying Function: extract-metric-photo (script size: 92 kB)
# {"functions":["extract-metric-photo"],"message":"Deployed Functions."}
```

### Passo 3: Testar

```bash
# Verificar que a function está viva (aguarda POST)
curl -X OPTIONS https://xtipphglpqqrjguxcajn.supabase.co/functions/v1/extract-metric-photo

# Esperado: HTTP 200 com CORS headers

# Teste completo: usar app Flutter
# 1. Abrir app
# 2. Tirar foto do prato
# 3. Verificar: HTTP 200 (não 502)
```

---

## 🔴 BUG #2 — Deep Link (Flutter App)

### Passo 1: Limpar Cache e Rebuild

```bash
# Limp cache Flutter
flutter clean

# Baixar dependências novamente
flutter pub get

# Rebuild App (debug)
flutter run

# Ou rebuild Release (para testes em device)
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Passo 2: Instalar Novamente em Device

```bash
# Se usando APK release
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Ou se usando flutter run (já instala automaticamente)
```

### Passo 3: Testar Deep Link

```bash
# Cenário de teste completo:
# 1. Abrir app
# 2. Tela Login → clique "Esqueci minha senha"
# 3. Entrar e-mail válido (ou criado para teste)
# 4. Receber e-mail com link de recuperação
# 5. **IMPORTANTE:** Abrir email NO DEVICE (não no PC)
# 6. Clicar link na mensagem
# 7. Verificar:
#    ✅ App abre (não navegador)
#    ✅ Tela "Definir Nova Senha" aparece
#    ✅ Campo de senha está focado
#    ✅ Botão "Atualizar Senha" funciona
# 8. Digitar nova senha 2x e confirmar
# 9. Verificar: redireciona para login

# Logs para debugging (terminal)
flutter logs | grep -i "password\|recovery\|auth\|deep"
```

---

## 🔄 Ordem de Deployment

### Timing Recomendado

1. **Imediato (agora):** Configurar GEMINI_API_KEY no Supabase
2. **Imediato (agora):** Deploy Edge Function
3. **Após teste do BUG #1:** Rebuild Flutter e testar
4. **Final:** Publicar APK/Bundle em Play Store/TestFlight

### Sequência Executável

```bash
# 1. Setup Supabase Secret
supabase secrets set GEMINI_API_KEY="seu-gemini-api-key-aqui"

# 2. Deploy Edge Function (leva ~30 segundos)
cd supabase/functions
supabase functions deploy extract-metric-photo
cd ../..

# 3. Rebuild Flutter (leva ~2-3 minutos)
flutter clean
flutter pub get
flutter build apk --release

# 4. Instalar em device de teste
adb install -r build/app/outputs/flutter-apk/app-release.apk

# 5. Validar no device
echo "Executar testes de BUG #1 e #2 conforme instruções acima"
```

---

## ⚠️ Troubleshooting

### BUG #1 Ainda Retorna 502?

```bash
# Verificar se secret foi configurado
supabase secrets list

# Se não aparecer ou estiver vazio:
supabase secrets set GEMINI_API_KEY="seu-api-key"

# Redeploy (força re-read de secrets)
cd supabase/functions
supabase functions deploy extract-metric-photo

# Aguardar ~1 minuto para propagação em todos servidores

# Verificar logs da Edge Function
# Via Dashboard: Functions → extract-metric-photo → Logs
```

### BUG #2 Deep Link Ainda Não Funciona?

```bash
# 1. Verificar se AndroidManifest.xml está correto
grep -A 8 "login-callback" android/app/src/main/AndroidManifest.xml
# Esperado: scheme="io.supabase.atletaapp" + host="login-callback"

# 2. Limpar cache completamente
flutter clean
rm -rf build ios .dart_tool pubspec.lock
flutter pub get

# 3. Rebuild zero
flutter run --no-fast-start

# 4. Verificar logs
flutter logs

# Se ainda não funcionar:
# - Verificar se Supabase Auth está enviando e-mail correto
# - Validar URL do e-mail (base64 decode do token)
# - Testar com URL direta no navegador
```

---

## 📱 Device Teste Recomendado

- **Android:** Versão 11+ (teste com versão mínima suportada também)
- **E-mail:** Conta Supabase válida (criar se necessário)
- **Conexão:** WiFi + dados móveis (teste ambos)

---

## ✅ Checklist Final

- [ ] GEMINI_API_KEY configurado no Supabase
- [ ] Edge Function deployada
- [ ] BUG #1 testado (foto do prato funciona sem 502)
- [ ] Flutter rebuild com clean concluído
- [ ] App instalado em device de teste
- [ ] BUG #2 testado (e-mail de recuperação abre app)
- [ ] Ambas funcionalidades funcionando
- [ ] Pronto para produção

---

**Status:** 🟢 Pronto para deployment imediato

