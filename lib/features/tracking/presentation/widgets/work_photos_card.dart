import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../domain/tracking_models.dart';

/// "Work photos": what the technician / driver photographed when the work was done, so the customer can see the
/// result without a call. Hidden when there is nothing. Tap a photo to see it full screen.
class WorkPhotosCard extends StatelessWidget {
  const WorkPhotosCard({super.key, required this.proofs});
  final List<TrackingProof> proofs;

  @override
  Widget build(BuildContext context) {
    if (proofs.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3E8EE))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.photo_library_outlined, size: 20, color: AppColors.navy),
            SizedBox(width: 8),
            Text('Work photos', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navy)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: proofs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _Thumb(proof: proofs[i], onTap: () => _open(context, proofs[i])),
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, TrackingProof p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: p.imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()),
                  errorWidget: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('Could not load the photo.', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                [p.label, if ((p.notes ?? '').isNotEmpty) p.notes!].join('\n'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.proof, required this.onTap});
  final TrackingProof proof;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: proof.imageUrl,
                  width: 110,
                  fit: proof.isSignature ? BoxFit.contain : BoxFit.cover,
                  memCacheWidth: 330,
                  placeholder: (_, __) => const ColoredBox(color: Color(0xFFE3E8EE)),
                  errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFE3E8EE), child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(proof.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
