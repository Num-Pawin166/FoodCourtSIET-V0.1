import 'package:firebase_core/firebase_core.dart';

/// ค่าเชื่อมต่อ Firebase project "foodcourt-siet" (เดียวกับแอปนักศึกษา)
/// ไม่ใช่รหัสลับ — สิทธิ์อ่าน/เขียนคุมด้วย firestore/firestore.rules
/// TODO: เปลี่ยน appId เป็นของแอปร้านค้าเมื่อลงทะเบียน package th.ac.kmitl.siet.foodcourt_vendor ใน Firebase แล้ว
class DefaultFirebaseOptions {
  static const android = FirebaseOptions(
    apiKey: 'AIzaSyD1njF7un5b4Jzf0FDcczxfrYl7Hjz5-Hs',
    appId: '1:39588856523:android:0629d20fc751561444114e',
    messagingSenderId: '39588856523',
    projectId: 'foodcourt-siet',
    storageBucket: 'foodcourt-siet.firebasestorage.app',
  );
}
