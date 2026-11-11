# Flutter Wrapper & Plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Preserve Line Numbers & Attributes for Crashlytics
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Razorpay SDK Proguard Rules
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-keepclasseswithmembers class * {
    public <init>(android.app.Activity, java.lang.String);
}
-keep class com.google.android.gms.auth.api.phone.** { *; }

# Google Play In-App Updates & Review
-keep class com.google.android.play.core.** { *; }
-keep class de.ffuf.in_app_update.** { *; }
-keep class dev.britannio.in_app_review.** { *; }
-dontwarn com.google.android.play.core.**

# Firebase SDKs
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Flutter Local Notifications & Secure Storage
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Location, Geocoding & Permission
-keep class com.baseflow.** { *; }
-keep class com.lyokone.location.** { *; }

# OkHttp, Okio, Dio
-dontwarn okhttp3.**
-dontwarn okio.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase
-dontwarn org.bouncycastle.**

# Play Core & Deferred Components
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn io.flutter.embedding.android.FlutterPlayStoreSplitApplication
