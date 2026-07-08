# Permissões nativas — Telemetria de Saúde (ONDA 3)

Este repositório ainda não tem `android/` nem `ios/` gerados (`flutter create .`
nunca rodou aqui — só `lib/` + `pubspec.yaml`). Os trechos abaixo são a
referência exata a colar nesses arquivos assim que os projetos nativos forem
gerados; até lá, `lib/features/dashboard/data/services/health_sync_service.dart`
e o fluxo de câmera compilam e passam no `flutter analyze`, mas não rodam de
verdade sem essas permissões declaradas nas plataformas nativas.

Cobre leitura **e** escrita para: Passos, Treinos, Sono, Peso, Pressão
Arterial e Glicose (pacote `health`), mais Câmera (pacote `camera`, usado
pelo fluxo de captura de aparelhos analógicos).

## Android — `android/app/src/main/AndroidManifest.xml`

Health Connect não usa o modelo antigo de `<uses-permission>` normal para
tudo — cada tipo de dado tem sua própria permissão dedicada, mais uma
declaração de `<queries>` exigida pelo Android 11+ para que o app enxergue o
pacote do Health Connect.

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Health Connect: leitura e escrita, um par por tipo de dado -->
    <uses-permission android:name="android.permission.health.READ_STEPS" />
    <uses-permission android:name="android.permission.health.WRITE_STEPS" />
    <uses-permission android:name="android.permission.health.READ_EXERCISE" />
    <uses-permission android:name="android.permission.health.WRITE_EXERCISE" />
    <uses-permission android:name="android.permission.health.READ_SLEEP" />
    <uses-permission android:name="android.permission.health.WRITE_SLEEP" />
    <uses-permission android:name="android.permission.health.READ_WEIGHT" />
    <uses-permission android:name="android.permission.health.WRITE_WEIGHT" />
    <uses-permission android:name="android.permission.health.READ_BLOOD_PRESSURE" />
    <uses-permission android:name="android.permission.health.WRITE_BLOOD_PRESSURE" />
    <uses-permission android:name="android.permission.health.READ_BLOOD_GLUCOSE" />
    <uses-permission android:name="android.permission.health.WRITE_BLOOD_GLUCOSE" />

    <!-- Necessário no Android 11+ para o app conseguir checar/abrir o
         Health Connect (health.isHealthConnectAvailable / installHealthConnect) -->
    <queries>
        <package android:name="com.google.android.apps.healthdata" />
        <intent>
            <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
        </intent>
    </queries>

    <!-- Câmera ao vivo (captura de glicosímetro/pressão/balança) -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />

    <application>
        <!-- Necessário para o Android abrir a tela de permissões do
             Health Connect a partir do app (>= Android 14 usa esta activity-alias
             própria do Health Connect; abaixo disso a rationale acima já cobre). -->
        <activity-alias
            android:name="ViewPermissionUsageActivity"
            android:exported="true"
            android:targetActivity=".MainActivity"
            android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
            <intent-filter>
                <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
                <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
            </intent-filter>
        </activity-alias>
    </application>
</manifest>
```

Também exige `minSdkVersion 26` em `android/app/build.gradle` (Health Connect
não roda abaixo disso) e, se o app precisar funcionar em Android < 14, o
usuário instala o Health Connect via Play Store — use
`Health().installHealthConnect()` para direcionar a esse fluxo quando
`isHealthConnectAvailable()` retornar `false` (já tratado defensivamente em
`health_sync_service.dart`).

## iOS — `ios/Runner/Info.plist`

```xml
<key>NSHealthShareUsageDescription</key>
<string>Usamos seus dados de saúde (passos, treinos, sono, peso, pressão arterial e glicose) para sincronizar automaticamente seu progresso e manter suas métricas clínicas atualizadas.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>Registramos no app Saúde as métricas que você confirma manualmente (ex: foto de um glicosímetro ou balança sem Bluetooth), para manter um histórico único e completo.</string>

<key>NSCameraUsageDescription</key>
<string>A câmera é usada exclusivamente para fotografar o visor de aparelhos físicos (glicosímetro, aparelho de pressão, balança) em tempo real, para extração automática do valor exibido.</string>
```

Além do `Info.plist`, o HealthKit exige a *capability* habilitada no Xcode
(`Signing & Capabilities → + Capability → HealthKit`), o que gera um
entitlements file com:

```xml
<key>com.apple.developer.healthkit</key>
<true/>
<key>com.apple.developer.healthkit.access</key>
<array/>
```

Sem essa capability, `Health().configure()` falha silenciosamente em runtime
mesmo com o `Info.plist` correto — checklist na hora do `flutter create .`:

1. Rodar `flutter create . --platforms=android,ios` para gerar os projetos.
2. Colar os blocos acima nos respectivos arquivos.
3. Habilitar a capability HealthKit no Xcode (passo manual, não é um arquivo de texto).
4. Setar `minSdkVersion 26` no `android/app/build.gradle`.
5. `flutter pub get` (os pacotes `health`/`camera` já estão no `pubspec.yaml`).
