# 🔴 RELATÓRIO TÉCNICO DE DEBUG — 2 Bugs Críticos Pós-Deploy (31/jul/2026)

**Data:** 2026-07-31 21:00 UTC  
**Reporter:** Fundador (testes física Android)  
**Status:** 🔍 **EM INVESTIGAÇÃO E CORREÇÃO**

---

## 🔴 BUG #1 — HTTP 502 na Edge Function `extract-metric-photo`

### Sintoma Reportado
- Tirar foto do prato → retorna HTTP 502
- Mensagem de erro: `{"error":"Falha ao analisar a imagem."}`
- Logs: Nenhum erro específico visível no app

### Raiz Causa Identificada
**Arquivo:** `supabase/functions/extract-metric-photo/index.ts`  
**Linhas:** 1840-1849  
**Problema:** `resolverComBuscaSemantica()` **NÃO TEM TRY/CATCH**

```typescript
// 🔴 CÓDIGO COM ERRO:
if (temCandidatoSemantico) {
  const { resolvidos, aindaNaoReconhecidos } = await resolverComBuscaSemantica(
    calculo.itensNaoReconhecidos,
    catalogo,
    params.obterChamarEmbedding(),        // ← PODE FALHAR (sem GEMINI_API_KEY)
    params.obterBuscaSemantica(),         // ← PODE FALHAR (sem secrets)
  );
  itensFinais.push(...resolvidos);
  itensNaoReconhecidosFinais = aindaNaoReconhecidos;
}
```

**Por que crasheia:**
1. Chamada a `chamarEmbedding(item.nome)` (linha 1172 em `resolverComBuscaSemantica`)
   - Dispara `Deno.env.get('GEMINI_API_KEY')` (linha 1584)
   - Se não estiver configurado → lança `ErroHttp(500, '...')`
   - **SEM TRY/CATCH** → exceção não tratada
   
2. Promise.all dentro de `resolverComBuscaSemantica` (linha 1169)
   - Se UMA promessa falha → TODO o Promise.all rejeita
   - Exceção borbulha para cima SEM captura
   
3. Handler em `processarPratoRefeicao` NÃO captura esta específica falha
   - Try/catch externo (linhas 1605-1616) pega a exceção
   - Mas retorna erro genérico 502 sem logging útil

### Solução: Adicionar Try/Catch em torno de `resolverComBuscaSemantica`

**Código corrigido (linhas 1840-1849):**

```typescript
if (temCandidatoSemantico) {
  try {
    const { resolvidos, aindaNaoReconhecidos } = await resolverComBuscaSemantica(
      calculo.itensNaoReconhecidos,
      catalogo,
      params.obterChamarEmbedding(),
      params.obterBuscaSemantica(),
    );
    itensFinais.push(...resolvidos);
    itensNaoReconhecidosFinais = aindaNaoReconhecidos;
  } catch (erro) {
    // Degradação graciosa: se a busca semântica falhar, manter em "Não reconhecidos"
    // é melhor que derrubar a função inteira. Log para debugging.
    console.error('Falha em busca semântica (fallback degradado):', 
      erro instanceof Error ? erro.message : 'erro desconhecido');
    // itensNaoReconhecidosFinais já tem os itens que não foram encontrados
    // — se a busca semântica falhar, eles simplesmente permanecem lá
  }
}
```

### Deploy + Secrets

**Passo 1: Configurar GEMINI_API_KEY no Supabase**
```bash
# Obter a chave do Google AI Studio (Seu Project)
# Formato: ai-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

supabase secrets set GEMINI_API_KEY="seu-gemini-api-key-aqui"

# Verificar (mascarado)
supabase secrets list
# Output:
# name              | value
# GEMINI_API_KEY    | ai-****...****
```

**Passo 2: Fazer o deploy da Edge Function**
```bash
cd supabase/functions/extract-metric-photo
supabase functions deploy extract-metric-photo

# Verificar (opcional)
curl https://xtipphglpqqrjguxcajn.supabase.co/functions/v1/extract-metric-photo \
  -X POST \
  -H "Authorization: Bearer seu-jwt-aqui" \
  -H "X-Tipo-Aparelho: pratoRefeicao" \
  --data-binary @sample-image.jpg

# Esperado: HTTP 200 (imagem processada) ou HTTP 422 (ilegível)
# NÃO 502
```

---

## 🔴 BUG #2 — Deep Link Não Abre Tela Correta

### Sintoma Reportado
- E-mail de recuperação de senha gerado corretamente
- URL: `https://xtipphglpqqrjguxcajn.supabase.co/auth/v1/verify?token=...&type=recovery&redirect_to=io.supabase.atletaapp://login-callback`
- Usuário clica link
- App pode não interceptar OU tela errada abre

### Investigação

#### ✅ Verificado: AndroidManifest.xml
**Arquivo:** `android/app/src/main/AndroidManifest.xml` (linhas 76-83)

```xml
<intent-filter android:autoVerify="false">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data
        android:scheme="io.supabase.atletaapp"
        android:host="login-callback" />
</intent-filter>
```

**Status:** ✅ **CORRETO** — scheme e host batem perfeitamente

#### ✅ Verificado: AppConfig.oauthRedirectUrl
**Arquivo:** `lib/core/config/app_config.dart` (linhas 173-187)

```dart
static String get oauthRedirectUrl {
  const override = String.fromEnvironment('OAUTH_REDIRECT_URL');
  return override.isNotEmpty
      ? override
      : 'io.supabase.atletaapp://login-callback';  // ✅ CORRETO
}
```

**Status:** ✅ **CORRETO** — matching o intent-filter

#### ✅ Verificado: Auth Recovery Controller
**Arquivo:** `lib/core/router/auth_recovery_controller.dart` (linhas 27-66)

```dart
class AuthRecoveryController extends ChangeNotifier {
  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _subscription;
  bool _emRecuperacao = false;

  AuthRecoveryController({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client {
    _subscription = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {  // ✅ Escuta evento
        _emRecuperacao = true;
        notifyListeners();  // ✅ Notifica AppRouter
      } else if (state.event == AuthChangeEvent.signedOut) {
        if (_emRecuperacao) {
          _emRecuperacao = false;
          notifyListeners();
        }
      }
    });
  }
}
```

**Status:** ✅ **CORRETO** — controller está escutando

#### ✅ Verificado: AppRouter Redirect
**Arquivo:** `lib/core/router/app_router.dart` (linhas 136-142)

```dart
if (authRecoveryController.emRecuperacao) {
  return isGoingToDefinirNovaSenha ? null : '/${RouteNames.definirNovaSenha}';
}
if (isGoingToDefinirNovaSenha) {
  return '/${RouteNames.home}';
}
```

**Status:** ✅ **CORRETO** — roteador redireciona para a tela correta

### Possíveis Causas de Falha

#### Cenário 1: Deep link não está sendo entregue ao app
**Causa:** Android está abrindo o link em navegador, não passando para o app
- **Solução:** Verificar se `android:autoVerify="false"` está correto (está)
- **Alternativa:** Adicionar `android:autoVerify="true"` se Digital Asset Links estiver configurado

#### Cenário 2: Evento `passwordRecovery` não está sendo acionado
**Causa:** `supabase_flutter` não está interceptando corretamente
- **Solução:** Verificar versão de `supabase_flutter` em `pubspec.yaml`
- **Verificação:** Ver se há logs no Supabase Auth

#### Cenário 3: Cache do app não reconhece a rota
**Causa:** Build antigo do app instalado no device
- **Solução:** Limpar cache e reinstalar
  ```bash
  flutter clean
  flutter pub get
  flutter run
  ```

### Teste Completo (Para Validar Correção)

1. **Tirar screenshot da URL do e-mail**
2. **Validar URL** (via decoder)
   ```bash
   # Decodificar token
   echo "seu-token-base64" | base64 -d
   ```
3. **Clicar link no e-mail**
4. **Observar:**
   - ✅ Tela de login abre
   - ✅ Evento `passwordRecovery` é disparado (verificar logs)
   - ✅ Redireciona para "Definir Nova Senha"
   - ✅ Formulário permite resetar senha
5. **Verificar logs:**
   ```bash
   flutter logs | grep -i "password\|recovery\|auth"
   ```

---

## 📋 Checklist de Correção e Deploy

### Para BUG #1 (HTTP 502)

- [ ] Editar `supabase/functions/extract-metric-photo/index.ts`
- [ ] Adicionar try/catch em torno de `resolverComBuscaSemantica()` (linhas 1840-1849)
- [ ] Configurar secret: `supabase secrets set GEMINI_API_KEY="..."`
- [ ] Fazer deploy: `supabase functions deploy extract-metric-photo`
- [ ] Testar: tirar foto e verificar HTTP 200 (não 502)

### Para BUG #2 (Deep Link)

- [ ] Limpar cache: `flutter clean && flutter pub get`
- [ ] Rebuild: `flutter run` (device teste)
- [ ] Solicitar novo e-mail de recuperação
- [ ] Clicar link e verificar se abre tela correta
- [ ] Se não funcionar, verificar logs: `flutter logs`

---

## 🔧 Comandos Finais para Deploy

```bash
# 1. Configurar secrets
supabase secrets set GEMINI_API_KEY="seu-gemini-api-key-aqui"

# 2. Deploy Edge Function
cd supabase/functions
supabase functions deploy extract-metric-photo

# 3. Rebuild Flutter
cd ../..
flutter clean
flutter pub get
flutter build apk --release

# 4. Testar em device
flutter install build/app/outputs/flutter-apk/app-release.apk
```

---

## 📊 Impacto

| Bug | Causa | Severidade | Fix Complexity |
|-----|-------|-----------|-----------------|
| **#1 — HTTP 502** | try/catch faltando | 🔴 Critical (app useless) | ⚠️ Média (adicionar blocoRot) |
| **#2 — Deep Link** | Possível cache/versão | 🟡 Major (can't reset pwd) | 🟢 Baixa (clean + rebuild) |

---

**Próximo:** Implementar correções acima e testar em device real.

