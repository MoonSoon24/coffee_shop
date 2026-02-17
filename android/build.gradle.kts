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


subprojects {
    plugins.withId("com.android.library") {
        val androidExt = extensions.findByName("android") ?: return@withId

        val currentNamespace = runCatching {
            androidExt.javaClass.getMethod("getNamespace").invoke(androidExt) as String?
        }.getOrNull()

        if (!currentNamespace.isNullOrBlank()) {
            return@withId
        }

        val manifestFile = file("src/main/AndroidManifest.xml")
        if (!manifestFile.exists()) {
            return@withId
        }

        val pkgName = Regex("package=\"([^\"]+)\"")
            .find(manifestFile.readText())
            ?.groupValues
            ?.getOrNull(1)
            ?.trim()

        if (pkgName.isNullOrBlank()) {
            return@withId
        }

        runCatching {
            androidExt.javaClass
                .getMethod("setNamespace", String::class.java)
                .invoke(androidExt, pkgName)
        }
    }
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}