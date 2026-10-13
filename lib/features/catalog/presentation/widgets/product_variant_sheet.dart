import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../domain/catalog_models.dart';
import 'product_card.dart';

/// BigBasket-style size picker for a product that comes in several packs
/// (250 ml / 500 ml, 1 kg / 5 kg ...). Opened from the pack-size chip on a
/// grocery [ProductCard]; each pack is a row with its photo, price, MRP and
/// its own Add / stepper (the same cart control the cards use). A pack that is
/// out of stock shows "Sold out".
Future<void> showProductVariantSheet(BuildContext context, ServiceItem product) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _VariantSheet(product: product),
  );
}

class _VariantSheet extends ConsumerWidget {
  const _VariantSheet({required this.product});

  final ServiceItem product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = product.variantOptions.isNotEmpty ? product.variantOptions : [product];
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Close button floating above the sheet.
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: const BoxDecoration(color: Color(0xFF3A3A3A), shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
            ),
          ),
          Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select pack size',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _VariantRow(
                      option: options[i],
                      isCurrent: options[i].id == product.id,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({required this.option, required this.isCurrent});

  final ServiceItem option;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final soldOut = !option.inStock;
    final pct = option.discountPercent;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent ? AppColors.groceryGreen : AppColors.border,
          width: isCurrent ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: AppRemoteImage(
                  imageUrl: option.imageUrl,
                  rawPath: option.imageUrl,
                  title: option.title,
                  categoryName: option.categorySlug,
                  slug: option.categorySlug,
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                ),
              ),
              if (soldOut)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: const Color(0xCC1F2937),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: const Text(
                      'Sold out',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.displayUnit,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '₹${option.effectivePrice}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (option.hasDiscount) ...[
                      const SizedBox(width: 6),
                      Text(
                        '₹${option.price}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textHint,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ],
                ),
                if (option.hasDiscount && pct != null)
                  Text(
                    '$pct% OFF',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.groceryGreenDark,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Add / stepper — or "Sold out" when the pack is unavailable.
          soldOut
              ? const Text(
                  'Sold out',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHint),
                )
              : QuickAddControl(service: option),
        ],
      ),
    );
  }
}
