group = "dk.stepnetwork.webadview_flutter"
version = "0.1.1"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
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

android {
    namespace = "dk.stepnetwork.webadview_flutter"

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
        // Flutter's default; above Didomi's 21. Gives shouldOverrideUrlLoading(WebResourceRequest)
        // and (from 26) onRenderProcessGone without compat shims.
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            // The core is pure Kotlin (own Rect, injectable logger/clock) and
            // uses the real org.json on the test classpath, so android.jar's
            // "Stub!" methods are never hit. Return-default keeps accidental
            // android.* calls from throwing.
            isReturnDefaultValues = true
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Same artifact the didomi_sdk Flutter plugin pins → Gradle resolves ONE Didomi.
    implementation("io.didomi.sdk:android:2.49.1")
    // Document-start scripts + origin-restricted WebMessageListener.
    implementation("androidx.webkit:webkit:1.17.0")
    implementation("androidx.annotation:annotation:1.9.1")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.4")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testImplementation("org.json:json:20250107")
}
