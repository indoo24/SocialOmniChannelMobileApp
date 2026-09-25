# R8/ProGuard rules for release builds.
#
# Two jobs: keep the handful of Android-side classes that are reached from
# outside the bytecode graph — over JNI, or by name from a string — and strip
# logging that would otherwise survive into a shipped binary.
#
# Everything else is deliberately left for R8 to shrink, optimise and rename.
# A `-keep class some.package.** { *; }` is not a safety measure: it pins the
# whole package's members against every pass R8 has, and R8 cannot tell an
# over-broad rule from a necessary one. The rules below are therefore scoped to
# the exact classes and members that something outside the graph names.
#
# Rules deliberately NOT written here, because the build already supplies them:
#
#   * Manifest components (MainActivity, FlutterFirebaseMessagingService,
#     FlutterFirebaseMessagingReceiver, FirebaseMessagingService, the init
#     providers...). AGP generates `-keep class <name> { <init>(); }` for every
#     `android:name` in the merged manifest — see
#     build/app/intermediates/aapt_proguard_file/.../aapt_rules.txt. That is
#     strictly better than a hand-written keep: it pins the constructor the
#     framework calls and lets R8 optimise the rest of the class.
#   * FlutterPlugin implementations. flutter_tools ships
#     flutter_proguard_rules.pro, which keeps them `allowshrinking,
#     allowobfuscation` — intentionally still optimisable.
#   * Firebase/Play-services internals. Their AARs ship consumer rules
#     (SafeParcelable CREATORs, @KeepName, DynamiteApi, the -dontwarns).
#   * Tink's shaded-protobuf reflection. tink-android ships its own
#     `-keepclassmembers ... GeneratedMessageLite { <fields>; }`.

# --- Flutter engine: the JNI boundary ---------------------------------------
# The engine's native half calls into Java over JNI, which resolves classes,
# methods and fields by name at runtime — invisible to R8's call graph.
#
# Flutter marks exactly that surface with @Keep (17 classes in the release
# embedding, FlutterJNI being the only one declaring `native` methods), so the
# annotation is the precise boundary. Keeping @Keep-annotated types rather than
# all of `io.flutter.**` leaves the other ~420 embedding classes optimisable.
#
# This must be stated here rather than inherited: the embedding jar ships no
# consumer rules, and the only other rule honouring @Keep comes from
# play-services-basement — i.e. it would silently disappear with Firebase.
-keep,allowshrinking class io.flutter.** { @androidx.annotation.Keep *; }
-keep @androidx.annotation.Keep class io.flutter.** { *; }

# Returned by FlutterJNI.nativeLookupCallbackInformation and populated field by
# field from native code, so nothing in bytecode ever writes these fields and
# R8 would otherwise consider them dead. This is the lookup that resolves a
# Dart `@pragma('vm:entry-point')` handle — the FCM background message handler
# in lib/core/notifications/push_service.dart runs through it.
-keepclassmembers class io.flutter.view.FlutterCallbackInformation {
    <fields>;
    private <init>(...);
}

# --- Firebase component discovery -------------------------------------------
# ComponentDiscovery reads registrar class names out of <meta-data> *values* in
# the merged manifest and instantiates them with Class.forName(...).newInstance.
# AGP's generated rules cover `android:name` components but not class names
# that appear as meta-data values, so this is a genuine gap.
#
# Scoped to the no-arg constructor, which is the only member discovery invokes
# (getComponents() is then called through the interface, so it is reachable
# normally). R8 keeps these classes' *names* too, which is required: the names
# live in manifest meta-data strings that nothing rewrites. Their bodies stay
# optimisable, and this pins ~10 registrars rather than all of com.google.firebase.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}

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
