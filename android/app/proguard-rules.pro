# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Razorpay SDK Proguard Rules
-keep class com.razorpay.** {*;}
-dontwarn com.razorpay.**
-keepclasseswithmembers class * {
    public <init>(android.app.Activity, java.lang.String);
}
-keep class com.google.android.gms.auth.api.phone.** { *; }

# OkHttp & Dio
-dontwarn okhttp3.**
-dontwarn okio.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# Flutter Riverpod & State
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-dontwarn org.bouncycastle.**

# Play Core & Deferred Components (when not using dynamic features)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication
