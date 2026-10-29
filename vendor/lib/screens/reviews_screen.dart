import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../reviews.dart';
import '../theme.dart';
import '../widgets.dart';

/// แท็บ "รีวิว": คะแนนเฉลี่ย สัดส่วนดาว และรีวิวทั้งหมดของร้านตัวเอง (อัปเดตทันทีเมื่อมีรีวิวใหม่)
class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  Stream<List<Review>>? _stream;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (state.reviews == null) return;
    try {
      final shop = await state.api.shop();
      if (mounted) setState(() { _stream = state.reviews!.watchShop(shop.id); _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<AppState>().reviews;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const PageHeader('รีวิวร้าน'),
      Expanded(child: _body(feed)),
    ]);
  }

  Widget _body(ReviewFeed? feed) {
    if (feed == null) {
      return EmptyState(
        icon: Icons.cloud_off,
        text: ReviewFeed.initError != null ? 'ระบบรีวิวใช้งานไม่ได้: ${ReviewFeed.initError}' : 'ดูรีวิวได้ในแอป Android',
      );
    }
    if (_error != null) return EmptyState(icon: Icons.wifi_off, text: _error!, action: TextButton(onPressed: _load, child: const Text('ลองใหม่')));
    if (_stream == null) return const Center(child: CircularProgressIndicator(color: AppColors.pink));
    return StreamBuilder<List<Review>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return const EmptyState(icon: Icons.cloud_off, text: 'โหลดรีวิวไม่ได้ในขณะนี้');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.pink));
        final list = snap.data!;
        if (list.isEmpty) {
          return const EmptyState(icon: Icons.star_outline_rounded, text: 'ยังไม่มีรีวิว\nลูกค้ารีวิวได้หลังรับอาหารแล้ว');
        }
        return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
          _Summary(list: list),
          const SizedBox(height: 16),
          Text('รีวิวทั้งหมด (${list.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          for (final r in list) _ReviewCard(review: r),
        ]);
      },
    );
  }
}

class Stars extends StatelessWidget {
  final int rating;
  final double size;
  const Stars({super.key, required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: AppColors.amber),
      ]);
}

/// คะแนนเฉลี่ย + แถบสัดส่วน 5→1 ดาว
class _Summary extends StatelessWidget {
  final List<Review> list;
  const _Summary({required this.list});

  @override
  Widget build(BuildContext context) {
    final avg = ReviewFeed.average(list);
    final dist = ReviewFeed.distribution(list);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Row(children: [
        Column(children: [
          Text(avg.toStringAsFixed(1), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, height: 1.1)),
          Stars(rating: avg.round(), size: 18),
          const SizedBox(height: 4),
          Text('${list.length} รีวิว', style: const TextStyle(fontSize: 12, color: AppColors.ink2)),
        ]),
        const SizedBox(width: 20),
        Expanded(
          child: Column(children: [
            for (var star = 5; star >= 1; star--)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(width: 14, child: Text('$star', style: const TextStyle(fontSize: 12))),
                  const Icon(Icons.star_rounded, size: 14, color: AppColors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: dist[star - 1] / list.length,
                        minHeight: 8,
                        color: AppColors.amber,
                        backgroundColor: AppColors.pinkSofter,
                      ),
                    ),
                  ),
                  SizedBox(width: 28, child: Text('${dist[star - 1]}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: AppColors.ink2))),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Review review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: cardDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Stars(rating: review.rating, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(review.authorName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            if (review.updatedAt != null) Text(thaiDateTime(review.updatedAt!), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ]),
          if (review.comment.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(review.comment, style: const TextStyle(fontSize: 13, color: AppColors.ink2))),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('ออเดอร์ #${review.orderId}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ),
        ]),
      );
}
