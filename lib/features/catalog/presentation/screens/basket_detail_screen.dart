import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../data/basket_cart.dart';
import '../../data/basket_models.dart';
import '../../data/marketplace_catalog_repository.dart';

/// Full detail for one Seller Hub combo/bundle offer ("Basket"), laid out like
/// the website's combo page: a photo gallery, a "Bundle deal" header, a fixed
/// combo price card with the saving, and a "What's in this combo" section
/// where each slot lists its products as selectable cards.
///
/// **Known limitation (unchanged):** the vendor's bundle price has no
/// equivalent in this app's cart, which prices each line at its own regular
/// price, so the chosen products are added individually and the combo price is
/// a reference — the note at the bottom says so.
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

  /// Gallery page to bring forward after the customer picks an option.
  int? _focusPage;

  static int? _keyOf(BasketSlotOption? o) => o?.productId ?? o?.id ?? o?.optionId;

  void _ensureDefaultSelections(MarketplaceBasket basket) {
    for (final slot in basket.slots) {
      final slotId = slot.id;
      if (slotId == null || _selections.containsKey(slotId)) continue;
      final key = _keyOf(slot.defaultOption);
      if (key != null) _selections[slotId] = key;
    }
  }

  BasketSlotOption? _selectedOption(BasketSlot slot) {
    if (slot.options.isEmpty) return null;
    final selectedKey = slot.id != null ? _selections[slot.id] : null;
    return slot.options.firstWhere(
      (o) => _keyOf(o) == selectedKey,
      orElse: () => slot.defaultOption ?? slot.options.first,
    );
  }

  /// One photo per slot — the product currently chosen for it — plus fixed
  /// items, so the gallery follows what the customer picks.
  List<String> _galleryFor(MarketplaceBasket basket) {
    final out = <String>[];
    void add(String u) {
      if (u.isNotEmpty && !out.contains(u)) out.add(u);
    }

    add(basket.primaryImage);
    for (final slot in basket.slots) {
      add(_selectedOption(slot)?.coverImage ?? '');
    }
    for (final item in basket.items) {
      add(item.primaryImage);
    }
    return out.isEmpty ? basket.galleryImages : out;
  }

  void _addToCart(MarketplaceBasket basket) {
    final addedCount =
        addComboToCart(ref.read(cartProvider.notifier), basket, _selectedOption);

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
      backgroundColor: AppColors.background,
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
    final pct = basket.savingsPercentRounded;
    final itemCount = basket.slots.isNotEmpty ? basket.slots.length : basket.items.length;
    final meta = <({IconData icon, String text})>[
      if (basket.sellerName.isNotEmpty)
        (icon: Icons.storefront_outlined, text: 'Sold by ${basket.sellerName}'),
      if (basket.warehouseName.isNotEmpty)
        (icon: Icons.local_shipping_outlined, text: 'Ships from ${basket.warehouseName}'),
      if (itemCount > 0)
        (icon: Icons.layers_outlined, text: '$itemCount ${itemCount == 1 ? 'item' : 'items'} included'),
    ];

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _ComboGallery(
                urls: _galleryFor(basket),
                title: basket.title,
                savePercent: pct,
                focusPage: _focusPage,
                onBack: () => context.pop(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        const _Pill(
                          icon: Icons.local_offer_rounded,
                          label: 'BUNDLE DEAL',
                          fg: Color(0xFF6D28D9),
                          bg: Color(0xFFEDE9FE),
                        ),
                        if (basket.isMultiOption)
                          const _Pill(
                            icon: Icons.tune_rounded,
                            label: 'Customizable',
                            fg: Color(0xFFB45309),
                            bg: AppColors.warningLight,
                          ),
                        if (!basket.inStock)
                          const _Pill(
                            icon: Icons.remove_shopping_cart_outlined,
                            label: 'Out of stock',
                            fg: Color(0xFFB91C1C),
                            bg: AppColors.errorLight,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      basket.title,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          for (final m in meta)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(m.icon, size: 14, color: AppColors.textHint),
                                const SizedBox(width: 4),
                                Text(
                                  m.text,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    _PriceCard(basket: basket, savePercent: pct),
                    if (basket.description.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        basket.description,
                        style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.45),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _WhatsInside(
                      basket: basket,
                      itemCount: itemCount,
                      selectedKeyOf: (slot) => slot.id != null ? _selections[slot.id] : null,
                      selectedOptionOf: _selectedOption,
                      onSelect: (index, slot, key) => setState(() {
                        if (slot.id != null) _selections[slot.id!] = key;
                        _focusPage = index + (basket.primaryImage.isNotEmpty ? 1 : 0);
                      }),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
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
            ],
          ),
        ),
        _buildBottomBar(context, basket),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, MarketplaceBasket basket) {
    final price = basket.bundlePrice;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: FilledButton.icon(
          onPressed: basket.inStock ? () => _addToCart(basket) : null,
          icon: const Icon(Icons.shopping_bag_outlined, size: 20),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.groceryGreen,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          label: Text(
            basket.inStock
                ? 'Add Combo to Cart${price != null ? ' • ₹$price' : ''}'
                : 'Out of Stock',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

// ── Gallery ─────────────────────────────────────────────────────────────────

/// Swipeable photo gallery with a thumbnail strip, a SAVE chip and the back
/// button, auto-advancing every few seconds (a touch restarts the countdown).
class _ComboGallery extends StatefulWidget {
  const _ComboGallery({
    required this.urls,
    required this.title,
    required this.onBack,
    this.savePercent,
    this.focusPage,
  });

  final List<String> urls;
  final String title;
  final VoidCallback onBack;
  final int? savePercent;
  final int? focusPage;

  @override
  State<_ComboGallery> createState() => _ComboGalleryState();
}

class _ComboGalleryState extends State<_ComboGallery> {
  final PageController _controller = PageController();
  int _page = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _ComboGallery old) {
    super.didUpdateWidget(old);
    if (_page >= widget.urls.length) _page = 0;
    if (old.urls.length != widget.urls.length) _start();
    final f = widget.focusPage;
    if (f != null && f != old.focusPage && f < widget.urls.length && _controller.hasClients) {
      _controller.animateToPage(f, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    if (widget.urls.length <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients || widget.urls.length <= 1) return;
      _controller.animateToPage(
        (_page + 1) % widget.urls.length,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _image(String? url, {double pad = 20}) => Padding(
        padding: EdgeInsets.all(pad),
        child: AppRemoteImage(
          imageUrl: url,
          rawPath: url,
          title: widget.title,
          categoryName: 'grocery',
          slug: 'seller_hub_groceries',
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.contain,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(
            height: 290 + top,
            child: Stack(
              children: [
                Positioned.fill(
                  top: top,
                  child: urls.length <= 1
                      ? _image(urls.isEmpty ? null : urls.first)
                      : Listener(
                          onPointerDown: (_) => _start(),
                          child: PageView.builder(
                            controller: _controller,
                            itemCount: urls.length,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (_, i) => _image(urls[i]),
                          ),
                        ),
                ),
                Positioned(
                  left: 8,
                  top: top + 6,
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.92),
                    shape: const CircleBorder(),
                    elevation: 1,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy, size: 22),
                      onPressed: widget.onBack,
                    ),
                  ),
                ),
                if (widget.savePercent != null)
                  Positioned(
                    right: 12,
                    top: top + 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'SAVE ${widget.savePercent}%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (urls.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: urls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final selected = i == _page;
                    return GestureDetector(
                      onTap: () {
                        _controller.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                        _start();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected ? AppColors.groceryGreen : AppColors.border,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _image(urls[i], pad: 4),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Header pieces ───────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.fg, required this.bg});

  final IconData icon;
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.basket, required this.savePercent});

  final MarketplaceBasket basket;
  final int? savePercent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8FB)),
        boxShadow: const [
          BoxShadow(color: Color(0x0F6D28D9), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'FIXED COMBO PRICE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: Color(0xFF6D28D9),
                  ),
                ),
              ),
              if (basket.hasSavings)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: Text(
                    'You save ₹${basket.savings}${savePercent != null ? ' ($savePercent%)' : ''}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (basket.bundlePrice != null)
                Text(
                  '₹${basket.bundlePrice}',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.navy),
                ),
              if (basket.hasSavings && basket.mrpTotal != null) ...[
                const SizedBox(width: 10),
                Text(
                  'MRP ₹${basket.mrpTotal}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textHint,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Inclusive of all taxes',
            style: TextStyle(fontSize: 11.5, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}

// ── What's in this combo ────────────────────────────────────────────────────

class _WhatsInside extends StatelessWidget {
  const _WhatsInside({
    required this.basket,
    required this.itemCount,
    required this.selectedKeyOf,
    required this.selectedOptionOf,
    required this.onSelect,
  });

  final MarketplaceBasket basket;
  final int itemCount;
  final int? Function(BasketSlot slot) selectedKeyOf;
  final BasketSlotOption? Function(BasketSlot slot) selectedOptionOf;
  final void Function(int index, BasketSlot slot, int key) onSelect;

  @override
  Widget build(BuildContext context) {
    final visibleSlots = basket.slots.where((s) => s.options.isNotEmpty).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "What's in this combo",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navy),
                ),
              ),
              if (basket.isMultiOption)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE9FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Tap to customize',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF6D28D9)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$itemCount ${itemCount == 1 ? 'item' : 'items'} configured',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < visibleSlots.length; i++)
            _SlotCard(
              number: i + 1,
              slot: visibleSlots[i],
              selectedKey: selectedKeyOf(visibleSlots[i]),
              onSelect: (key) => onSelect(i, visibleSlots[i], key),
            ),
          // The confirmed list: what the customer has actually picked for each
          // slot (it changes as they choose), plus any extra fixed product.
          ..._confirmedItems(visibleSlots),
        ],
      ),
    );
  }

  List<Widget> _confirmedItems(List<BasketSlot> visibleSlots) {
    final items = <BasketItem>[];
    final slotDefaultTitles = <String>{};
    for (final slot in basket.slots) {
      final d = slot.defaultOption?.title;
      if (d != null) slotDefaultTitles.add(d);
      final o = selectedOptionOf(slot);
      if (o == null) continue;
      items.add(BasketItem(
        productId: o.productId ?? o.id,
        productTitle: o.title,
        quantity: slot.quantity,
        unit: o.unit,
        packSize: o.packSize,
        mrp: o.mrp,
        unitPrice: o.sellingPrice,
        primaryImage: o.coverImage,
      ));
    }
    for (final fixed in basket.items) {
      if (!slotDefaultTitles.contains(fixed.productTitle)) items.add(fixed);
    }
    if (items.isEmpty) return const [];
    return [
      const SizedBox(height: 6),
      Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.groceryGreen),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Your combo \u00b7 ${items.length} ${items.length == 1 ? 'item' : 'items'} confirmed',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      for (final item in items) _FixedItemCard(item: item),
    ];
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.number,
    required this.slot,
    required this.selectedKey,
    required this.onSelect,
  });

  final int number;
  final BasketSlot slot;
  final int? selectedKey;
  final ValueChanged<int> onSelect;

  static int? _keyOf(BasketSlotOption o) => o.productId ?? o.id ?? o.optionId;

  @override
  Widget build(BuildContext context) {
    final multi = slot.isMultiOption;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Color(0xFF6D28D9), shape: BoxShape.circle),
                child: Text(
                  '$number',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  slot.slotTitle.isNotEmpty ? slot.slotTitle : 'Item $number',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.navy),
                ),
              ),
              if (multi)
                _MiniChip(
                  text: 'Choose 1 of ${slot.options.length}',
                  bg: const Color(0xFFEDE9FE),
                  fg: const Color(0xFF6D28D9),
                ),
              const SizedBox(width: 6),
              _MiniChip(text: 'Qty: ${slot.quantity}', bg: Colors.white, fg: AppColors.navy, border: true),
            ],
          ),
          const SizedBox(height: 10),
          for (final option in slot.options)
            _OptionTile(
              option: option,
              selectable: multi,
              selected: !multi || (_keyOf(option) != null && _keyOf(option) == selectedKey),
              onTap: (!multi || !option.inStock || _keyOf(option) == null)
                  ? null
                  : () => onSelect(_keyOf(option)!),
            ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text, required this.bg, required this.fg, this.border = false});

  final String text;
  final Color bg;
  final Color fg;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: border ? Border.all(color: AppColors.border) : null,
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

/// One product choice inside a slot: radio, photo, name, brand / pack and
/// price. The chosen one gets a green border and tint.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selectable,
    required this.selected,
    required this.onTap,
  });

  final BasketSlotOption option;
  final bool selectable;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final out = !option.inStock;
    final sub = [
      if (option.brand.isNotEmpty) option.brand,
      if (option.packSize.isNotEmpty) option.packSize else if (option.unit.isNotEmpty) option.unit,
    ].join(' • ');
    final selling = option.sellingPrice;
    final mrp = option.mrp;
    final showMrp = mrp != null && selling != null && mrp > selling;

    return Opacity(
      opacity: out ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selectable && selected ? AppColors.groceryGreenLight : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selectable && selected ? AppColors.groceryGreen : AppColors.border,
              width: selectable && selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              if (selectable) ...[
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? AppColors.groceryGreen : AppColors.textHint,
                ),
                const SizedBox(width: 8),
              ],
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(4),
                child: AppRemoteImage(
                  imageUrl: option.coverImage,
                  rawPath: option.coverImage,
                  title: option.title,
                  categoryName: 'grocery',
                  slug: 'seller_hub_groceries',
                  width: 46,
                  height: 46,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 3),
                    if (out)
                      const Text(
                        'Out of stock',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.error),
                      )
                    else
                      Row(
                        children: [
                          if (selling != null)
                            Text(
                              '₹$selling',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          if (showMrp) ...[
                            const SizedBox(width: 6),
                            Text(
                              'MRP ₹$mrp',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FixedItemCard extends StatelessWidget {
  const _FixedItemCard({required this.item});

  final BasketItem item;

  @override
  Widget build(BuildContext context) {
    final sub = [
      if (item.packSize.isNotEmpty) item.packSize else if (item.unit.isNotEmpty) item.unit,
    ].join();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(4),
            child: AppRemoteImage(
              imageUrl: item.primaryImage,
              rawPath: item.primaryImage,
              title: item.productTitle,
              categoryName: 'grocery',
              slug: 'seller_hub_groceries',
              width: 46,
              height: 46,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.navy),
                ),
                if (sub.isNotEmpty)
                  Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          _MiniChip(text: 'Qty: ${item.quantity}', bg: Colors.white, fg: AppColors.navy, border: true),
        ],
      ),
    );
  }
}
