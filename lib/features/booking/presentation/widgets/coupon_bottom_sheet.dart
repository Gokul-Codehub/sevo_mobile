import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_error.dart';
import '../../../../shared/theme/app_colors.dart';
import '../../data/coupon_repository.dart';

/// Result handed back to the caller after a coupon is successfully applied
/// — the discount amount always comes from the server's own validation
/// response, never guessed client-side.
class AppliedCoupon {
  const AppliedCoupon({
    required this.code,
    required this.discountAmount,
  });

  final String code;
  final Decimal discountAmount;
}

/// Screen 15: Apply Coupon Bottom Sheet
///
/// Fixed 2026-09-16: this used to show three hardcoded coupons
/// (FIRSTSEVO / SEVOPRO / FREESHIP) with made-up discount amounts, and
/// accepted ANY typed text as a "valid" code with a guessed ₹50 discount —
/// there was no real coupon system at all, and it could never reflect
/// whatever coupons the admin actually publishes. This now lists the
/// real, live, admin-published coupons from GET /customer/coupons/ and
/// validates every applied code against POST /customer/coupons/validate/
/// (service_requests/views.py: CustomerCouponListView /
/// CustomerCouponValidateView) — a coupon can only be "applied" once the
/// server itself confirms it's valid for the real cart total and returns
/// the real discount amount.
class CouponBottomSheet extends ConsumerStatefulWidget {
  const CouponBottomSheet({
    super.key,
    required this.cartTotal,
    this.currentCode,
  });

  /// The real cart/order subtotal at the moment the sheet opens — required
  /// by the backend to check each coupon's minimum-booking rule and to
  /// compute the real discount.
  final Decimal cartTotal;
  final String? currentCode;

  static Future<AppliedCoupon?> show(
    BuildContext context, {
    required Decimal cartTotal,
    String? currentCode,
  }) {
    return showModalBottomSheet<AppliedCoupon>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CouponBottomSheet(
        cartTotal: cartTotal,
        currentCode: currentCode,
      ),
    );
  }

  @override
  ConsumerState<CouponBottomSheet> createState() => _CouponBottomSheetState();
}

class _CouponBottomSheetState extends ConsumerState<CouponBottomSheet> {
  final _controller = TextEditingController();
  String? _errorMessage;
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentCode != null) {
      _controller.text = widget.currentCode!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _applyCode(String code) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      setState(() => _errorMessage = 'Please enter a valid coupon code.');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isValidating = true;
    });

    final repo = ref.read(couponRepositoryProvider);
    final result = await repo.validateCoupon(
      code: cleanCode,
      cartTotal: widget.cartTotal,
    );

    if (!mounted) return;
    setState(() => _isValidating = false);

    switch (result) {
      case Success(:final data):
        Navigator.of(context).pop(
          AppliedCoupon(
            code: data.couponCode.isNotEmpty ? data.couponCode : cleanCode,
            discountAmount: data.discountAmount,
          ),
        );
      case Failure(:final error):
        setState(() => _errorMessage = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final couponsAsync = ref.watch(availableCouponsProvider);

    // Fixed 2026-10-07 ("the promo/coupons model is not showing up instead
    // it show little dark [box]"): the `Flexible` around the coupon list
    // below sits in a `Column` with `mainAxisSize.min`, but
    // `showModalBottomSheet` never gives this content a bounded height —
    // `Flexible`/`Expanded` need a finite main-axis constraint from their
    // parent, so layout threw mid-build (RenderFlex "incoming height
    // constraints are unbounded") and every render object downstream
    // (the sheet's own rounded shape, the barrier, the tap handler) failed
    // to lay out, which is what rendered as a tiny broken dark box instead
    // of the sheet. Capping the sheet's own height here gives `Flexible` a
    // real, finite bound to shrink/scroll within.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Apply Coupon',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Code Input Field
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _errorMessage != null
                              ? AppColors.error
                              : AppColors.border,
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        controller: _controller,
                        textCapitalization: TextCapitalization.characters,
                        enabled: !_isValidating,
                        decoration: const InputDecoration(
                          hintText: 'Enter coupon code',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: AppColors.textHint,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Fixed 2026-10-07 — second, separate crash in this same
                  // sheet ("BoxConstraints forces an infinite width" /
                  // RenderConstrainedBox(w=Infinity, h=50.0), cascading up
                  // through the button's Material/ink render objects):
                  // a bare `SizedBox(height: 50, child: ElevatedButton(...))`
                  // sitting directly in a `Row` with no `Expanded`/`Flexible`
                  // gets an UNBOUNDED (infinite) max-width constraint from
                  // the Row for sizing — completely normal Flutter behavior
                  // for a non-flex Row child, but the button's internal
                  // Material tap-target padding then fails to resolve a
                  // size under that infinite width. Wrapping it in
                  // `IntrinsicWidth` forces a real, finite width (computed
                  // from the button's own content) before that unbounded
                  // constraint ever reaches it.
                  IntrinsicWidth(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isValidating
                            ? null
                            : () => _applyCode(_controller.text),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        child: _isValidating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Apply',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Available Coupons Section
              const Text(
                'Available Coupons',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 12),

              Flexible(
                child: couponsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (err, st) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Could not load coupons right now. You can still enter a code above.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ),
                  data: (coupons) {
                    if (coupons.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No coupons available right now.',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                        ),
                      );
                    }
                    return SingleChildScrollView(
                      child: Column(
                        children: coupons.map((coupon) {
                          final isSelected = widget.currentCode?.toUpperCase() ==
                              coupon.code.toUpperCase();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFF0FDF4)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: isSelected ? 1.5 : 0.8,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.3),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        coupon.code,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primary,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: _isValidating
                                          ? null
                                          : () => _applyCode(coupon.code),
                                      child: Text(
                                        isSelected ? 'APPLIED' : 'APPLY',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: isSelected
                                              ? AppColors.primary
                                              : AppColors.navy,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  coupon.title,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.navy,
                                  ),
                                ),
                                if (coupon.description.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    coupon.description,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  coupon.subtitle,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textHint,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
