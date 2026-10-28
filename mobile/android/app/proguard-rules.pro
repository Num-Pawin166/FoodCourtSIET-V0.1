# shared_preferences_android 2.5+ ถูกเรียกจาก Dart ผ่าน JNI (jnigen) ด้วยชื่อเมธอดตรงๆ
# R8 มองไม่เห็นการเรียกนี้ จึงลบ/เปลี่ยนชื่อเมธอดทิ้ง → แอป release ค้างตอนเปิด (NoSuchMethodError)
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
# เมธอดข้างบนเป็น suspend fun: signature ที่ JNI ค้นหามี kotlin.coroutines.Continuation
# ถ้า R8 เปลี่ยนชื่อ Continuation (เช่นเป็น t3/c) JNI จะหาเมธอดไม่เจอ
-keep class kotlin.coroutines.** { *; }
