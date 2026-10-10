import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../data/basket_models.dart';
import '../../data/marketplace_catalog_repository.dart';

/// Full detail for one Seller Hub combo/bundle offer ("Basket") — shows the
/// bundle price vs. the combined MRP, lets the customer pick one product
/// for each multi-option slot (e.g. "Any 1kg rice brand"), and adds the
/// resolved components to the cart.
///
/// Added 2026-10-08. **Known limitation, by design for this first cut**:
/// the vendor's bundle pricing (`bundle_price` — one all-in price for the
/// whole combo, cheaper than its parts) has no equivalent in this app's
/// cart/checkout model, which only knows how to price each line item at
/// its own regular price (see `cart_notifier.dart` / `CartSummary`).
/// Building true bundle-priced checkout would mean new backend + checkout
/// schema work beyond this scope. The pragmatic compromise taken here:
/// resolved components go into the SAME cart as individually-priced items
/// (merging with any matching quantity already in the cart — see
/// `basket_models.dart`'s `_basketCartIdOffset` doc comment), and the
/// screen is upfront that the combo price shown is a reference, not what
/// checkout will charge.
class BasketDetailScreen extends ConsumerStatefulWidget {
  const BasketDetailScreen({super.key, required this.basketId, this.initialBasket});

  final int basketId;
  final MarketplaceBasket? initialBasket;

  @override
  ConsumerState<BasketDetailScreen> createState() => _BasketDetailScreenState();
}

class _BasketDetailScreenState extends ConsumerState<BasketDetailScreen> {
  /// slotId -> selected option's productId (or option id when no productId).
  final Map<int, int> _selections = {};

  void _ensureDefaultSelections(MarketplaceBasket basket) {
    for (final slot in basket.slots) {
      final slotId = slot.id;
      if (slotId == null || _selections.containsKey(slotId)) continue;
      final defaultOption = slot.defaultOption;
      final key = defaultOption?.productId ?? defaultOption?.id ?? defaultOption?.optionId;
      if (key != null) _selections[slotId] = key;
    }
  }

  void _addToCart(MarketplaceBasket basket) {
    final cart = ref.read(cartProvider.notifier);
    var addedCount = 0;

    for (final slot in basket.slots) {
      final selectedKey = slot.id != null ? _selections[slot.id] : null;
      final chosen = slot.options.isEmpty
          ? null
          : slot.options.firstWhere(
              (o) => (o.productId ?? o.id ?? o.optionId) == selectedKey,
              orElse: () => slot.defaultOption ?? slot.options.first,
            );
      final item = chosen?.toServiceItem();
      if (item != null) {
        cart.addService(item, quantity: slot.quantity);
        addedCount++;
      }
    }

    for (final basketItem in basket.items) {
      final item = basketItem.toServiceItem();
      if (item != null) {
        cart.addService(item, quantity: basketItem.quantity);
        addedCount++;
      }
    }

    if (!mounted) return;
    if (addedCount > 0) {
      AppToast.addedToCart(context, basket.title);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This combo's items aren't available right now")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(marketplaceBasketDetailProvider(widget.basketId));

    return Scaffold(
      backgroundColor: Colors.white,
      body: detailAsync.when(
        data: (fetched) {
          final basket = fetched ?? widget.initialBasket;
          if (basket == null) {
            return _buildError(context, "This combo offer isn't available anymore");
          }
          _ensureDefaultSelections(basket);
          return _buildBody(context, basket);
        },
        loading: () {
          final basket = widget.initialBasket;
          if (basket != null) {
            _ensureDefaultSelections(basket);
            return _buildBody(context, basket);
          }
          return const Center(child: CircularProgressIndicator());
        },
        error: (_, __) {
          final basket = widget.initialBasket;
          if (basket != null) {
            _ensureDefaultSelections(basket);
            return _buildBody(context, basket);
          }
          return _buildError(context, "Couldn't load this combo offer");
        },
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
              onPressed: () => context.pop(),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(message, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, MarketplaceBasket basket) {
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                backgroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                  ),
                  onPressed: () => context.pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    color: AppColors.surfaceVariant,
                    child: AppRemoteImage(
                      imageUrl: basket.primaryImage,
                      rawPath: basket.primaryImage,
                      title: basket.title,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        basket.title,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.navy),
                      ),
                      if (basket.sellerName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Sold by ${basket.sellerName}',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          if (basket.bundlePrice != null)
                            Text(
                              '₹${basket.bundlePrice}',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                            ),
                          if (basket.hasSavings && basket.mrpTotal != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '₹${basket.mrpTotal}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textHint,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (basket.hasSavings) ...[
                        const SizedBox(height: 4),
                        Text(
                          'You save ₹${basket.savings} on this combo',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.groceryGreenDark),
                        ),
                      ],
                      if (basket.description.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          basket.description,
                          style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
                        ),
                      ],
                      const SizedBox(height: 18),
                      const Divider(color: AppColors.divider),
                      const SizedBox(height: 14),
                      const Text(
                        "What's in this combo",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy),
                      ),
                      const SizedBox(height: 10),
                      ...basket.slots.map((slot) => _SlotPicker(
                            slot: slot,
                            selectedKey: slot.id != null ? _selections[slot.id] : null,
                            onSelect: (key) => setState(() {
                              if (slot.id != null) _selections[slot.id!] = key;
                            }),
                          )),
                      ...basket.items.map((item) => _FixedItemRow(item: item)),
                      const SizedBox(height: 12),
                      // Honest about the one real limitation of this feature
                      // (see this screen's doc comment) rather than letting
                      // the customer think checkout will charge the combo
                      // price shown above.
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondary),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Combo items are added to your cart at their own regular prices — the combo total above is Seller Hub's reference price for this offer.",
                                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildBottomBar(context, basket),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, MarketplaceBasket basket) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: FilledButton(
          onPressed: basket.inStock ? () => _addToCart(basket) : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.groceryGreen,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(
            basket.inStock ? 'Add Combo to Cart' : 'Out of Stock',
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _SlotPicker extends StatelessWidget {
  const _SlotPicker({required this.slot, required this.selectedKey, required this.onSelect});

  final BasketSlot slot;
  final int? selectedKey;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (slot.options.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slot.slotTitle.isNotEmpty ? slot.slotTitle : 'Choose 1',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy),
          ),
          const SizedBox(height: 8),
          if (slot.isMultiOption)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: slot.options.map((option) {
                final key = option.productId ?? option.id ?? option.optionId;
                final isSelected = key != null && key == selectedKey;
                final outOfStock = !option.inStock;
                return GestureDetector(
                  onTap: (outOfStock || key == null) ? null : () => onSelect(key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary.withOpacity(0.12) : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
                    ),
                    child: Text(
                      option.title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: outOfStock
                            ? AppColors.textHint
                            : isSelected
                                ? AppColors.primary
                                : AppColors.navy,
                      ),
                    ),
                  ),
                );
              }).toList(),
            )
          else
            _FixedOptionRow(option: slot.options.first, quantity: slot.quantity),
        ],
      ),
    );
  }
}

class _FixedOptionRow extends StatelessWidget {
  const _FixedOptionRow({required this.option, required this.quantity});

  final BasketSlotOption option;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AppRemoteImage(
            imageUrl: option.primaryImage,
            rawPath: option.primaryImage,
            title: option.title,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${option.title} × $quantity',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _FixedItemRow extends StatelessWidget {
  const _FixedItemRow({required this.item});

  final BasketItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AppRemoteImage(
              imageUrl: item.primaryImage,
              rawPath: item.primaryImage,
              title: item.productTitle,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${item.productTitle} × ${item.quantity}',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
