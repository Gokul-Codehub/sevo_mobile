import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../shared/theme/app_colors.dart';
import '../../../../shared/utils/app_toast.dart';
import '../../../../shared/widgets/app_remote_image.dart';
import '../../../booking/domain/cart_notifier.dart';
import '../../data/marketplace_catalog_repository.dart';
import '../../data/recipe_models.dart';
import '../../data/recipe_repository.dart';
import '../../domain/catalog_models.dart';

const Color _green = Color(0xFF157038);
const Color _greenSoft = Color(0xFFE6F2EA);

/// Recipe page: what the dish needs, with the matching Seller Hub products
/// right there to add to the cart, then the numbered cooking steps.
/// Mirrors the web "Recipe Detail" page (Ingredients & Pantry + Cooking
/// Instructions); the cart is the app's normal cart, so everything added here
/// shows up in Cart / checkout like any other grocery item.
class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({super.key, required this.recipeKey});

  /// Recipe slug (or numeric id).
  final String recipeKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipeDetailProvider(recipeKey));
    final recipe = async.valueOrNull;
    final cartCount = ref.watch(cartProvider).fold<int>(0, (sum, i) => sum + i.quantity);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.restaurant_menu_rounded, size: 16, color: _green),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                recipe?.title ?? 'Recipe',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        actions: [
          if (recipe != null)
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share_outlined, size: 20, color: AppColors.textPrimary),
              onPressed: () => Share.share(
                'Check out this ${recipe.title} recipe on SEVO: https://sevo.co.in/marketplace/recipe/${recipe.slug.isNotEmpty ? recipe.slug : recipe.id}',
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _CartPill(count: cartCount, onTap: () => context.push('/cart')),
          ),
        ],
      ),
      body: async.when(
        loading: () => const _RecipeSkeleton(),
        error: (_, __) => _RecipeMessage(
          icon: Icons.wifi_off_rounded,
          title: 'Couldn\'t load this recipe',
          message: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(recipeDetailProvider(recipeKey)),
        ),
        data: (r) => r == null
            ? _RecipeMessage(
                icon: Icons.search_off_rounded,
                title: 'Recipe not found',
                message: 'This recipe is not available right now.',
                actionLabel: 'Go back',
                onAction: () => context.canPop() ? context.pop() : context.go('/'),
              )
            : _RecipeBody(recipe: r),
      ),
      bottomNavigationBar: cartCount > 0 ? _CartBar(count: cartCount) : null,
    );
  }
}

// ───────────────────────── body ─────────────────────────

class _RecipeBody extends ConsumerWidget {
  const _RecipeBody({required this.recipe});

  final RecipeDetail recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    int qtyOf(ServiceItem s) =>
        cart.where((i) => i.service.id == s.id && !i.isComboLine).fold<int>(0, (a, i) => a + i.quantity);

    // Ingredients that can be added in one tap: in stock, not optional, not yet in the cart.
    final addable = [
      for (final ing in recipe.ingredients)
        if (!ing.isOptional && ing.canOrder && qtyOf(ing.product!.toServiceItem()) == 0) ing.product!,
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 28 + MediaQuery.paddingOf(context).bottom),
      children: [
        _Hero(recipe: recipe),
        const SizedBox(height: 26),
        Row(
          children: [
            const Icon(Icons.restaurant_rounded, size: 20, color: _green),
            const SizedBox(width: 8),
            const Text(
              'Ingredients & Pantry',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 8),
            _Chip('${recipe.ingredients.length} items'),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Tap Add on a matching fresh product to have it delivered to your door.',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
        ),
        if (recipe.orderableCount > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.groceryGreenLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.groceryGreenTint),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 16, color: _green),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${recipe.orderableCount} items ready to order',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _green),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (addable.length > 1) ...[
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () {
                    final notifier = ref.read(cartProvider.notifier);
                    for (final p in addable) {
                      notifier.addService(p.toServiceItem());
                    }
                    AppToast.show(context, '${addable.length} ingredients added to cart');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    side: const BorderSide(color: _green),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Add all (${addable.length})',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (recipe.ingredients.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No specific ingredients listed.',
              style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
            ),
          )
        else
          for (var i = 0; i < recipe.ingredients.length; i++) ...[
            _IngredientCard(index: i + 1, ingredient: recipe.ingredients[i]),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 18),
        Row(
          children: [
            const Icon(Icons.soup_kitchen_rounded, size: 20, color: _green),
            const SizedBox(width: 8),
            const Text(
              'Cooking Instructions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 8),
            _Chip('${recipe.steps.length} steps'),
          ],
        ),
        const SizedBox(height: 14),
        if (recipe.steps.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: _cardDecoration(),
            child: const Center(
              child: Text(
                'No steps available for this recipe yet.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          )
        else
          for (final s in recipe.steps) ...[
            _StepCard(step: s),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    );

// ───────────────────────── hero ─────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.recipe});

  final RecipeDetail recipe;

  @override
  Widget build(BuildContext context) {
    final diet = _dietStyle(recipe.diet);
    final inStock = recipe.orderableCount;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration().copyWith(borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: AppColors.surfaceVariant,
                    child: AppRemoteImage(imageUrl: recipe.coverImage, title: recipe.title, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: diet.color, width: 1.5),
                      ),
                      child: Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: diet.color, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: diet.bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: diet.color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: diet.color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(diet.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: diet.color)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(20)),
                child: const Text(
                  'Cook at Home',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            recipe.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, height: 1.2, color: AppColors.textPrimary),
          ),
          if (recipe.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              recipe.description,
              style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) {
              final w = (box.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (recipe.cookTimeMinutes > 0)
                    _Metric(
                      width: w,
                      icon: Icons.schedule_rounded,
                      tint: const Color(0xFFD1FAE5),
                      iconColor: const Color(0xFF047857),
                      label: 'COOK TIME',
                      value: '${recipe.cookTimeMinutes} mins',
                    ),
                  if (recipe.kcal > 0)
                    _Metric(
                      width: w,
                      icon: Icons.local_fire_department_rounded,
                      tint: const Color(0xFFFEF3C7),
                      iconColor: const Color(0xFFF59E0B),
                      label: 'CALORIES',
                      value: '${recipe.kcal} kcal',
                    ),
                  if (recipe.servings > 0)
                    _Metric(
                      width: w,
                      icon: Icons.people_alt_outlined,
                      tint: const Color(0xFFDBEAFE),
                      iconColor: const Color(0xFF1D4ED8),
                      label: 'SERVINGS',
                      value: '${recipe.servings} people',
                    ),
                  _Metric(
                    width: w,
                    icon: Icons.shopping_bag_outlined,
                    tint: const Color(0xFFF3E8FF),
                    iconColor: const Color(0xFF7E22CE),
                    label: 'SHOP ITEMS',
                    value: '$inStock in stock',
                    valueColor: _green,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DietStyle {
  const _DietStyle(this.label, this.color, this.bg);
  final String label;
  final Color color;
  final Color bg;
}

_DietStyle _dietStyle(RecipeDiet d) {
  switch (d) {
    case RecipeDiet.veg:
      return const _DietStyle('Vegetarian', Color(0xFF059669), Color(0xFFECFDF5));
    case RecipeDiet.nonVeg:
      return const _DietStyle('Non-Vegetarian', Color(0xFFE11D48), Color(0xFFFFF1F2));
    case RecipeDiet.egg:
      return const _DietStyle('Contains Egg', Color(0xFFB45309), Color(0xFFFFFBEB));
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueColor = AppColors.textPrimary,
  });

  final double width;
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 9.5, letterSpacing: 0.6, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: valueColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── ingredients ─────────────────────────

class _IngredientCard extends ConsumerWidget {
  const _IngredientCard({required this.index, required this.ingredient});

  final int index;
  final RecipeIngredient ingredient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ingredient.product;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.surfaceVariant, shape: BoxShape.circle),
                child: Text(
                  '$index',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ingredient.name,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        children: [
                          const TextSpan(text: 'Quantity: '),
                          TextSpan(
                            text: ingredient.quantity.isEmpty ? 'As needed' : ingredient.quantity,
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (ingredient.isOptional)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Text(
                    'Optional',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (product == null)
            const Text(
              'Standard pantry / kitchen item',
              style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: AppColors.textHint),
            )
          else
            _LinkedProductRow(product: product),
        ],
      ),
    );
  }
}

class _LinkedProductRow extends ConsumerWidget {
  const _LinkedProductRow({required this.product});

  final MarketplaceProduct product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = product.toServiceItem();
    final qty = ref
        .watch(cartProvider)
        .where((i) => i.service.id == service.id && !i.isComboLine)
        .fold<int>(0, (a, i) => a + i.quantity);
    final notifier = ref.read(cartProvider.notifier);
    final unit = (product.variantLabel ?? product.packSize ?? product.unit ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.push('/products/${service.slug}', extra: service),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 52,
                height: 52,
                color: Colors.white,
                child: AppRemoteImage(imageUrl: product.primaryImage, title: product.title, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/products/${service.slug}', extra: service),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.25, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      if (unit.isNotEmpty)
                        Text(unit, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                      Text(
                        '₹${product.sellingPrice}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                      ),
                      if (product.hasStrikeThroughMrp)
                        Text(
                          '₹${product.mrp}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textHint,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!product.inStock)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(9)),
              child: const Text(
                'Out of stock',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
              ),
            )
          else if (qty == 0)
            FilledButton.icon(
              onPressed: () {
                notifier.addService(service);
                AppToast.addedToCart(context, product.title);
              },
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(11)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Step(icon: Icons.remove_rounded, onTap: () => notifier.updateQuantity(service.id, qty - 1)),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '$qty',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  _Step(
                    icon: Icons.add_rounded,
                    onTap: () {
                      if (service.maxQuantity > 0 && qty >= service.maxQuantity) {
                        AppToast.show(context, 'Only ${service.maxQuantity} in stock', type: AppToastType.error);
                        return;
                      }
                      notifier.updateQuantity(service.id, qty + 1);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(width: 32, height: 36, child: Icon(icon, size: 17, color: Colors.white)),
    );
  }
}

// ───────────────────────── steps ─────────────────────────

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step});

  final RecipeStep step;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF10B981), Color(0xFF0D9488)],
              ),
            ),
            child: Text(
              '${step.number}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STEP ${step.number}',
                  style: const TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: Color(0xFF047857)),
                ),
                const SizedBox(height: 5),
                Text(
                  step.instruction,
                  style: const TextStyle(fontSize: 14, height: 1.55, color: Color(0xFF334155)),
                ),
                if ((step.image ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: AppRemoteImage(imageUrl: step.image, title: 'Step ${step.number}', fit: BoxFit.cover),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── small pieces ─────────────────────────

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
      ),
    );
  }
}

class _CartPill extends StatelessWidget {
  const _CartPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shopping_bag_outlined, size: 16, color: Colors.white),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '$count',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: _green),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cart Total', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  const SizedBox(height: 1),
                  Text(
                    '$count ${count == 1 ? 'item' : 'items'}',
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => context.push('/cart'),
              icon: const Text('View Cart', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              label: const Icon(Icons.chevron_right_rounded, size: 18),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: const Color(0xFF022C22),
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeSkeleton extends StatelessWidget {
  const _RecipeSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double? w, double r = 14}) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(color: const Color(0xFFE8EDF3), borderRadius: BorderRadius.circular(r)),
        );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        AspectRatio(aspectRatio: 4 / 3, child: box(0, r: 20)),
        const SizedBox(height: 16),
        box(28, w: 220),
        const SizedBox(height: 10),
        box(14),
        const SizedBox(height: 6),
        box(14, w: 260),
        const SizedBox(height: 20),
        Row(children: [Expanded(child: box(56)), const SizedBox(width: 10), Expanded(child: box(56))]),
        const SizedBox(height: 22),
        box(90, r: 18),
        const SizedBox(height: 12),
        box(90, r: 18),
      ],
    );
  }
}

class _RecipeMessage extends StatelessWidget {
  const _RecipeMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, size: 30, color: const Color(0xFFE11D48)),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
