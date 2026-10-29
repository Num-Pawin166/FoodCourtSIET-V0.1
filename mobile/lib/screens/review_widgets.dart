import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../reviews.dart';
import '../theme.dart';
import '../widgets.dart';

/// ดาว 1–5 (กดได้เมื่อมี onChanged)
class Stars extends StatelessWidget {
  final int rating;
  final double size;
  final ValueChanged<int>? onChanged;
  const Stars({super.key, required this.rating, this.size = 16, this.onChanged});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++)
          onChanged == null
              ? Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: AppColors.amber)
              : IconButton(
                  tooltip: '$i ดาว',
                  onPressed: () => onChanged!(i),
                  icon: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: AppColors.amber),
                ),
      ]);
}

/// ส่วน "รีวิวจากลูกค้า" ในหน้าร้าน — อัปเดตทันทีเมื่อมีคนรีวิวใหม่ (Firestore snapshots)
class ShopReviews extends StatelessWidget {
  final int shopId;
  const ShopReviews({super.key, required this.shopId});

  @override
  Widget build(BuildContext context) {
    final service = context.read<AppState>().reviews!;
    return StreamBuilder<List<Review>>(
      stream: service.watchShop(shopId),
      builder: (context, snap) {
        Widget body;
        if (snap.hasError) {
          body = const Text('โหลดรีวิวไม่ได้ในขณะนี้', style: TextStyle(fontSize: 12, color: AppColors.muted));
        } else if (!snap.hasData) {
          body = const LinearProgressIndicator(color: AppColors.pink);
        } else if (snap.data!.isEmpty) {
          body = const Text('ยังไม่มีรีวิว รับอาหารแล้วรีวิวได้ที่หน้าประวัติ', style: TextStyle(fontSize: 12, color: AppColors.muted));
        } else {
          final list = snap.data!;
          body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(ReviewService.average(list).toStringAsFixed(1), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Stars(rating: ReviewService.average(list).round()),
              const SizedBox(width: 6),
              Expanded(child: Text('(${list.length} รีวิว)', style: const TextStyle(fontSize: 12, color: AppColors.ink2))),
              if (list.length > 2) TextButton(onPressed: () => _showAll(context, list), child: const Text('ดูทั้งหมด')),
            ]),
            for (final r in list.take(2)) ReviewTile(review: r),
          ]);
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('รีวิวจากลูกค้า', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            body,
          ]),
        );
      },
    );
  }

  void _showAll(BuildContext context, List<Review> list) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('รีวิวทั้งหมด (${list.length})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              for (final r in list) ReviewTile(review: r),
            ],
          ),
        ),
      );
}

class ReviewTile extends StatelessWidget {
  final Review review;
  const ReviewTile({super.key, required this.review});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Stars(rating: review.rating, size: 14),
            const SizedBox(width: 8),
            Expanded(child: Text(review.authorName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            if (review.updatedAt != null) Text(thaiDateTime(review.updatedAt!), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ]),
          if (review.comment.isNotEmpty) Text(review.comment, style: const TextStyle(fontSize: 13, color: AppColors.ink2)),
        ]),
      );
}

/// ปุ่มบนการ์ดประวัติ: ยังไม่รีวิว → "ให้คะแนนร้าน" / รีวิวแล้ว → แสดงดาว แตะเพื่อแก้
class OrderReviewButton extends StatelessWidget {
  final Order order;
  const OrderReviewButton({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final service = context.read<AppState>().reviews!;
    return StreamBuilder<Review?>(
      stream: service.watchOrder(order.id),
      builder: (context, snap) {
        if (snap.hasError || snap.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
        final mine = snap.data;
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => showReviewSheet(context, order, existing: mine),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: mine == null
                  ? const Row(children: [
                      Icon(Icons.star_outline_rounded, size: 18, color: AppColors.amber),
                      SizedBox(width: 4),
                      Text('ให้คะแนนร้าน', style: TextStyle(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w600)),
                    ])
                  : Row(children: [
                      Stars(rating: mine.rating, size: 16),
                      const SizedBox(width: 6),
                      const Text('รีวิวแล้ว · แตะเพื่อแก้', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    ]),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showReviewSheet(BuildContext context, Order order, {Review? existing}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReviewSheet(order: order, existing: existing, page: context),
    );

class _ReviewSheet extends StatefulWidget {
  final Order order;
  final Review? existing;
  final BuildContext page; // ไว้แสดง SnackBar บนหน้าหลังจากปิด sheet แล้ว
  const _ReviewSheet({required this.order, this.existing, required this.page});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late int _rating = widget.existing?.rating ?? 0;
  late final _comment = TextEditingController(text: widget.existing?.comment ?? '');
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final state = context.read<AppState>();
    final page = widget.page;
    setState(() => _sending = true);
    try {
      await state.reviews!.submit(order: widget.order, rating: _rating, comment: _comment.text, authorName: state.user!.name);
      if (mounted) Navigator.pop(context);
      if (page.mounted) showMsg(page, 'ขอบคุณสำหรับรีวิว!');
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      if (page.mounted) showMsg(page, e, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('รีวิว ${widget.order.shopName}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          Text('ออเดอร์ ${widget.order.queueNo}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 8),
          Center(child: Stars(rating: _rating, size: 34, onChanged: (v) => setState(() => _rating = v))),
          const SizedBox(height: 8),
          TextField(
            controller: _comment,
            maxLength: ReviewService.maxComment,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'เล่าให้เพื่อนฟังหน่อย (ไม่บังคับ)'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: _rating == 0 || _sending ? null : _send,
              child: Text(_sending ? 'กำลังส่ง...' : widget.existing == null ? 'ส่งรีวิว' : 'บันทึกการแก้ไข'),
            ),
          ),
        ]),
      );
}

