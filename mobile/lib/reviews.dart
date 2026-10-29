import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';
import 'models.dart';

/// รีวิวร้านจากนักศึกษา เก็บบน Cloud Firestore (collection "reviews")
/// ต่างจากฐานข้อมูลในเครื่อง (local_db.dart) ตรงที่ทุกคนเห็นข้อมูลชุดเดียวกันแบบ real-time
class Review {
  final String id;
  final int shopId;
  final int orderId;
  final int rating; // 1–5
  final String comment;
  final String authorName;
  final String authorUid;
  final DateTime? updatedAt; // null ระหว่างรอเวลาจากเซิร์ฟเวอร์

  Review({required this.id, required this.shopId, required this.orderId, required this.rating, required this.comment,
      required this.authorName, required this.authorUid, this.updatedAt});

  factory Review.fromDoc(String id, Map<String, dynamic> d) => Review(
        id: id, shopId: d['shopId'], orderId: d['orderId'], rating: d['rating'], comment: d['comment'] ?? '',
        authorName: d['authorName'] ?? '', authorUid: d['authorUid'] ?? '',
        updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      );
}

class ReviewService {
  static const maxComment = 300;

  final FirebaseFirestore db;
  /// คืน uid ของผู้ใช้ Firebase Auth (ล็อกอินแบบ anonymous ให้ถ้ายังไม่มี) — rules ใช้ uid นี้ยืนยันเจ้าของรีวิว
  final Future<String> Function() signIn;

  ReviewService(this.db, {required this.signIn});

  /// เปิดใช้บน Android เท่านั้น (เว็บ/แพลตฟอร์มอื่นไม่มีค่าเชื่อมต่อ → ซ่อนส่วนรีวิว)
  static Future<ReviewService?> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
      final auth = FirebaseAuth.instance;
      return ReviewService(FirebaseFirestore.instance,
          signIn: () async => (auth.currentUser ?? (await auth.signInAnonymously()).user!).uid);
    } catch (e) {
      debugPrint('firebase init failed: $e');
      return null;
    }
  }

  CollectionReference<Map<String, dynamic>> get _col => db.collection('reviews');

  /// หนึ่งออเดอร์รีวิวได้ครั้งเดียว (ส่งซ้ำ = แก้รีวิวเดิม)
  static String docId(int orderId) => 'order_$orderId';

  /// รีวิวของร้าน ใหม่สุดก่อน (เรียงในแอป เลี่ยงการต้องสร้าง composite index)
  Stream<List<Review>> watchShop(int shopId) => Stream.fromFuture(signIn()).asyncExpand((_) => _col
      .where('shopId', isEqualTo: shopId)
      .limit(100)
      .snapshots()
      .map((s) => [for (final d in s.docs) Review.fromDoc(d.id, d.data())]
        ..sort((a, b) => (b.updatedAt ?? DateTime(9999)).compareTo(a.updatedAt ?? DateTime(9999)))));

  Stream<Review?> watchOrder(int orderId) => Stream.fromFuture(signIn()).asyncExpand((_) => _col
      .doc(docId(orderId))
      .snapshots()
      .map((d) => d.exists ? Review.fromDoc(d.id, d.data()!) : null));

  Future<void> submit({required Order order, required int rating, required String comment, required String authorName}) async {
    if (rating < 1 || rating > 5) throw ArgumentError('ให้คะแนน 1–5 ดาว');
    if (order.status != 'completed') throw StateError('รีวิวได้หลังรับอาหารแล้วเท่านั้น');
    final text = comment.trim();
    if (text.length > maxComment) throw ArgumentError('ความคิดเห็นยาวเกิน $maxComment ตัวอักษร');
    final uid = await signIn();
    await _col.doc(docId(order.id)).set({
      'shopId': order.shopId,
      'orderId': order.id,
      'rating': rating,
      'comment': text,
      'authorName': shortName(authorName),
      'authorUid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static double average(List<Review> reviews) =>
      reviews.isEmpty ? 0 : reviews.fold<int>(0, (s, r) => s + r.rating) / reviews.length;

  /// แสดงชื่อแบบย่อเพื่อความเป็นส่วนตัว: "สมชาย ใจดี" → "สมชาย ใ."
  static String shortName(String full) {
    final parts = full.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'นักศึกษา';
    final first = parts.first.length > 40 ? parts.first.substring(0, 40) : parts.first;
    return parts.length == 1 ? first : '$first ${String.fromCharCode(parts[1].runes.first)}.';
  }
}
