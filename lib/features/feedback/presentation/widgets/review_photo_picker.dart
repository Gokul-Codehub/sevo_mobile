import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';

/// "Add photos (optional)" for a review: up to [max] photos from the camera or gallery. The parent owns the list
/// and uploads it after the rating is saved.
class ReviewPhotoPicker extends StatelessWidget {
  const ReviewPhotoPicker({
    super.key,
    required this.photos,
    required this.onChanged,
    this.max = 3,
    this.pick,
    this.title = 'Add photos (optional)',
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  final List<XFile> photos;
  final ValueChanged<List<XFile>> onChanged;
  final int max;

  /// Test seam: replaces the system picker.
  final Future<XFile?> Function(ImageSource source)? pick;

  Future<void> _add(BuildContext context) async {
    if (photos.length >= max) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;
    try {
      final x = await (pick != null ? pick!(source) : ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85));
      if (x == null) return;
      if (await x.length() > 5 * 1024 * 1024) {
        if (context.mounted) AppToast.show(context, 'Each photo must be under 5 MB.', type: AppToastType.error);
        return;
      }
      onChanged([...photos, x]);
    } catch (_) {
      if (context.mounted) AppToast.show(context, 'Could not open the photo.', type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy)),
        const SizedBox(height: 4),
        Text('${subtitle ?? 'Show the finished work.'} Up to $max photos.', style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 10),
        SizedBox(
          height: 78,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < photos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(photos[i].path), width: 78, height: 78, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(width: 78, height: 78, child: ColoredBox(color: Color(0xFFE3E8EE), child: Icon(Icons.image)))),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        key: Key('remove_photo_$i'),
                        onTap: () => onChanged([...photos]..removeAt(i)),
                        child: const CircleAvatar(radius: 11, backgroundColor: Colors.black87, child: Icon(Icons.close, size: 14, color: Colors.white)),
                      ),
                    ),
                  ]),
                ),
              if (photos.length < max)
                InkWell(
                  key: const Key('add_photo'),
                  onTap: () => _add(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                    child: const Icon(Icons.add_a_photo_outlined, color: AppColors.navy),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
