allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Correção pontual: file_picker 11.0.2 detecta AGP >= 9 (é o caso deste
// projeto) e, quando detecta, deliberadamente NÃO aplica seu próprio Kotlin
// Gradle Plugin — o autor do pacote já escreveu esse `if` esperando que o
// Built-in Kotlin do AGP compile o Kotlin dele. Só que `android.builtInKotlin`
// PERMANECE `false` neste projeto (gradle.properties) porque device_info_plus,
// health e workmanager_android ainda aplicam o KGP antigo incondicionalmente,
// e o AGP 9 recusa esses três terminantemente quando essa flag está ligada
// ("the 'org.jetbrains.kotlin.android' plugin is no longer required... since
// AGP 9.0"). Resultado sem este bloco: NENHUM dos dois caminhos compila o
// Kotlin do file_picker — nem o built-in (desligado), nem o próprio plugin
// (ele mesmo se absteve) — e `FilePickerPlugin` nunca existe, quebrando
// GeneratedPluginRegistrant.java com "cannot find symbol".
//
// Este bloco aplica o Kotlin Android Plugin SÓ no subprojeto `file_picker`,
// de fora, sem editar o pacote (edição em pub cache seria apagada no
// próximo `flutter pub get`/`pub cache repair`) e sem religar a flag global
// (que quebraria os outros três). Versão do KGP usada: a já declarada em
// settings.gradle.kts (`org.jetbrains.kotlin.android` 2.3.20) — nenhuma
// versão nova é introduzida.
//
// DÍVIDA TÉCNICA (não corrigir agora — ver RELATÓRIO DE FIM DE TAREFA):
// este bloco todo deixa de ser necessário no dia em que file_picker,
// device_info_plus, health e workmanager_android migrarem para Built-in
// Kotlin (ou pelo menos file_picker ganhar uma versão que não dependa dessa
// flag) — nesse ponto, ligar `android.builtInKotlin=true` E remover este
// bloco é o caminho correto.
subprojects {
    if (project.name == "file_picker") {
        project.pluginManager.apply("org.jetbrains.kotlin.android")
        // Mesmo alvo de bytecode que o próprio build.gradle do file_picker já
        // usa para Java (VERSION_17) — evita "Inconsistent JVM target
        // compatibility" entre a task compileDebugKotlin (injetada aqui) e
        // compileDebugJavaWithJavac. Configurado via tasks.withType (mesmo
        // padrão que workmanager_android já usa no próprio build.gradle) em
        // vez da extensão `kotlinOptions` do AGP — que exige um import que
        // não resolve neste ponto do script raiz.
        project.tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
