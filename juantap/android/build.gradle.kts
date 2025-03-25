import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory

// ✅ Repositories for plugins and dependencies
allprojects {
    repositories {
        google()
        gradlePluginPortal()
        mavenCentral()
    }
}

// ✅ Firebase / Google Services Plugin
plugins {
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false // ✅ Match existing classpath
    id("com.google.gms.google-services") version "4.4.2" apply false
}

// ✅ Custom build directory structure
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

// ✅ Apply the custom build directory to subprojects
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// ✅ Ensure app module is evaluated before others (optional)
subprojects {
    project.evaluationDependsOn(":app")
}

// ✅ Clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
