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

// Some plugins (e.g. flutter_plugin_android_lifecycle) require every module that
// depends on them to compile against Android API 36, but older plugins such as
// file_picker still pin compileSdk 34.  Force a consistent compileSdk 36 across
// all Android subprojects so the AAR-metadata check passes.
subprojects {
    // Reflectively call android.compileSdkVersion(36) — avoids needing the
    // Android Gradle Plugin types on the root build script's classpath.
    val pinCompileSdk = fun() {
        val androidExt = extensions.findByName("android") ?: return
        runCatching {
            androidExt.javaClass
                .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(androidExt, 36)
        }
    }
    // :app is force-evaluated early by evaluationDependsOn above, so calling
    // afterEvaluate on it would throw "already evaluated" — configure those now
    // and defer the rest until their own build script has run.
    if (state.executed) pinCompileSdk() else afterEvaluate { pinCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
