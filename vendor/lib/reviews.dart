import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';

/// รีวิวที่นักศึกษาให้ร้าน (เขียนจากแอปนักศึกษา เก็บบน Cloud Firestore collection "reviews")
class Review {
  final String id;
  final int shopId;
  final int orderId;
  final int rating; // 1–5
  final String comment;
  final String authorName;
  final DateTime? updatedAt;

  Review({required this.id, required this.shopId, required this.orderId, required this.rating, required this.comment,
      required this.authorName, this.updatedAt});

  factory Review.fromDoc(String id, Map<String, dynamic> d) => Review(
        id: id, shopId: d['shopId'], orderId: d['orderId'], rating: d['rating'], comment: d['comment'] ?? '',
        authorName: d['authorName'] ?? '', updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      );
}

/// ร้านค้าอ่านรีวิวของร้านตัวเองแบบ real-time (อ่านอย่างเดียว — security rules ไม่ให้แก้/ลบ)
class ReviewFeed {
  final FirebaseFirestore db;
  /// ล็อกอิน Firebase แบบ anonymous (rules ให้อ่านได้เฉพาะผู้ที่ล็อกอินแล้ว)
  final Future<String> Function() signIn;

  ReviewFeed(this.db, {required this.signIn});

  /// สาเหตุที่เปิด Firebase ไม่ได้ (บน Android) — หน้ารีวิวแสดงให้เห็นแทนการซ่อนเงียบๆ
  static Object? initError;

  /// เปิดใช้บน Android เท่านั้น
  static Future<ReviewFeed?> init() async {
    initError = null;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
      final auth = FirebaseAuth.instance;
      return ReviewFeed(FirebaseFirestore.instance,
          signIn: () async => (auth.currentUser ?? (await auth.signInAnonymously()).user!).uid);
    } catch (e) {
      debugPrint('firebase init failed: $e');
      initError = e;
      return null;
    }
  }

  /// รีวิวของร้าน ใหม่สุดก่อน
  Stream<List<Review>> watchShop(int shopId) => Stream.fromFuture(signIn()).asyncExpand((_) => db
      .collection('reviews')
      .where('shopId', isEqualTo: shopId)
      .limit(200)
      .snapshots()
      .map((s) => [for (final d in s.docs) Review.fromDoc(d.id, d.data())]
        ..sort((a, b) => (b.updatedAt ?? DateTime(9999)).compareTo(a.updatedAt ?? DateTime(9999)))));

  static double average(List<Review> reviews) =>
      reviews.isEmpty ? 0 : reviews.fold<int>(0, (s, r) => s + r.rating) / reviews.length;

  /// จำนวนรีวิวแยกตามดาว: index 0 = 1 ดาว ... index 4 = 5 ดาว
  static List<int> distribution(List<Review> reviews) {
    final counts = List.filled(5, 0);
    for (final r in reviews) {
      if (r.rating >= 1 && r.rating <= 5) counts[r.rating - 1]++;
    }
    return counts;
  }
}
