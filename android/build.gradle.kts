import java.util.Properties

val localProperties = Properties().apply {
    file("local.properties").inputStream().use(::load)
}
val flutterSdkPath =
    localProperties.getProperty("flutter.sdk")
        ?: error("flutter.sdk is not set in local.properties")
val flutterEngineVersion = file("$flutterSdkPath/bin/internal/engine.version").readText().trim()

group = "com.manukj.edge_gen_ai"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.2.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

val agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt()

if (agpMajor < 9) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

android {
    namespace = "com.manukj.edge_gen_ai"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        // ML Kit GenAI Prompt API requires API 26+.
        minSdk = 26
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

project.extensions.configure(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java) {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    compileOnly("io.flutter:flutter_embedding_release:1.0.0-$flutterEngineVersion")
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta2")
    implementation("com.google.mlkit:genai-summarization:1.0.0-beta1")
    implementation("com.google.mlkit:genai-proofreading:1.0.0-beta1")
    implementation("com.google.mlkit:genai-rewriting:1.0.0-beta1")
    implementation("com.google.mlkit:genai-image-description:1.0.0-beta1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // For awaiting the ListenableFutures returned by the task-specific
    // ML Kit GenAI clients (checkFeatureStatus/runInference).
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-guava:1.8.1")

    testImplementation("io.flutter:flutter_embedding_release:1.0.0-$flutterEngineVersion")
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
    // The android.jar used by JVM unit tests only stubs org.json, so pull in
    // the real implementation for ToolPromptingTest.
    testImplementation("org.json:json:20240303")
}