
# Preserve WorkManager and Room database classes required by AdMob
-keep class androidx.work.impl.** { *; }
-keep class androidx.room.MultiInstanceInvalidationService { *; }
-dontwarn androidx.work.impl.**
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.background.systemjob.SystemJobService { *; }

# Preserve App Startup components
-keep class androidx.startup.** { *; }
-keep class androidx.startup.InitializationProvider
-keep class * implements androidx.startup.Initializer
-keep class com.ptrjrs.worshippads.MainActivity { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }

# Google Mobile Ads SDK
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**