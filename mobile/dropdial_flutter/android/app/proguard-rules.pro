# Suppress optional ML Kit language recognition scripts not included in Latin bundle
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep Flutter and native service classes
-keep class com.dropdial.dropdial_flutter.** { *; }
-keep class com.google.mlkit.vision.text.** { *; }

