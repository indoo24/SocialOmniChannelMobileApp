# R8/ProGuard rules for release builds.
#
# Two jobs: keep the Android-side classes Flutter and its plugins reach
# reflectively, and strip logging that would otherwise survive into a shipped
# binary.

# --- Flutter engine and embedding -------------------------------------------
# Reached via JNI and reflection; R8 cannot see those references.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- Firebase / FCM ---------------------------------------------------------
# Message payloads and the background handler entry point are instantiated
# reflectively by the Play Services runtime.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# --- flutter_secure_storage -------------------------------------------------
# Backed by androidx.security's EncryptedSharedPreferences, whose key handling
# uses reflection over Tink primitives.
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# --- MainActivity -----------------------------------------------------------
# Named as a string in AndroidManifest.xml, so nothing in bytecode refers to it.
-keep class com.scenario.scenario_mobile.MainActivity { *; }

# --- Strip Android logging from release builds -------------------------------
# The Dart side is gated by AppLog/kDebugMode; this covers the native half —
# plugin logging that would otherwise write to logcat on an agent's phone.
# -assumenosideeffects lets R8 delete the calls entirely rather than leave them
# unreachable, so the log strings are removed from the binary too.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
