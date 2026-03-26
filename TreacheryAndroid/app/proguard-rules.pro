# Keep kotlinx serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

-keep,includedescriptorclasses class com.solomon.treachery.**$$serializer { *; }
-keepclassmembers class com.solomon.treachery.** {
    *** Companion;
}
-keepclasseswithmembers class com.solomon.treachery.** {
    kotlinx.serialization.KSerializer serializer(...);
}
