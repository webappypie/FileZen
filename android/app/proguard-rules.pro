# FileZen ProGuard / R8 Configuration Rules

# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn com.google.android.play.core.**

# Drift / SQLite Native Libs
-keep class com.simonoid.sqlite3.** { *; }
-keep class org.sqlite.** { *; }
-keep class sqlite3.** { *; }
-dontwarn com.simonoid.sqlite3.**

# ML Kit text recognition: optional non-Latin script modules are not bundled
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Gson / JSON Models
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**

# PDF and Media Libraries
-keep class com.shockwave.** { *; }
-dontwarn com.shockwave.**

# Native JNI Methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Android Architecture Components
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
