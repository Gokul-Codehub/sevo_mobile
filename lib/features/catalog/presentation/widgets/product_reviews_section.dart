import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../core/errors/error_manager.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/utils/date_utils.dart';
import '../../../feedback/presentation/widgets/review_photo_picker.dart';
import '../../data/product_reviews_repository.dart';

const _star = Color(0xFFF5A623);

class _Stars extends StatelessWidget {
  const _Stars(this.value);
  final double value;
  static const double size = 14;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 1; i <= 5; i++) Icon(value >= i ? Icons.star_rounded : (value >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded), size: size, color: _star),
      ]);
}

/// Ratings & reviews for a Seller Hub product: the summary, what customers wrote (with photos), and - for a customer
/// who received the product - writing, editing or deleting their own review. [productId] is the real Seller Hub id.
class ProductReviewsSection extends ConsumerWidget {
  const ProductReviewsSection({super.key, required this.productId});
  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(productReviewsProvider(productId)).valueOrNull;
    final eligibility = ref.watch(reviewEligibilityProvider(productId)).valueOrNull;
    final summary = page?.summary ?? const ReviewSummary();
    final results = page?.results ?? const <ProductReview>[];
    // Nothing to show and nothing the customer could do: keep the product page clean.
    if (summary.count == 0 && results.isEmpty && !(eligibility?.canWrite ?? false)) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Ratings & reviews', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      const SizedBox(height: 12),
      if (summary.count > 0) _Summary(summary),
      if (eligibility != null) _WriteButton(eligibility: eligibility, onWrite: () => _openForm(context, ref)),
      for (final r in results) _ReviewTile(review: r, onEdit: r.isMine ? () => _openForm(context, ref, existing: r) : null),
    ]);
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref, {ProductReview? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReviewFormSheet(productId: productId, existing: existing),
    );
    if (saved == true) {
      ref.invalidate(productReviewsProvider(productId));
      ref.invalidate(reviewEligibilityProvider(productId));
    }
  }
}

class _Summary extends StatelessWidget {
  const _Summary(this.s);
  final ReviewSummary s;

  @override
  Widget build(BuildContext context) {
    final total = s.count == 0 ? 1 : s.count;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Column(children: [
          Text(s.average.toStringAsFixed(1), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.navy)),
          _Stars(s.average),
          const SizedBox(height: 2),
          Text('${s.count} ${s.count == 1 ? 'review' : 'reviews'}', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        ]),
        const SizedBox(width: 20),
        Expanded(
          child: Column(children: [
            for (var star = 5; star >= 1; star--)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Text('$star', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  const Icon(Icons.star_rounded, size: 11, color: _star),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: (s.distribution[star] ?? 0) / total, minHeight: 6, backgroundColor: const Color(0xFFE8ECF1), valueColor: const AlwaysStoppedAnimation(_star)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(width: 22, child: Text('${s.distribution[star] ?? 0}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _WriteButton extends StatelessWidget {
  const _WriteButton({required this.eligibility, required this.onWrite});
  final ReviewEligibility eligibility;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    if (eligibility.existing != null) return const SizedBox.shrink(); // their own review is in the list, with Edit
    if (!eligibility.eligible) {
      // Only worth saying when there is already something to read; an empty section is hidden anyway.
      return Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(eligibility.explanation, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: onWrite,
        icon: const Icon(Icons.rate_review_outlined, size: 18),
        label: const Text('Write a review'),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review, this.onEdit});
  final ProductReview review;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: review.isMine ? AppColors.navy.withValues(alpha: 0.4) : const Color(0xFFE8ECF1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Stars(review.rating.toDouble()),
            const SizedBox(width: 8),
            Expanded(child: Text(review.isMine ? 'You' : (review.reviewerName.isEmpty ? 'Customer' : review.reviewerName), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
            if (onEdit != null) TextButton(onPressed: onEdit, style: TextButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 8)), child: const Text('Edit')),
          ]),
          if (review.headline.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(review.headline, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
          if (review.comment.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(review.comment, style: const TextStyle(fontSize: 13, height: 1.4))),
          if (review.photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final url in review.photos)
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 64, height: 64, color: const Color(0xFFF1F5F9)))),
              ]),
            ),
          if (review.createdAt != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(formatDmy(review.createdAt!), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
        ]),
      );
}

/// Write or edit a review: stars (required), headline, comment and up to three photos.
class ReviewFormSheet extends ConsumerStatefulWidget {
  const ReviewFormSheet({super.key, required this.productId, this.existing, this.pickPhoto});
  final int productId;
  final ProductReview? existing;

  /// Test seam for the photo picker.
  final Future<XFile?> Function(ImageSource source)? pickPhoto;

  @override
  ConsumerState<ReviewFormSheet> createState() => _ReviewFormSheetState();
}

class _ReviewFormSheetState extends ConsumerState<ReviewFormSheet> {
  late int _rating = widget.existing?.rating ?? 0;
  late final _headline = TextEditingController(text: widget.existing?.headline ?? '');
  late final _comment = TextEditingController(text: widget.existing?.comment ?? '');
  final List<XFile> _photos = [];
  late final List<String> _keptUrls = [...?widget.existing?.photos];
  bool _busy = false;

  @override
  void dispose() {
    _headline.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      AppToast.show(context, 'Please choose a star rating.', type: AppToastType.error);
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(productReviewsRepositoryProvider);
    final urls = [..._keptUrls];
    for (final photo in _photos) {
      final up = await repo.uploadPhoto(widget.productId, photo);
      if (up case Success(:final data)) {
        urls.add(data);
      } else if (up case Failure(:final error)) {
        if (!mounted) return;
        setState(() => _busy = false);
        AppToast.show(context, ErrorManager.present(error).body, type: AppToastType.error);
        return;
      }
    }
    final r = await repo.submit(widget.productId, rating: _rating, headline: _headline.text, comment: _comment.text, photoUrls: urls, update: widget.existing != null);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case Success():
        AppToast.show(context, widget.existing != null ? 'Review updated.' : 'Thank you! Your review will appear once it is approved.', type: AppToastType.success);
        Navigator.of(context).pop(true);
      case Failure(:final error):
        AppToast.show(context, ErrorManager.present(error).body, type: AppToastType.error);
    }
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your review?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    final r = await ref.read(productReviewsRepositoryProvider).deleteMine(widget.productId);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case Success():
        Navigator.of(context).pop(true);
      case Failure(:final error):
        AppToast.show(context, ErrorManager.present(error).body, type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = 3 - _keptUrls.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.existing != null ? 'Edit your review' : 'Rate this product', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 12),
          Row(children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                key: ValueKey('star-$i'),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _rating = i),
                icon: Icon(i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: _star, size: 34),
              ),
          ]),
          TextField(controller: _headline, maxLength: 80, decoration: const InputDecoration(labelText: 'Headline (optional)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _comment, maxLines: 4, maxLength: 1000, decoration: const InputDecoration(labelText: 'Your review (optional)', border: OutlineInputBorder())),
          if (room > 0) ReviewPhotoPicker(photos: _photos, max: room, onChanged: (p) => setState(() => _photos..clear()..addAll(p)), pick: widget.pickPhoto, title: 'Add photos (optional)'),
          const SizedBox(height: 12),
          Row(children: [
            if (widget.existing != null) TextButton(onPressed: _busy ? null : _delete, child: const Text('Delete review', style: TextStyle(color: Color(0xFFC62828)))),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 24)),
              onPressed: _busy ? null : _submit,
              child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(widget.existing != null ? 'Save' : 'Submit'),
            ),
          ]),
        ]),
      ),
    );
  }
}
