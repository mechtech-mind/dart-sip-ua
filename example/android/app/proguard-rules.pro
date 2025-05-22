# Suppress warnings for missing classes (from R8 error log)
-dontwarn java.beans.ConstructorProperties
-dontwarn java.beans.Transient
-dontwarn org.conscrypt.Conscrypt
-dontwarn org.conscrypt.OpenSSLProvider
-dontwarn org.w3c.dom.bootstrap.DOMImplementationRegistry

# Recommended keep rules for Jackson (if used)
-keep class com.fasterxml.jackson.** { *; }
-keepclassmembers class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.databind.ext.**

# Recommended keep rules for OkHttp/Conscrypt (if used)
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn org.conscrypt.**
-keep class org.conscrypt.** { *; } 