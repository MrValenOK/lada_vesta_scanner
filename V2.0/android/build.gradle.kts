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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

fun Project.raiseCompileSdkIfNeeded() {
    val androidExt = extensions.findByName("android") ?: return
    androidExt.withGroovyBuilder {
        val raw = runCatching { getProperty("compileSdkVersion") }.getOrNull()
        val level = when (raw) {
            is Int -> raw
            is String -> raw.filter { it.isDigit() }.toIntOrNull() ?: 0
            else -> 0
        }
        if (level in 1..33) {
            runCatching { setProperty("compileSdk", 36) }
            runCatching { invokeMethod("compileSdkVersion", 36) }
            println("[VSPro] compileSdk поднят до 36 у $name (был: $raw)")
        }
    }
}

// Плагин flutter_bluetooth_classic_serial объявляет устаревший compileSdk (33),
// а его AndroidX-зависимости требуют >= 34 — поднимаем compileSdk субпроектов до 36.
// afterEvaluate — корректный тайминг; fallback — для проекта, оценённого до этого блока
// (в этом Gradle :app оценивается рано из-за evaluationDependsOn в шаблоне).
subprojects {
    try {
        afterEvaluate { raiseCompileSdkIfNeeded() }
    } catch (_: Exception) {
        raiseCompileSdkIfNeeded()
    }
}
